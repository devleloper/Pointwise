# Architecture

Pointwise is a menu bar app with two independent engines — pointer tracking and wheel scrolling — driven by one settings model. This document explains how they work, why they are built this way, and which alternatives were rejected.

## Layout

```
Packages/PointwiseCore/          Pure Swift, Foundation only, fully unit-tested
  Models/                        AppSettings, PointerSettings, ScrollSettings, DeviceIdentity/Rule
  Pointer/                       PointerAccelerationModel: macOS's curve math, for drawing
  Scroll/                        ScrollEventKind, WheelSpeedEstimator, ScrollAccelerationCurve,
                                 GlideAnimator, FractionAccumulator, WheelScroller
  Persistence/                   SettingsStore (versioned JSON in UserDefaults)
Pointwise/                       The app
  App/                           PointwiseApp (MenuBarExtra, AppDelegate), AppModel, Log,
                                 DebugSnapshots (Debug only)
  Services/                      Thin adapters over macOS APIs:
                                 PointerService (IOHIDEventSystemClient), DeviceMonitor (IOHIDManager),
                                 ScrollEventTap (CGEventTap), SystemIntegration (TCC, SMAppService)
  UI/                            SwiftUI: SettingsView and its panes, charts, menu, welcome
  Resources/                     Asset catalog, Localizable.xcstrings (English, Russian)
```

Rules that keep it simple:

- Decisions live in `PointwiseCore` as value types with tests; services only translate between them and macOS.
- One owner per piece of state: `AppModel` (main actor) owns settings and services; the scroll tap's state is confined to its own thread.
- No abstractions with a single implementation, no dependency injection framework, no third-party packages.

## Settings flow

```
SwiftUI control ──binding──▶ AppModel.update { … }
                               ├─ SettingsStore.save (JSON, versioned, tolerant decoding)
                               ├─ PointerService.apply(rule per device)
                               └─ ScrollEventTap.update(configuration)  ─ lock-protected hand-off
```

Every change is saved and applied immediately. Decoding tolerates missing keys, wrong types and out-of-range numbers (NaN included), so settings survive upgrades, downgrades and hand edits.

## Pointer tracking

### How macOS accelerates a mouse

The HID event system's pointer filter (`IOHIDPointerScrollFilter`) reads a per-device **tracking value** (`HIDMouseAcceleration`, 16.16 fixed point) and turns raw mouse counts into pointer points:

1. The device's own parametric curves (`HIDAccelCurves`) if it publishes them; otherwise its table (`HIDPointerAccelerationTable`); otherwise a default table built into macOS.
2. The tracking value selects a curve, interpolating between neighbours. Parametric curves are clamped at the last one (3.0 in practice); tables scale linearly above their last entry.
3. Input speed is normalised by `HIDPointerResolution` (400 counts per inch when unknown).
4. A **negative** tracking value removes the accelerator: one count moves one point.
5. If the user turned **Pointer acceleration** off in System Settings › Mouse › Advanced, WindowServer sets `HIDUseLinearScalingMouseAcceleration` and the tracking value becomes a plain multiplier. Pointwise reads that flag from IORegistry, draws the linear curve and says so in the Pointer pane.

There is one value for speed *and* acceleration — that is how macOS works, not a Pointwise simplification.

### What Pointwise does

`PointerService` uses the public simple client (`IOHIDEventSystemClientCreateSimpleClient`) and writes only `HIDMouseAcceleration` on services whose `HIDPointerAccelerationType` is `HIDMouseAcceleration` (trackpads use a different type and are never touched):

- Each service's value is recorded before Pointwise first changes it.
- Handing a device back (quit, pause, rule set to **macOS settings**, **Restore Defaults**) writes the current macOS tracking value, or the recorded value if macOS doesn't report one.
- A 2-second maintenance timer re-applies values that changed underneath (System Settings, wake, a reconnect racing with Pointwise). It only runs while Pointwise manages a device or the scroll tap is active.
- `DeviceMonitor` uses IOHIDManager **matching callbacks only** — the manager is never opened, so no input is read and no Input Monitoring permission is needed. Changes are coalesced for 300 ms and re-applied once more after a second, because macOS applies its own value to a new device shortly after it appears.
- `SIGTERM`, `SIGINT` and `SIGHUP` quit through `NSApp.terminate`, so devices are restored on `kill`, logout and Ctrl-C too.
- Tracking values are system-wide, so devices are handed back when another user's session becomes active and taken over again on return. Nothing is written while the Mac sleeps or another session is active. During a relaunch the old instance leaves devices to the new one.
- Starting to customize (globally or per device) begins from the current macOS setting, including "acceleration off", so nothing jumps.

### The curve chart

`PointerAccelerationModel` re-implements the filter's parametric and table algorithms (IOHIDFamily-2238.100.59, APSL 2.0) so the chart shows what the device really gets. Curves, tables and resolution are read from IORegistry, which needs no permission. Tests compare it with an independent model that reproduced the filter's live segment dumps.

### Rejected alternatives

- **Moving the pointer ourselves** (event tap plus `CGWarpMouseCursorPosition`) would allow any curve, but adds latency and breaks games, drags, multi-display edges and other tools.
- **Writing `HIDPointerResolution` or custom curves** needs a privileged, private HID client.
- **`defaults write -g com.apple.mouse.scaling`** applies globally, only at login or through System Settings, and can't be per device.

## Wheel scrolling

### Event flow

```
HID wheel ─▶ WindowServer ─▶ session event tap (Pointwise, scroll-wheel events only, own thread)
                                 │
                                 ├─ marker set? ───────────────▶ pass (Pointwise's own events)
                                 ├─ scroll/momentum phase? ────▶ pass (trackpad, Magic Mouse)
                                 │                                 and stop any glide on touch
                                 ├─ continuous, no phase? ─────▶ reverse in place, pass
                                 └─ notched wheel
                                      ├─ custom scrolling off ─▶ reverse in place, pass
                                      ├─ smoothing off ────────▶ rewrite as whole lines, pass
                                      └─ smoothing on ─────────▶ replace with first pixel chunk,
                                                                  post the rest per frame
```

### Classification

Only public event fields are used: `ScrollPhase`/`MomentumPhase` non-zero means a gesture device; `IsContinuous` distinguishes pixel-precise wheels from notched ones. Gesture events are never modified, which keeps swipes, rubber-banding and momentum intact.

### The scroll model (`WheelScroller`)

- **One notch = one event's sign.** The line delta in a wheel event already includes macOS's own acceleration, so Pointwise counts notches and times them instead (`WheelSpeedEstimator`, reset after 350 ms or a direction change).
- **Distance** = lines per notch × 10 points × `ScrollAccelerationCurve.multiplier(speed)`. Below 3 notches per second there is no acceleration; above it a power curve grows and levels off at 40 notches per second.
- **Smoothing off:** the event stays a classic wheel event, rewritten with whole lines and a carried remainder. Apps keep their usual handling, AppKit keeps Shift-for-horizontal.
- **Smoothing on:** each notch starts an ease-out glide `1 - (1 - t)^k` (`GlideAnimator`). Glides overlap and add up, so the total distance is exact regardless of frame timing. The first chunk replaces the original event, so there is no added latency and nothing is duplicated; the rest is posted at the display's refresh rate. Fractions of a point are carried (`FractionAccumulator`).
- **Reversal** flips the sign per axis. In-place rewrites read all three delta fields before writing, because setting the line delta overwrites the others.

Glide frames carry the location where the wheel was aimed, so — like native momentum — the rest of a glide keeps scrolling the same view even if the pointer moves on.

Synthesized events are pixel-precise and **phase-less**: that avoids swipe navigation and rubber-banding being triggered by a mouse wheel. They carry a marker in `eventSourceUserData` so the tap passes them through. Shift is applied by moving the delta to the horizontal axis, because AppKit only does that for classic wheel events.

A glide stops when you click (passive global click monitor, so clicks never pass through the tap), touch the trackpad, change modifiers mid-glide, reverse the wheel, or when the tap is disabled.

### Tap lifecycle and robustness

- The tap is created on its own thread (`userInteractive`) with its own run loop; the glide timer runs there too, so the hot path needs no locks. Settings arrive through an `OSAllocatedUnfairLock`-protected hand-off.
- `kCGEventTapDisabledByTimeout` re-enables at once. The maintenance timer recreates a tap that is disabled or invalid.
- `stop()` waits for the thread to finish, so a following `start()` never overlaps it; if a thread doesn't stop in time, no new one starts until it has.
- The tap is stopped on sleep and session switches and recreated afterwards.
- Accessibility is re-checked off the main thread with `IOHIDCheckAccess`, which also notices revocation; the tap is torn down at once if access disappears.

### Rejected alternatives

- **Phased (trackpad-like) synthetic events** would give rubber-banding but trigger swipe navigation and need private gesture companion events.
- **Per-device scrolling** needs the sending device of a scroll event: private `CGEventGetIOHIDEvent`, or opening the HID devices with Input Monitoring.
- **Per-device rules in settings** decode entry by entry, so a rule written by a newer version never discards the others.
- **Disabling macOS scroll acceleration** (`HIDMouseScrollAcceleration = -1`) does not take effect at runtime for an existing device; counting notches makes it irrelevant anyway.

## Performance

- Idle: no polling except the 2-second maintenance timer, which only runs while there is something to maintain.
- The tap's event mask is scroll-wheel only; pointer motion never reaches Pointwise.
- Per scroll event: a few field reads and arithmetic; no allocation in the classification path, no logging, no IPC.
- The Settings window is created on demand and released on close.

## Testing

- `PointwiseCore` has Swift Testing suites for the scroll curve, speed estimation, glide distance conservation, reversal, settings decoding and the macOS pointer curve math (against reference values).
- `Pointwise --snapshot <dir>` (Debug builds) renders every screen in light and dark mode for visual review.
- Event tap and HID behaviour need a real mouse; see the manual checklist in [CONTRIBUTING.md](../CONTRIBUTING.md#manual-test-checklist).

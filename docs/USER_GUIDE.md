# User guide

Pointwise lives in the menu bar (the cursor icon). Its menu has:

- **Enable Pointwise** (⌘E) — pause everything: mice go back to their macOS settings and scroll events pass through unchanged.
- **Smooth Scrolling** — quick toggle for the glide.
- **Settings…** (⌘,) — the settings window.
- **Pointwise Needs Attention…** — appears when a permission is missing or macOS refused a change.

If you hide the menu bar item (Settings › General, or ⌘-drag it out of the menu bar), open Pointwise again from Finder or Spotlight to get to Settings.

## Pointer

- **Customize pointer tracking** — when off, mice use System Settings › Mouse.
- **Pointer acceleration** — when off, the pointer moves exactly as many points as the mouse reports counts. Its speed then follows the mouse's DPI; Tracking speed has no effect.
- **Tracking speed** — the same scale as macOS (0–3). Higher values are faster *and* accelerate more: macOS couples the two.
- **The chart** shows the speed multiplier against mouse speed for the selected mouse: your Pointwise setting (solid) and your macOS setting (dashed). A flat line means no acceleration. Mice that publish their own curves (many keyboards with a pointer interface, some Apple devices) follow them; others use the standard macOS curve.

If **Pointer acceleration** is off in System Settings › Mouse › Advanced, macOS scales movement linearly for every mouse: Tracking speed then works as a plain speed multiplier, and the pane tells you so.

Turning customization on starts from your current macOS setting, so the pointer doesn't jump. Mice with their own settings in **Devices** ignore this pane.

## Scrolling

These settings apply to mice with a notched wheel. Trackpads and Magic Mouse keep their own scrolling.

- **Custom wheel scrolling** — when off, macOS scrolls as usual; reversal still works.
- **Distance per notch** — how far one slow notch scrolls, in lines (1 line = 10 points).
- **Acceleration** — how much further fast spins go. Slow scrolling (below about 3 notches per second) is never accelerated. The chart shows points per notch against wheel speed.
- **Smooth scrolling** — each notch glides to a stop instead of jumping.
  - **Smoothness** — glide length, 80–600 ms.
  - **Responsiveness** — how much of the distance is covered right away. High values feel snappy, low values soft.
  - Clicking, touching the trackpad, reversing the wheel or changing modifier keys stops a glide.
  - A glide scrolls whatever is under the pointer, so moving the pointer during a glide moves the rest of it along.
- **Reverse vertical / horizontal scrolling** — flips the wheel relative to macOS Natural scrolling, which also applies to the trackpad. The trackpad keeps the macOS direction.
- **Reset Scrolling** restores the defaults of this pane.

Shift + wheel scrolls horizontally, as usual on macOS. ⌘/⌥/⌃ + wheel keep their meaning in apps (for example zoom).

Needs Accessibility access; see [PERMISSIONS.md](PERMISSIONS.md).

## Devices

Connected mice appear automatically. For each one choose:

- **Shared settings** — follows the Pointer pane.
- **Custom** — its own acceleration switch and tracking speed, shown under the device.
- **macOS settings** — Pointwise leaves it alone.

Mice with a custom rule stay listed under **Not Connected** while unplugged; **–** forgets them. Identical mice (same model) share a rule, because macOS offers no stable public serial number for most mice.

Some keyboards expose a pointer interface; they are listed with a keyboard icon and can be configured like a mouse.

## General

- **Enable Pointwise** — see the menu.
- **Open at login** — uses the macOS login item service. If macOS asks for approval, click **Open Login Items…**. Keep Pointwise in the Applications folder.
- **Show in menu bar**.
- **Permissions** — Accessibility status, with a button to grant it or relaunch.
- **Restore Defaults…** — every mouse back to its macOS tracking speed, per-device rules removed, scrolling back to defaults.
- **Version** and a shortcut to the macOS Mouse settings.

## Quitting

Quitting Pointwise (menu, ⌘Q, logout, or `kill`) hands every mouse back to its macOS tracking speed and removes the event tap. Scrolling returns to the macOS behaviour immediately.

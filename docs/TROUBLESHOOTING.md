# Troubleshooting

## Scrolling does nothing although Accessibility is on

macOS remembers permissions per code signature. After installing a new build signed differently (your own build, a Debug build, or a different release channel), the old entry stays switched on but no longer matches.

1. Quit Pointwise.
2. In **System Settings › Privacy & Security › Accessibility**, select Pointwise and remove it with **–**.
3. Open Pointwise again and click **Grant Access…**.

Or from Terminal (release build):

```bash
tccutil reset Accessibility io.github.devleloper.Pointwise
```

Debug builds use the bundle ID `io.github.devleloper.Pointwise.debug`.

## "Restart required"

macOS granted access, but it applies to an existing event tap only after a relaunch. Click **Relaunch Pointwise**.

## The pointer speed jumps back

Another tool is setting the same value. Pointwise re-applies its setting within a couple of seconds when something else changes it, so two tools will fight. Turn off pointer customization in Logi Options+, SteerMouse, LinearMouse, Mac Mouse Fix or BetterTouchTool — or in Pointwise.

Changing **Tracking speed** in System Settings while Pointwise customizes the pointer has no lasting effect for managed mice; Pointwise restores that new macOS value when you hand the mouse back.

## Scrolling is doubled, jerky or too fast

- Another scroll utility is active (Mac Mouse Fix, LinearMouse, Logi Options+ "smooth scrolling", SmoothScroll). Use only one.
- In Java apps (JetBrains IDEs, Minecraft launcher) each pixel-precise event counts as at least one unit. Turn off **Smooth scrolling**.
- Lower **Acceleration** if fast spins overshoot.

## Trackpad gestures behave differently

They shouldn't: gesture events carry phases and are passed through untouched. If you see a difference, pause Pointwise from the menu bar to confirm, then [open an issue](https://github.com/devleloper/Pointwise/issues/new/choose) with your macOS version.

## A mouse is missing from Devices

- Only devices macOS treats as mice for tracking are listed. Trackpads are intentionally excluded.
- Bluetooth mice appear once connected, not when only paired.
- Some vendor drivers replace the macOS HID stack; their mice may not accept tracking changes. Settings › General then reports that macOS refused the change.

## Open at login doesn't work

- Move Pointwise to `/Applications`. Login items registered from a disk image or Downloads (App Translocation) can break.
- Check **System Settings › General › Login Items** and allow Pointwise.

## Collecting logs

Pointwise logs state changes (permissions, devices, failures) but never individual input events:

```bash
log show --last 30m --predicate 'subsystem == "io.github.devleloper.Pointwise"' --info
```

## Resetting everything

```bash
defaults delete io.github.devleloper.Pointwise
tccutil reset Accessibility io.github.devleloper.Pointwise
```

Then log out and back in, or reconnect your mice, to clear any tracking value set by a crashed Pointwise.

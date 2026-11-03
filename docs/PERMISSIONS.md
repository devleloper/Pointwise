# Permissions

Pointwise asks for as little as possible.

| Feature | Permission | Why |
| --- | --- | --- |
| Pointer speed and acceleration | None | Uses the public HID event system client, which may set a mouse's tracking value without special access. |
| Device list | None | Uses IOHIDManager matching notifications only; devices are never opened. |
| Wheel scrolling (curve, glide, reversal) | **Accessibility** | Changing or replacing scroll events requires an active event tap, which macOS gates behind Accessibility (the `PostEvent` privilege). |
| Open at login | Login Items approval | macOS may ask you to confirm in System Settings › General › Login Items. |

## What Accessibility is used for

- A Quartz event tap that receives **scroll-wheel events only**. Keyboard events, clicks and pointer movement are not in its event mask and never reach Pointwise.
- A passive global monitor for mouse-button presses, used only to stop a running glide. It cannot change or block clicks and records nothing.
- Posting the pixel-precise scroll events that make up a smooth glide.

Pointwise never uses Accessibility to read window contents, UI elements or text.

## Granting access

1. Open Pointwise Settings › Scrolling and click **Grant Access…** (or use the welcome screen).
2. macOS adds Pointwise to **System Settings › Privacy & Security › Accessibility**. Turn it on.
3. Pointwise notices the change within a few seconds. If it shows **Restart required**, click **Relaunch Pointwise**.

## Revoking access

Turn Pointwise off in the same list. Pointwise notices within a few seconds, removes its event tap and shows the permission banner again; scrolling returns to the macOS behaviour at once. Pointer settings keep working because they need no permission.

## Why not Input Monitoring?

Input Monitoring would let Pointwise tell which mouse produced a scroll event (per-device scrolling), but it also grants access to keyboard input. Pointwise doesn't ask for it.

## Rebuilt or updated app

macOS ties the Accessibility grant to the app's code signature. Developer ID updates of Pointwise keep it. A build signed differently (your own build, a Debug build) is a different app to macOS: grant access again, and remove stale entries with **–**. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#scrolling-does-nothing-although-accessibility-is-on).

# Contributing to Pointwise

Thanks for your interest! Pointwise is intentionally small, so please read the scope section before writing code.

## Scope

Pointwise tunes mouse pointer tracking and mouse-wheel scrolling. Contributions that make that more reliable, correct, accessible or efficient are very welcome. Features outside that scope (button remapping, gestures, per-app profiles, trackpad tweaks, macros) will be declined to keep the app focused and trustworthy. When in doubt, open an issue first.

Hard rules:

- **Public, documented macOS APIs only.** No private frameworks, SPI, `dlsym` tricks or undocumented event fields.
- No networking code of any kind.
- The event tap handles scroll-wheel events only. Never add keyboard events to it.
- Trackpad and gesture-phase events pass through untouched.
- Every device Pointwise changes must be handed back to macOS on quit, pause and rule changes.
- No new permissions and no third-party dependencies without prior discussion.

## Getting started

1. Fork and clone the repository.
2. Open `Pointwise.xcodeproj` in Xcode 16 or later.
3. Run the tests: `swift test --package-path Packages/PointwiseCore`.
4. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/BUILDING.md](docs/BUILDING.md).

## Branching

The project uses a simplified Git Flow:

| Branch | Purpose |
| --- | --- |
| `main` | Released code only. Every commit on `main` is a tagged release. |
| `develop` | Integration branch. Pull requests target `develop`. |
| `feature/<short-name>` | New functionality, branched from `develop`. |
| `fix/<short-name>` | Bug fixes, branched from `develop`. |
| `release/<x.y.z>` | Release preparation, see [docs/RELEASING.md](docs/RELEASING.md). |
| `hotfix/<short-name>` | Urgent fixes, branched from `main`, merged into `main` and `develop`. |

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <description>

[optional body]

[optional footer, e.g. "Fixes #12"]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Scopes in use: `core`, `pointer`, `scroll`, `app`, `ui`, `l10n`, `docs`, `ci`, `release`.

Examples:

```
feat(scroll): stop the glide when modifier keys change
fix(pointer): restore tracking when a device is set to macOS settings
docs: explain Accessibility reset after rebuilding
```

Use `!` after the type or a `BREAKING CHANGE:` footer for breaking changes (for example, an incompatible settings format).

## Code style

- Swift 6 language mode, strict concurrency; no warnings (CI treats them as errors).
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and the style of the surrounding code.
- Keep decisions in `PointwiseCore` (Foundation only) and cover them with tests. Keep `Pointwise/Services` thin.
- The scroll event tap callback must stay allocation-light: no logging, no IPC, no locks other than the configuration hand-off.
- Prefer simple, concrete code over abstractions that have a single implementation.
- Comments explain *why*, not *what*.
- UI text uses macOS terminology (System Settings, Accessibility, Natural scrolling). Every new string needs English and Russian in `Localizable.xcstrings`.

## Pull requests

1. Create a branch from `develop`.
2. Make focused changes with tests where applicable.
3. Make sure the tests and the Xcode build pass without warnings.
4. Update `CHANGELOG.md` under **Unreleased** and the docs if behaviour changes.
5. Open a pull request against `develop` and fill in the template. For UI changes, include light and dark screenshots (`Pointwise --snapshot <dir>` in Debug builds).
6. For changes to event handling or device handling, run the manual checklist below and say which mouse you used.

CI must be green before merge. Pull requests are squash-merged with a Conventional Commit title.

## Manual test checklist

Event taps and HID properties can't be unit-tested without real hardware. Before a release, and for changes in `Pointwise/Services`:

**Pointer**
- [ ] Customize pointer tracking on: speed changes immediately; the chart's dashed line shows the macOS setting.
- [ ] Pointer acceleration off: movement is linear; on again: back to the curve.
- [ ] A device set to **Custom** behaves differently from the shared settings; **macOS settings** restores the System Settings speed.
- [ ] Changing Tracking speed in System Settings while customized: Pointwise re-applies its value within ~2 s.
- [ ] Unplug/replug (or reconnect Bluetooth): the device reappears in Devices and gets its settings.
- [ ] Quit Pointwise (⌘Q and `kill <pid>`): every mouse returns to the System Settings speed.

**Scrolling** (Accessibility granted)
- [ ] Notched wheel, smooth on: glides in Safari, Finder, Xcode, Chrome, Firefox; no double scrolling.
- [ ] Smooth off: classic stepped scrolling with the configured distance.
- [ ] Fast spins scroll further with acceleration on; slow single notches stay precise.
- [ ] Reverse vertical / horizontal flip only the mouse; the trackpad keeps its direction.
- [ ] Shift + wheel scrolls horizontally in both modes.
- [ ] ⌘ + wheel zooms where apps support it; pressing ⌘ mid-glide doesn't zoom the remaining glide.
- [ ] Clicking during a glide stops it; touching the trackpad stops it.
- [ ] Trackpad: two-finger scroll, momentum, rubber-banding, swipe between pages, Mission Control gestures unchanged.
- [ ] Revoke Accessibility in System Settings: within a few seconds scrolling is back to macOS behaviour and the banner appears.
- [ ] Sleep and wake, then scroll: still works. Switch users and back: still works.
- [ ] Pause from the menu bar: everything back to macOS behaviour; resume: restored.

**General**
- [ ] Open at login on/off (from /Applications).
- [ ] Hide the menu bar item, reopen the app from Finder: Settings opens.
- [ ] Restore Defaults: mice back to macOS speed, devices list cleared of rules, scrolling defaults.
- [ ] Light and Dark Mode, English and Russian.

## Reporting bugs and requesting features

Use the [issue templates](https://github.com/devleloper/Pointwise/issues/new/choose). For security or privacy issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

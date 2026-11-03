# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-03

### Added

- Pointer tracking for mice through the macOS HID event system: tracking speed and an acceleration switch, shared by all mice or per device.
- Chart of the acceleration curve macOS applies to the selected mouse, compared with the macOS setting.
- Mouse-wheel scrolling with a speed curve, acceleration for fast spins, smooth glide with adjustable smoothness and responsiveness, and independent vertical and horizontal reversal.
- Trackpad and Magic Mouse gesture events always pass through untouched.
- Automatic detection of connected and disconnected mice; settings for disconnected mice are kept.
- Menu bar item with pause and smooth-scrolling toggles, Settings window in the style of System Settings, welcome screen.
- Open at login, Restore Defaults, English and Russian localization.
- Every managed mouse is handed back to its macOS settings on quit, pause, `SIGTERM` and rule changes; values reset by macOS are re-applied.

[Unreleased]: https://github.com/devleloper/Pointwise/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/devleloper/Pointwise/releases/tag/v1.0.0

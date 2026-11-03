# Building

## Requirements

- macOS 14 or later
- Xcode 16 or later (CI uses the default Xcode of the `macos-26` runner)
- No third-party tools or packages

If `xcodebuild` says it requires Xcode while Xcode is installed, either select it once:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Project layout

- `Pointwise.xcodeproj` — the app target. Its sources are a synchronized folder, so new files in `Pointwise/` are picked up without editing the project.
- `Packages/PointwiseCore` — a local Swift package with all logic that can be tested without macOS input APIs.

## Run the tests

```bash
swift test --package-path Packages/PointwiseCore
```

In Xcode: open `Packages/PointwiseCore/Package.swift` and press ⌘U.

## Build and run

```bash
open Pointwise.xcodeproj
```

Run the **Pointwise** scheme (⌘R). Debug builds:

- use the bundle ID `io.github.devleloper.Pointwise.debug`, so their settings and permissions never mix with an installed release;
- are ad-hoc signed, so macOS treats every rebuild as a new app for Accessibility. Re-grant access after a rebuild, or sign Debug with your Apple Development identity (Signing & Capabilities) to keep the grant between builds — don't commit that change.

Command line, with warnings as errors like CI:

```bash
xcodebuild -project Pointwise.xcodeproj -scheme Pointwise -configuration Debug \
  -derivedDataPath build/DerivedData SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

## Screenshots

Debug builds can render every screen in light and dark mode, offscreen, without Screen Recording permission:

```bash
build/DerivedData/Build/Products/Debug/Pointwise.app/Contents/MacOS/Pointwise --snapshot /tmp/pointwise-shots
```

Add `-AppleLanguages "(ru)"` for Russian. The screenshots show sample settings, which are neither saved nor applied to any device. The README images in `docs/images` come from this command.

## Localization

Strings live in `Pointwise/Resources/Localizable.xcstrings` (English source, Russian translation). Xcode adds new strings to the catalog when you build in the IDE. From the command line, after a Debug build:

```bash
xcrun xcstringstool sync Pointwise/Resources/Localizable.xcstrings \
  $(find build/DerivedData/Build/Intermediates.noindex/Pointwise.build/Debug -name '*.stringsdata' -path '*arm64*' \
    ! -name 'ExtractedAppShortcutsMetadata.stringsdata' -exec echo --stringsdata {} \;)
```

Then translate the new entries; pull requests with new UI strings need both languages.

## App icon

The icon is drawn by a script, so it can be changed in code review:

```bash
swift scripts/make-icon.swift
```

## Release build

```bash
./scripts/build-release.sh
```

Builds a universal (Apple silicon + Intel) Release app, signs it with the hardened runtime, and writes `build/Pointwise-<version>.zip`, `.dmg` and `.sha256`. Without signing credentials the app is ad-hoc signed — fine for your own Mac. Distribution builds: [RELEASING.md](RELEASING.md).

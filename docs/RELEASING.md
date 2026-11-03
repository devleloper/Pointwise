# Releasing

Releases are built, signed with a Developer ID, notarized and drafted on GitHub by the [Release workflow](../.github/workflows/release.yml) when a version tag is pushed.

## Versioning

[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **MAJOR** — incompatible settings format or removed features.
- **MINOR** — new features.
- **PATCH** — fixes only.

`MARKETING_VERSION` in the Xcode project is the version; `CURRENT_PROJECT_VERSION` is the build number and increases with every release.

## One-time setup: signing secrets

Create these in **Settings › Environments › release › Secrets** (or as repository secrets):

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | `base64 -i DeveloperIDApplication.p12` — the *Developer ID Application* certificate with its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password of that .p12 |
| `NOTARY_API_KEY_P8` | `base64 -i AuthKey_XXXXXXXXXX.p8` — an App Store Connect API key (Users and Access › Integrations › Team Keys, role *Developer*) |
| `NOTARY_API_KEY_ID` | The key ID |
| `NOTARY_API_ISSUER_ID` | The issuer ID (UUID) |

To export the certificate: Keychain Access › My Certificates › *Developer ID Application: …* › Export… › .p12.

Keep the same Team ID and bundle ID (`io.github.devleloper.Pointwise`) for the life of the project. macOS ties users' Accessibility grants to them; changing either makes every user grant access again.

Without these secrets the workflow still produces a draft release, ad-hoc signed and marked as such.

## Cutting a release

1. Branch `release/x.y.z` from `develop`.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project (target › General › Identity).
3. Move the **Unreleased** entries in `CHANGELOG.md` under `## [x.y.z] - YYYY-MM-DD`.
4. Run the manual checklist in [CONTRIBUTING.md](../CONTRIBUTING.md#manual-test-checklist) with a Release build.
5. Merge into `main` (squash is not used for release branches), tag and push:

   ```bash
   git tag -a vx.y.z -m "Pointwise x.y.z"
   git push origin main vx.y.z
   ```

6. The workflow checks that the tag matches `MARKETING_VERSION`, runs the tests, builds a universal app, signs it, notarizes and staples the app and the DMG, and drafts a GitHub release with the `.dmg`, `.zip` and `.sha256`.
7. Review the draft, paste the changelog section into the notes, publish.
8. Merge `main` back into `develop`.

## What the pipeline does

`scripts/build-release.sh` (also usable locally):

1. `xcodebuild` Release for `generic/platform=macOS` (arm64 + x86_64), warnings as errors.
2. `codesign --options runtime --timestamp` with the Developer ID identity. No entitlements: Pointwise needs no sandbox exceptions, and event taps and HID properties are permission-gated, not entitlement-gated.
3. Notarize a zip of the app with `notarytool` (App Store Connect API key) and staple the app.
4. Build the DMG with `hdiutil`, sign it, notarize and staple it, and check both with `spctl`.
5. Write SHA-256 checksums.

Locally, with the certificate in your login keychain:

```bash
export DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEY_PATH=~/keys/AuthKey_XXXXXXXXXX.p8 NOTARY_KEY_ID=XXXXXXXXXX NOTARY_ISSUER_ID=…
./scripts/build-release.sh
```

If notarization fails, fetch the log:

```bash
xcrun notarytool log <submission-id> --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
```

## Distribution

GitHub Releases is the only official channel. Pointwise has no auto-updater: it has no network code at all. Users update by downloading a new DMG.

Mac App Store distribution is not possible: the App Sandbox does not allow the Accessibility event tap that wheel scrolling needs.

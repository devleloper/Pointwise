## Summary

<!-- What does this change and why? Link issues with "Fixes #123". -->

## Type

- [ ] Bug fix
- [ ] Feature (discussed in an issue)
- [ ] Refactoring / performance
- [ ] Documentation / CI

## Checklist

- [ ] The PR targets `develop` and the title follows [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] `swift test --package-path Packages/PointwiseCore` passes
- [ ] The app builds without warnings
- [ ] New logic in `PointwiseCore` has tests
- [ ] Public APIs only; no networking code; no keyboard events in the event tap; no new permissions
- [ ] `CHANGELOG.md` and docs are updated if behaviour changed
- [ ] UI changes include light and dark screenshots (`Pointwise --snapshot <dir>` in Debug builds)
- [ ] New UI strings have English and Russian entries in `Localizable.xcstrings`

## Testing

<!-- How did you verify this? macOS version, mouse model and connection, apps tried. -->

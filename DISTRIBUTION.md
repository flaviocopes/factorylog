# Releasing

Work Tracebook ships as a universal app on GitHub Releases, signed with Flavio's Developer ID (team `DGFKNTAG99`) and notarized by Apple when the release is built on a Mac with that certificate in the keychain. CI and forks build ad hoc signed zips instead. Installed copies update themselves from the latest release.

## The release contract

The in-app updater trusts the GitHub release, and copies already installed can only install releases that match what they check. Every release must have:

- a tag `vX.Y.Z`, equal to `CFBundleShortVersionString` in `Resources/FactoryLog-Info.plist`, `FactoryLogVersion.current`, and the CLI's `--version`
- one `.zip` made by `Scripts/build-release.zsh`, with `Work Tracebook.app` at its top, universal, and passing `codesign --verify --deep --strict`
- the bundle ID `dev.factorylog.app`
- the status of latest release, not a draft and not a prerelease

GitHub computes the SHA-256 digest of every upload, and the updater refuses a zip that doesn't match it.

## Steps

1. Bump the version with semver in the plist (`CFBundleShortVersionString` and `CFBundleVersion`) and in `Sources/FactoryLogCore/FactoryLogVersion.swift`. A new feature is a minor release, a fix-only release is a patch.
2. Add the release to `CHANGELOG.md`.
3. Run `zsh Scripts/verify-release.zsh`.
4. Commit, tag `vX.Y.Z`, and push the commit and the tag.
5. Run `zsh Scripts/build-release.zsh` on the tagged commit on a Mac with the Developer ID certificate and a notarytool profile named `notary`. It notarizes and staples the app, then prints the zip's path and SHA-256.
6. Write the notes with what's new first, then an `## Install` section and the checksum. The update dialog shows the notes up to `## Install`.
7. `gh release create vX.Y.Z dist/Work-Tracebook-X.Y.Z.zip --title "Work Tracebook X.Y" --notes-file notes.md --verify-tag`
8. Download the zip from the release page, check its checksum, unzip it with `ditto -x -k`, and run `codesign --verify --deep --strict` on the app.

Refresh the screenshots and the banner when the UI changes: `zsh Scripts/screenshots.zsh`, then `swift Scripts/render-banner.swift`.

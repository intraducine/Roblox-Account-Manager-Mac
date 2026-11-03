# Development guide

[Back to the README](../README.md) · [User guide](USER_GUIDE.md)

The app uses Swift Package Manager, SwiftUI, and AppKit. It targets macOS 13 or newer and has no third-party runtime dependencies. Packaging requires Xcode with the macOS 26 SDK or newer so the app uses the current native interface.

## Build from source

```sh
git clone https://github.com/intraducine/Roblox-Account-Manager-Mac.git
cd Roblox-Account-Manager-Mac
swift test --parallel
RAM_ALLOW_AD_HOC_BUILD=1 ./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

The build script creates one universal app for Apple silicon and Intel Macs. `VERSION` supplies the packaged app version and the version used in network headers. `packaging/Info.plist` supplies the build number. Current release builds use the project signing certificate. To choose an identity for a local build, set `RAM_SIGNING_IDENTITY` to its certificate hash or name. Project-signed builds also need `RAM_EXPECTED_PROJECT_CERT_SHA256`.

The build passes the selected SDK version and minimum macOS version to the linker. Before replacing the app in `dist`, it checks both values for both architectures. If the check fails, select a working Xcode toolchain and rebuild. The macOS 13 minimum supported version does not change.

The smoke test rebuilds `dist/Roblox Account Manager.app` with an ad hoc signature. Preserve a needed signed app before you run it. For a local package check without the private release identity, run `./scripts/smoke-test-app.sh`. It creates an ad hoc-signed app that must not be published. The smoke run uses empty temporary storage and does not read saved accounts or Keychain items. Release packaging always rejects an ad hoc signature.

On the release Mac, run this setup once:

```sh
./scripts/create-project-signing-identity.sh
xcrun swift scripts/release-signature.swift create
```

Create the ZIP, checksum, and project signature with:

```sh
./scripts/package-release.sh
release_version=$(tr -d '[:space:]' < VERSION)
(cd dist && shasum -a 256 -c "Roblox-Account-Manager-for-Mac-$release_version.zip.sha256")
```

Run the identity script only once on the release Mac. It creates a 20-year project certificate and non-exportable private key through a temporary memory disk, imports them into the user's Keychain, and leaves no private-key file in the repository or normal disk storage. The certificate subject contains the project name and no email address. Keychain can ask for approval when the release build uses this private key.

Version 1.1.2 and later must match the pinned project certificate and the separate project update signature. Packaging stops if the app, certificate, or signing metadata contains an email address or local user home path. This project intentionally does not use Developer ID signing or Apple notarization because those systems connect a public build to an Apple Developer identity. The anonymous project certificate contains the project name only. macOS can show an unidentified-developer warning after a manual download.

For manual installation and macOS security warnings, see the [user guide](USER_GUIDE.md#install-and-update).

## Local checks

Use the checks in [.github/workflows/ci.yml](../.github/workflows/ci.yml):

```sh
swift test --parallel
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency
swift build -c release
zsh -n scripts/*.sh
git diff --check
./scripts/smoke-test-app.sh
```

The strict concurrency build must have no concurrency warnings. The smoke test uses empty temporary storage. It does not prove that saved accounts can join a live Roblox game. Some integration tests need explicit environment settings because they launch Roblox clients, use macOS approval UI, or install a published update.

## Publish a release

Review the exact source, notes, app, archive, signing metadata, and logs that will be published. Packaging checks do not replace this privacy review. Keep the project signing identity, bundle identifier, and updater checks unchanged.

Prepare one local Markdown notes file. Start with one short user benefit sentence, then `## What changed` and two to five short bullets. Add `## Before you update` only when users must take action. Keep the facts consistent with `CHANGELOG.md`.

After the required checks, privacy review, and approval to publish, use the reviewed notes file:

```sh
release_version=$(tr -d '[:space:]' < VERSION)
gh release create "v$release_version" dist/Roblox-Account-Manager-for-Mac-"$release_version".zip{,.sha256,.sig} \
    --title "Roblox Account Manager for Mac $release_version" \
    --notes-file /path/to/release-notes.md \
    --latest
```

Confirm the intended release commit and tag. Wait for every required CI run for that commit and tag before creating the release. Read the live release back, download its assets into a new temporary folder, and verify them again.

The updater checks GitHub asset digests, the checksum, project update signature, app name, version, bundle identifier, exact approved signing certificate, and both architectures. Keep its backup, installed-app validation, relaunch, and restore paths working.

Version 1.2.4 checks each architecture with a separate `lipo -verify_arch` call in the build, package, smoke test, and updater. Both architectures remain required. Some installed `lipo` versions reject a check that lists both architectures in one call.

Older managers still use the old check until they are replaced. Users who receive that compatibility error must install the release ZIP manually once. Keep this recovery step in the version 1.2.4 release notes and user guide.

## Signing history

Version 1.1.1 was the bridge from the old signing identity to the project identity used by 1.1.2 and later. It stores the exact project certificate fingerprint. Rebuilding that bridge requires `RAM_BRIDGE_BASE_APP` to point to the public version 1.1.0 app. Current releases do not use that setting.

The updater validates the new identity before it grants access to existing Keychain items. It checks the installed app after replacement and restores the old app if that check fails. The separate update key stays in the Mac Secure Enclave. macOS requires user approval for each release signature.

Version 1.2.2 skips the Keychain access migration when the installed app already uses the downloaded update's verified project identity.

## Project records

- [Live test report](V1_LIVE_TEST_REPORT.md): dated checks and cases that still need controlled accounts.
- [Version 1 implementation specification](V1_IMPLEMENTATION_SPEC.md): original release behavior.
- [Research](RESEARCH.md): experiments and technical decisions.
- [Implementation plan](IMPLEMENTATION_PLAN.md): development history.

These records describe their own test dates and versions. Use the current source and [user guide](USER_GUIDE.md) for current behavior.

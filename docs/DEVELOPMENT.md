# Development guide

Requires macOS 13 or later and Xcode with the macOS 26 SDK or newer. The app uses Swift Package Manager and has no third-party runtime dependencies.

## Build

```sh
git clone https://github.com/intraducine/Roblox-Account-Manager-Mac.git
cd Roblox-Account-Manager-Mac
swift test --parallel
RAM_ALLOW_AD_HOC_BUILD=1 ./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

`VERSION` sets the app version; `packaging/Info.plist` sets the build number. For a local signing identity, set `RAM_SIGNING_IDENTITY`. Project-signed builds also need `RAM_EXPECTED_PROJECT_CERT_SHA256`.

## Checks

```sh
swift test --parallel
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency
swift build -c release
zsh -n scripts/*.sh
git diff --check
./scripts/smoke-test-app.sh
```

The smoke test replaces the app in `dist` with an ad hoc-signed build and uses empty temporary storage. Preserve any signed build first. Release packages must use the project signing identity.

## Release

On the release Mac, set up the project signing identity and update key once:

```sh
./scripts/create-project-signing-identity.sh
xcrun swift scripts/release-signature.swift create
```

Run the checks above, then package the release:

```sh
./scripts/package-release.sh
release_version=$(tr -d '[:space:]' < VERSION)
(cd dist && shasum -a 256 -c "Roblox-Account-Manager-for-Mac-$release_version.zip.sha256")
```

Review the exact source, release notes, package, signing metadata, and logs for private information. Confirm the project certificate, update signature, bundle identity, version, and both processor architectures. Ad hoc builds must not be published.

Prepare a notes file with one short opening sentence and two to five bullets under `## What changed`. Keep it consistent with `CHANGELOG.md`. After approval, push the intended commit and tag. Wait for all required CI checks, then publish:

```sh
release_version=$(tr -d '[:space:]' < VERSION)
gh release create "v$release_version" dist/Roblox-Account-Manager-for-Mac-"$release_version".zip{,.sha256,.sig} \
    --title "Roblox Account Manager for Mac $release_version" \
    --notes-file /path/to/release-notes.md \
    --latest
```

Read the published release back, download its assets, and verify them. Keep the updater's signature checks, backup, installation validation, and restore path intact.

# Roblox Account Manager for Mac

A native macOS port of [Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). It keeps account sessions in macOS Keychain and launches the installed Roblox client with the selected account.

This project is independent and is not made by or approved by Roblox Corporation.

## Current release

Version `0.1.0` includes the complete core Mac workflow:

- Add an account through a private embedded Roblox sign-in page.
- Import a `.ROBLOSECURITY` session as an advanced option.
- Validate each session with Roblox before saving it.
- Store sessions in macOS Keychain. The account metadata file contains no session cookies.
- Search accounts and organize them with aliases, groups, and notes.
- Save a place ID and optional server target for each account.
- Launch a public server, a job ID, or a private server link as the selected account.
- Keep an automatic metadata backup.

## Requirements

- macOS 13 or newer.
- Roblox installed in `/Applications`.
- Xcode 15 or newer to build from source.

## Build and run

```sh
swift test
./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

The packaging script builds a universal Intel and Apple silicon release binary, makes the app icon, creates the `.app` bundle, and applies an ad hoc local signature. Apple notarization needs a paid Apple Developer identity and is not part of this repository.

## How launches work

The app uses the same core method as the Windows project:

1. It sends the selected account session only to Roblox HTTPS endpoints.
2. It completes Roblox's CSRF request challenge.
3. It requests a short-lived authentication ticket.
4. It opens the `roblox-player` URL scheme registered by the installed Mac client.

The app never writes a session cookie into the launch URL or a log.

## Security notes

- Treat `.ROBLOSECURITY` as a password. Never send it to another person.
- The browser sign-in uses a non-persistent WebKit data store. The accepted session moves to Keychain.
- Network requests use an isolated URL session and do not share cookies between accounts.
- Removing an account deletes its Keychain item and its local metadata.
- Metadata is stored at `~/Library/Application Support/Roblox Account Manager/Accounts.json`.

## Mac limits

The installed Roblox app declares `LSMultipleInstancesProhibited`. This port does not bypass that platform rule. It switches the account used for a launch, but it does not promise concurrent Roblox clients.

Windows-only features from the original project are not in version 0.1.0. These include Win32 window placement, mutex bypass, FPS file patches, CefSharp browser profiles, the local developer API, Nexus account control, and process watcher automation. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the feature decisions.

## License

This port is licensed under GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

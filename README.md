# Roblox Account Manager for Mac

A native macOS port of [Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). It keeps account sessions in macOS Keychain and launches the installed Roblox client with the selected account.

This project is independent and is not made by or approved by Roblox Corporation.

## Current release

Version `0.3.0` includes the complete parallel and batch-account Mac workflow:

- Add an account through a private embedded Roblox sign-in page.
- Import a `.ROBLOSECURITY` session as an advanced option.
- Validate each session with Roblox before saving it.
- Store sessions in macOS Keychain. The account metadata file contains no session cookies.
- Search accounts and organize them with aliases, groups, and notes.
- Save a place ID and optional server target for each account.
- Launch a public server, a job ID, or a private server link as the selected account.
- Keep different accounts running in separate Roblox processes at the same time.
- Select accounts with checkboxes or select a complete group.
- Launch the selected accounts immediately with one shared place and server target.
- Continue the batch when one account fails, then keep failed accounts selected for retry.
- Show which accounts are running and stop one account without closing the others.
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
4. It verifies the installed Roblox app has a valid Roblox Corporation signature.
5. It makes an APFS-cloned temporary copy for the selected account.
6. It gives that copy a unique bundle ID, allows a new instance, and applies a local ad hoc signature.
7. It sends the launch URL directly to that isolated copy.

The app never writes a session cookie into the launch URL or a log.

## Security notes

- Treat `.ROBLOSECURITY` as a password. Never send it to another person.
- The browser sign-in uses a non-persistent WebKit data store. The accepted session moves to Keychain.
- Network requests use an isolated URL session and do not share cookies between accounts.
- Parallel copies are made only in `~/Library/Caches/Roblox Account Manager/Instances`.
- The app never edits or re-signs `/Applications/Roblox.app`.
- Removing an account deletes its Keychain item and its local metadata.
- Metadata is stored at `~/Library/Application Support/Roblox Account Manager/Accounts.json`.

## Parallel-launch limits

The installed Roblox app declares `LSMultipleInstancesProhibited`. This port works around that limit only in disposable per-account copies. Roblox can change its client checks at any time. A future Roblox update can stop parallel mode from working until this project is updated.

Use accounts that belong to you. Some Roblox experiences can prohibit alternate accounts or farming even when Roblox itself allows both accounts to sign in. This app does not hide automation, inject code, or change the Roblox executable.

Windows-only features from the original project are not in version 0.3.0. These include Win32 window placement, FPS file patches, CefSharp browser profiles, the local developer API, Nexus account control, and process watcher automation. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the feature decisions.

## License

This port is licensed under GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

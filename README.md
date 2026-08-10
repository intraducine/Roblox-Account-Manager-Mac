# Roblox Account Manager for Mac

A native macOS port of [Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). It keeps account sessions in macOS Keychain and launches the installed Roblox client with the selected account.

This project is independent and is not made by or approved by Roblox Corporation.

## Current release

Version `0.6.0` adds a strict official-client mode and keeps the parallel-copy method as a separate fallback:

- Add an account through a private embedded Roblox sign-in page.
- Import a `.ROBLOSECURITY` session as an advanced option.
- Validate each session with Roblox before saving it.
- Store sessions in macOS Keychain. The account metadata file contains no session cookies.
- Search accounts and organize them with aliases, groups, and notes.
- Save a place ID and optional server target for each account.
- Launch a public server, a job ID, or a private server link as the selected account.
- Use the exact Roblox app in `/Applications` by default.
- Keep different accounts running at the same time only when you explicitly enable Modified Parallel Fallback.
- Select accounts with checkboxes or select a complete group.
- Launch the selected accounts immediately with one shared place and server target.
- Continue the batch when one account fails, then keep failed accounts selected for retry.
- Show which accounts are running and stop one account without closing the others.
- Keep an automatic metadata backup.
- Use a standard native macOS interface that follows the system appearance.
- Send the JSON media type required by Roblox when requesting launch tickets.
- Show a clear warning before Modified Parallel Fallback can be enabled.
- Reuse stable Apple-signed fallback copies so macOS permission decisions can persist.
- Use one shared fallback identity so microphone and local-network approval applies to every managed fallback account.
- Stop every running managed Roblox client with one native `Stop All` action.
- Omit the Roblox menu-bar helper from managed copies and reuse one stable system identity for all managed clients.

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

The packaging script builds a universal Intel and Apple silicon release binary, makes the app icon, and creates the `.app` bundle. It uses an installed Apple code-signing identity when one is available and otherwise falls back to an ad hoc local signature. Apple notarization is not part of this repository.

## How launches work

Both modes use the same secure account launch steps:

1. It sends the selected account session only to Roblox HTTPS endpoints.
2. It completes Roblox's CSRF request challenge.
3. It requests a short-lived authentication ticket.
4. It verifies the installed Roblox app has a valid Roblox Corporation signature.

Official Roblox is the default mode. It sends the launch URL to the exact `/Applications/Roblox.app` bundle. It does not copy, edit, or sign Roblox. The current Roblox app permits only one game client in this mode.

Modified Parallel Fallback is separate and never turns itself on. It makes a persistent copy for each account, changes the copied `Info.plist`, removes the copied menu-bar helper, writes copied client settings, and signs the copy again. This permits concurrent clients on the current Roblox build.

The app never writes a session cookie into the launch URL or a log.

## Security notes

- Treat `.ROBLOSECURITY` as a password. Never send it to another person.
- The browser sign-in uses a non-persistent WebKit data store. The accepted session moves to Keychain.
- Network requests use an isolated URL session and do not share cookies between accounts.
- Fallback copies are kept in `~/Library/Application Support/Roblox Account Manager/Instances` so macOS can reuse their permission identity.
- The app never edits or re-signs `/Applications/Roblox.app`.
- Removing an account deletes its Keychain item and its local metadata.
- Metadata is stored at `~/Library/Application Support/Roblox Account Manager/Accounts.json`.

## Parallel-launch limits

The installed Roblox app declares `LSMultipleInstancesProhibited`. Live testing on August 10, 2026 confirmed that one official client joins normally but a second official client does not stay open. [Apple documents this property as a multiple-instance restriction](https://developer.apple.com/documentation/bundleresources/information-property-list/lsmultipleinstancesprohibited), even when an app asks Launch Services for a new instance.

Modified Parallel Fallback works around that limit with managed copies. [Roblox states that modified versions of its app are not allowed and that continued use can lead to account restrictions](https://en.help.roblox.com/hc/en-us/articles/24275616578708-Anti-cheat-Messages). Treat this mode as detectable and risky. The manager shows this warning before it lets you enable the fallback. Roblox can also change its client checks at any time and stop the fallback from working.

Official mode uses Roblox's original signature and permission identity. Roblox can still request microphone, local-network, notification, or login-item access. Those requests come from Roblox, and this app does not approve them.

Fallback mode uses a stable shared identity. Its first launch can show microphone or local-network decisions. Later launches reuse the same signed copies and identity. The fallback copies omit the optional menu-bar helper. If no Apple code-signing identity is installed, the app uses ad hoc signing and macOS can ask again after a Roblox update.

Use accounts that belong to you. Some Roblox experiences can prohibit alternate accounts or farming even when Roblox itself allows both accounts to sign in. The app does not inject code or hide its launches. Official mode leaves the complete Roblox bundle unchanged. Fallback mode does not patch Roblox's machine code, but re-signing changes signature data in the copied executable. Do not treat the fallback as an unmodified client.

Windows-only features from the original project are not in version 0.5.0. These include Win32 window placement, FPS file patches, CefSharp browser profiles, the local developer API, Nexus account control, and process watcher automation. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the feature decisions.

## License

This port is licensed under GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

# Roblox Account Manager for Mac

A native macOS port of [Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). It saves Roblox sign-ins in macOS Keychain and launches the installed Roblox client with the selected account.

This project is independent and is not made by or approved by Roblox Corporation.

## What the app does

Version `0.9.0` is made for running several Roblox accounts at the same time:

- Add an account through a temporary Roblox sign-in page inside the app.
- Store each Roblox sign-in in macOS Keychain. The account list does not contain sign-in secrets.
- Search accounts and organize them with aliases, groups, and notes. One account can be in several groups.
- Save a game and an optional server choice for each account.
- Let Roblox choose a public server, browse public servers by available space, or join a player whose server Roblox makes public.
- Use private server links and manual Job IDs from the same server chooser.
- Select accounts with checkboxes, Shift-click one profile at a time, or a complete group. Shift-click again to deselect that profile.
- Run each account in a separate copy that exactly matches `/Applications/Roblox.app`.
- Show which accounts are running. Stop one account or stop all managed clients.
- Keep the advanced fallback behind a clear risk warning. The app does not enable it by itself.
- Import a `.ROBLOSECURITY` session only through the advanced account option.
- Keep an automatic backup of account names, groups, notes, and launch choices.
- Use a standard native macOS interface that follows the system appearance.

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

Every manager launch starts a separate copy of Roblox. This is true even when you launch only one account. You can then launch another account without closing the first one.

The copy is unchanged. It has the same files and Roblox signature as the installed app at `/Applications/Roblox.app`. The manager checks this before each launch. It does not edit the installed app.

If you only want to use Roblox without the account manager, open `/Applications/Roblox.app` in Finder. That action is separate from this app.

### Choose a game and server

- **Place ID:** This number identifies a Roblox experience or a place inside an experience. It is the number after `/games/` in a Roblox game link.
- **Roblox chooses:** This is the default. Roblox selects an available public server.
- **Browse public servers:** Choose a running server by its player count and open spaces. For a batch, the app puts servers with enough room first.
- **Join a player:** Enter a Roblox username. The app uses the public presence that Roblox provides. It cannot find hidden, private, or offline players.
- **Private server link:** Paste a supported link for a private server that every selected account can access.
- **Manual Job ID:** Open Advanced when you already have the unique code for one running public server.

Enter a Place ID before browsing public servers, using a private server link, or entering a Job ID. Join a Player fills the current Place ID from Roblox automatically.

Public server lists are cached for one minute because Roblox limits how often they can refresh. The app does not send a saved account sign-in when it browses servers, looks up a username, or checks public player presence.

For each launch, the manager:

1. Sends the selected saved session only to Roblox.
2. Gets a short-lived launch ticket from Roblox.
3. Checks the installed Roblox app and the separate copy.
4. Starts that copy and gives the ticket only to that process.

The app keeps one separate Roblox copy for each account. Each copy must match the installed app exactly and keep Roblox's original signature. The app sends the launch request to the correct Roblox process. The session and launch ticket do not appear in the process list or app logs.

### Advanced fallback

Use this only if normal managed launches stop working. You must open the advanced explanation and accept a warning before you can enable it. The app never enables it by itself.

This fallback changes settings inside each copied app and gives the copy a different digital signature. It is not an unchanged Roblox client. Roblox can detect the different signature. Using this option can put an account at risk. Return to the unchanged launch method when you finish testing it.

The app never writes a session cookie or launch ticket to a log.

## Security notes

- Treat `.ROBLOSECURITY` as a password. Never send it to another person.
- The browser sign-in uses a non-persistent WebKit data store. The accepted session moves to Keychain.
- Network requests use an isolated URL session and do not share cookies between accounts.
- Unmodified and fallback copies are kept in `~/Library/Application Support/Roblox Account Manager/Instances`.
- The manifest for an unmodified copy stays beside `Roblox.app`, never inside it.
- The app never edits or re-signs `/Applications/Roblox.app`.
- Removing an account deletes its Keychain item and its local metadata.
- Metadata is stored at `~/Library/Application Support/Roblox Account Manager/Accounts.json`.
- Empty group names are stored at `~/Library/Application Support/Roblox Account Manager/Groups.json`.

## Parallel-launch limits

The installed Roblox app declares `LSMultipleInstancesProhibited`. This tells the normal macOS app launcher to allow only one copy. Live testing on August 10, 2026 confirmed that a second client does not stay open when it starts through that system. [Apple documents this property as a multiple-instance restriction](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html). Apple also provides [process-targeted Apple Events](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor), which let the manager send a launch request to one exact process.

The standard managed launch starts the checked copy without the normal macOS app launcher. It does not bypass Roblox security checks, inject code, patch memory, edit the copied app, or replace its signature. Each copy must match `/Applications/Roblox.app` and pass strict signature checks. If a check fails, the manager deletes that copy and stops the launch.

The modified fallback changes managed copies. [Roblox states that modified versions of its app are not allowed and that continued use can lead to account restrictions](https://en.help.roblox.com/hc/en-us/articles/24275616578708-Anti-cheat-Messages). Treat this option as detectable and risky. The manager shows this warning before it lets you enable the fallback. Roblox can also change its checks at any time and stop the fallback from working.

The normal managed copies use Roblox's original signature and permission identity. Roblox can still request microphone, local-network, notification, or login-item access. Those requests come from Roblox, and this app does not approve them. An exact bundle cannot remove Roblox's menu-bar helper or client settings without becoming modified.

Fallback mode uses a stable shared identity. Its first launch can show microphone or local-network decisions. Later launches reuse the same signed copies and identity. The fallback copies omit the optional menu-bar helper. If no Apple code-signing identity is installed, the app uses ad hoc signing and macOS can ask again after a Roblox update.

Use accounts that belong to you. Some Roblox experiences can prohibit alternate accounts or farming even when Roblox itself allows both accounts to sign in. Roblox can see normal process, session, network, device, and account behavior. An unchanged bundle is not an invisibility promise or a policy exception. The app does not inject code or hide its launches. Normal managed copies keep the complete Roblox bundle unchanged. Fallback mode does not patch Roblox's machine code, but re-signing changes signature data in the copied executable. Do not treat the fallback as an unmodified client.

Windows-only features from the original project are not in version 0.9.0. These include Win32 window placement, FPS file patches, CefSharp browser profiles, the local developer API, Nexus account control, and process watcher automation. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the feature decisions.

## License

This port is licensed under GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

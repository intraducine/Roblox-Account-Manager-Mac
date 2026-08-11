# Roblox Account Manager for Mac

A native SwiftUI app for running several Roblox accounts on one Mac. It saves each Roblox session in macOS Keychain and launches a separate unchanged copy of the installed Roblox app for each managed account.

This project is independent. Roblox Corporation does not make or approve it. Use only accounts that you own or have permission to use.

## Version 1.0 features

- Launch several saved accounts together.
- Stop one managed Roblox client or use **Stop All**.
- Find friends whose current experience is publicly visible.
- Verify that a reported Job ID is in Roblox's public server list before a normal batch join.
- Check open server spaces before launch. The app never removes selected accounts without telling you.
- Open Roblox Home, Profile, Settings, or Security in an isolated window for one selected account.
- Check account sign-in health and sign in again without losing aliases, groups, notes, favorites, or Launch Sets.
- Save Launch Sets for common account and experience choices.
- Reuse recent and favorite experiences from the Place ID chooser.
- Export and import account metadata without Roblox sessions.
- Run local checks for Roblox, unchanged copies, storage, Keychain entries, process records, and Roblox services.

The app does not store passwords. It does not solve captchas, inject code, automate gameplay, reveal hidden presence, or bypass private-server access.

## Requirements

- macOS 13 or newer.
- Roblox installed at `/Applications/Roblox.app`.
- Xcode 15 or newer to build from source.

## Build from source

```sh
git clone <repository-url>
cd roblox-account-maneger-mac
swift test
./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

The build script creates one universal app for Apple silicon and Intel Macs. It uses an ad hoc local signature by default. To use a specific signing identity, set `RAM_SIGNING_IDENTITY` to its certificate hash or name before running the script.

To create the optional ZIP file and SHA-256 checksum:

```sh
./scripts/package-release.sh
shasum -a 256 -c "dist/Roblox-Account-Manager-for-Mac-1.0.0.zip.sha256"
```

A downloaded build is not notarized. macOS can show a warning when you open it. Building from source gives you the clearest local trust boundary. This project does not use an automatic updater or paid Apple services.

## Add accounts

Use **Add Account** and sign in on Roblox's temporary page. The page uses a non-persistent browser store. After sign-in, the app checks the Roblox user ID and saves only the `.ROBLOSECURITY` session in macOS Keychain.

Treat `.ROBLOSECURITY` like a password. Never send it to another person.

You can give one account an alias, notes, and several groups. These fields do not change the Roblox account.

## Launch accounts

Every managed launch uses a separate copy of `/Applications/Roblox.app`. This includes the first account. You can start another account later without closing the first one.

The normal copy stays unchanged. Every file must match the installed Roblox app. It keeps Roblox Corporation's original signature. The manager stops the launch if the copy or signature check fails. It never edits `/Applications/Roblox.app`.

To launch:

1. Select accounts from the account list or select a group.
2. Enter a Place ID or choose a recent or favorite experience.
3. Let Roblox choose a server, browse public servers, find a player, or enter a supported private server link.
4. Select **Launch Selected Accounts**.

A Place ID is the number after `/games/` in a Roblox experience link. A Job ID identifies one current server. Job IDs stop working when that server closes.

The bottom **Advanced fallback** changes copied app settings and applies a different signature. Roblox can detect that change. Use it only for recovery tests. Normal V1 launches use unchanged copies.

## Find Players

Open **Find Players** in the toolbar or choose **View > Joinable Players**.

The window checks the friends of all valid source accounts, merges duplicate players, and shows which source accounts found each player. V1 automatic discovery uses only presence that Roblox makes public. It labels these results **Publicly visible**. It does not claim to find friend-only or hidden activity.

For each public result, the app searches Roblox's public server pages for the reported Job ID:

- **Public** means the Job ID was found. You can select managed accounts and join them.
- **Not confirmed** means the first search limit ended. You can continue checking or make a warned attempt.
- **Restricted or unavailable** means the complete public search did not find the server. Open the player's profile as a source account and use Roblox's own Join button if it appears.
- **No server supplied** means Roblox showed an experience but did not give the app a server target.

Before a verified batch join, the app refreshes capacity and checks each selected account. If only two spaces remain for four selected accounts, it offers **Launch First 2**, **Change Selection**, and **Cancel**. Roblox can still reject a launch if access, capacity, age, region, or the server changes.

Roblox controls online visibility and join access. See [Roblox Online Status and Visibility](https://en.help.roblox.com/hc/en-us/articles/39144167691284-Online-Status-and-Visibility).

## Selected-account Roblox website

Right-click an account or use its detail view to open Roblox Home, Profile, Settings, or Security. Each website window:

- Shows the active alias and Roblox username at all times.
- Uses a separate non-persistent WebKit data store.
- Receives only that account's saved session.
- Clears web data when it closes.
- Saves a changed session only after Roblox confirms the same user ID.
- Opens non-Roblox links in the normal browser only after confirmation.

This is the safe fallback for friend-only or restricted player joins. The user completes the join through Roblox's normal website controls.

## Launch Sets and experiences

A Launch Set stores account IDs, group names, a Place ID, and one server method. It does not save a discovered public Job ID because public servers can close. Private server links stay local and are excluded from normal backups.

The experience chooser records recent Place IDs and launch counts. You can mark an entry as a favorite. A numeric Place ID stays the source of truth, so a name lookup is not required to launch.

## Backup and diagnostics

Open **Tools > Diagnostics and Backup**.

Normal backups can include account IDs, usernames, aliases, groups, notes, favorites, recent experiences, and Launch Sets. They exclude sessions, launch tickets, access codes, active process IDs, raw network responses, and private server links. Import matches accounts by Roblox user ID and never replaces a Keychain session.

The redacted diagnostic report contains only plain check results. It does not include cookies, tickets, private links, private access codes, or complete launch URLs.

## Roblox and macOS limits

Roblox declares that its normal macOS app should have only one instance. The manager starts separate exact copies directly and sends each launch request to the correct process. It does not use process injection or change the normal copied bundle.

Roblox can still see normal device, process, network, session, and account behavior. An unchanged copy does not make the manager invisible and does not override the rules of an experience.

Roblox can request microphone, local-network, notification, or login-item permission. These requests come from Roblox. This app cannot remove those requests while keeping the Roblox bundle unchanged.

The optional modified fallback does not meet the unchanged-copy rule. Roblox states that modified clients can lead to account restrictions. See [Roblox anti-cheat messages](https://en.help.roblox.com/hc/en-us/articles/24275616578708-Anti-cheat-Messages).

## Data locations

- Account metadata: `~/Library/Application Support/Roblox Account Manager/Accounts.json`
- Group names: `~/Library/Application Support/Roblox Account Manager/Groups.json`
- Launch Sets, experiences, and active target records: the same local data folder
- Managed copies: `~/Library/Application Support/Roblox Account Manager/Instances`
- Sessions: macOS Keychain only

Removing an account deletes its Keychain item and local account metadata.

## Development notes

[docs/V1_LIVE_TEST_REPORT.md](docs/V1_LIVE_TEST_REPORT.md) records the live checks completed for this release and the cases that still need controlled test accounts. [docs/RESEARCH.md](docs/RESEARCH.md) records old experiments and the V1 presence decision. [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) is development history. These files do not replace this current guide.

Windows-only features from the original project remain outside V1. These include Win32 window placement, Windows registry work, a local control API, process injection, and gameplay automation.

## License

This port uses GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

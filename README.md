# Roblox Account Manager for Mac

A native SwiftUI app for running several Roblox accounts on one Mac. It saves each Roblox session in macOS Keychain and launches a separate unchanged copy of the installed Roblox app for each managed account.

This project is independent. Roblox Corporation does not make or approve it. Use only accounts that you own or have permission to use.

## What the app can do

- Save several Roblox accounts without saving their passwords.
- Run several saved accounts at the same time in separate Roblox windows.
- Start one account, several selected accounts, or every account in a group.
- Stop one managed Roblox window or close all managed windows with **Stop All**.
- Give accounts easy-to-read names, notes, and membership in more than one group.
- Search saved accounts and show only the accounts in one group.
- Save common account and game choices as **Launch Sets** so you can reuse them later.
- Keep a list of recently played games and mark games as favorites.
- Let Roblox choose a server, choose a public server with enough open spaces, or use a supported private-server link.
- Save private-server links with names and browse them again without pasting them each time.
- Find friends whose current game is visible to at least one saved account.
- Join a visible friend with several accounts. The friend account starts first, then the app sends the other selected accounts to the same server.
- Open Roblox Home, Profile, Settings, or Security as one saved account without signing the other accounts out.
- Use Roblox Play and Join buttons in that account's website window. The correct saved account opens in its own managed Roblox window.
- Check whether a saved account is still signed in and sign in again without losing its name, groups, notes, favorites, or Launch Sets.
- Export and import account names, groups, notes, games, and Launch Sets without copying Roblox sign-ins.
- Check the Roblox installation, saved data, Keychain storage, managed copies, running processes, and Roblox services for common problems.
- Offer an optional advanced recovery method if unchanged Roblox copies stop working. This method changes the copy and warns you before it runs.

The app does not store passwords. It does not solve captchas, inject code, automate gameplay, reveal hidden presence, or bypass private-server access.

## Requirements

- macOS 13 or newer.
- Roblox installed at `/Applications/Roblox.app`.
- Xcode 15 or newer to build from source.

## Quick start

1. Open **Add Account** and sign in on the Roblox page.
2. Repeat this for every account that you want to run.
3. Use the checkboxes in the account list to select the accounts that should open together.
4. Enter a Place ID or select **Choose Game** to reuse a recent game.
5. Keep **Let Roblox choose** or select another server option.
6. Select **Launch Accounts**. Each selected account opens in its own Roblox window.

A Place ID is the number after `/games/` in a Roblox game link. Most users do not need a Job ID. A Job ID is an advanced, temporary code for one server that is already running.

## Build from source

```sh
git clone <repository-url>
cd roblox-account-maneger-mac
swift test
./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

The build script creates one universal app for Apple silicon and Intel Macs. It uses an installed Apple code-signing identity when one is available. This stable signature lets macOS recognize the app after an update. If no identity is available, the script uses an ad hoc signature. To choose a specific identity, set `RAM_SIGNING_IDENTITY` to its certificate hash or name before running the script.

To create the optional ZIP file and SHA-256 checksum:

```sh
./scripts/package-release.sh
(cd dist && shasum -a 256 -c "Roblox-Account-Manager-for-Mac-1.0.3.zip.sha256")
```

A downloaded build is not notarized. macOS can show a warning when you open it. Building from source gives you the clearest local trust boundary. This project does not use an automatic updater or paid Apple services.

## Add accounts

Use **Add Account** and sign in on the Roblox page inside the app. Select **Save This Account** when the page is ready. The page does not keep browsing history. The app checks which Roblox account signed in and saves its Roblox session in Keychain, the private password storage built into macOS.

The app never sees or saves your Roblox password. The advanced paste option accepts a `.ROBLOSECURITY` session value. Treat that value like a password and never send it to another person.

The app stores all saved Roblox sessions inside one Keychain item. Version 1.0.2 uses a new item because older ad hoc builds could lose access after an app update and show error `-25293`. If macOS allows access to the old item, the app moves every session automatically. If macOS blocks the old item, account names and settings remain, but each affected account must sign in once. Version 1.0.2 and later release builds use a stable Apple signing identity so later updates keep access to the new item.

The managed Roblox website window keeps top-level browsing on `roblox.com`. Secure frames used inside Roblox pages can load without an external-link warning, and they do not receive the Roblox session cookie. A real link to another site asks before it opens in the default browser and names the destination.

You can give one account an alias, notes, and several groups. These fields do not change the Roblox account.

## Update the app

Version 1.0.3 adds the in-app updater. Choose **Roblox Account Manager > Check for Updates** or open **About > Check for Updates**.

The app checks only final releases from this project's public GitHub page. When a newer version exists, it downloads the release ZIP and checksum, checks GitHub's file fingerprint, and confirms that the downloaded app has the same signing identity as the installed app. It also checks the app name, version, bundle identifier, and Intel and Apple silicon support before showing **Install and Restart**.

The updater never stores a GitHub login or token. It does not install a draft or prerelease. The current app must be in a location that your macOS account can change, such as an app that you copied to `/Applications`. A hidden copy of the previous version stays beside the app as a recovery backup.

Version 1.0.2 and older do not have the updater. Install version 1.0.3 once with the release ZIP. Later public releases can use the in-app button.

## Launch accounts

Every managed launch uses a separate copy of `/Applications/Roblox.app`. This includes the first account. You can start another account later without closing the first one.

The normal copy stays unchanged. Every file must match the installed Roblox app. It keeps Roblox Corporation's original signature. The manager stops the launch if the copy or signature check fails. It never edits `/Applications/Roblox.app`.

To launch:

1. Select accounts from the account list or select a group.
2. Enter a Place ID or choose a recent or favorite experience.
3. Let Roblox choose a server, browse public servers, find a player, or enter a supported private server link.
4. Select **Launch Accounts**.

A Place ID is the number after `/games/` in a Roblox experience link. A Job ID identifies one current server. Job IDs stop working when that server closes, so the app never saves them as a future launch choice. Choosing or typing a different Place ID returns the server choice to **Let Roblox choose**.

Open **Choose Server > Private Servers** to save a private-server link with a clear name. The app reads the Place ID from the link. Select the saved name later to reuse both the link and its Place ID. Links that were already saved to accounts or Launch Sets appear in this list after the app loads them.

The bottom **Advanced fallback** changes copied app settings and applies a different signature. Roblox can detect that change. Use it only for recovery tests. Normal managed launches use unchanged copies.

## Find Players

Open **Find Players** in the toolbar or choose **View > Joinable Players**.

The window checks the online friends that Roblox shows to each saved account, one account at a time. It merges duplicate players and shows which saved accounts can see each player. It does not guess hidden activity or scan public server pages.

To join a friend with several accounts:

1. Select the friend.
2. Select every account that you want to launch. Accounts that already have a managed Roblox client running are disabled.
3. Include at least one account shown under **Visible To**. Roblox gave that account the friend's server, so it must start first.
4. Select **Join Friend**.

The manager starts one account from the **Visible To** list first. It then tries the other selected accounts in the same server. Roblox checks access and available space for each account. An account can still be rejected because it cannot join that player, the server is full, the game has limits, or the server changed.

This friend flow makes no public-server requests. Public-server browsing remains a separate manual tool.

Roblox controls online visibility and join access. See [Roblox Online Status and Visibility](https://en.help.roblox.com/hc/en-us/articles/39144167691284-Online-Status-and-Visibility).

## Selected-account Roblox website

Right-click an account or use its detail view to open Roblox Home, Profile, Settings, or Security. Each website window:

- Shows the active alias and Roblox username at all times.
- Uses a separate non-persistent WebKit data store.
- Receives only that account's saved session.
- Clears web data when it closes.
- Saves a changed session only after Roblox confirms the same user ID.
- Opens non-Roblox links in the normal browser only after confirmation.
- Sends Roblox Play and Join actions back to the manager for this account.

When you select Play or Join on the Roblox website, the manager reads only the Place ID and server choice. It does not reuse the website's launch ticket. It requests a new ticket for the account shown at the top of the window, then starts that account in a separate unchanged Roblox copy. It does not open the normal Roblox app. If that account already has a managed client running, the manager stops the second launch and tells you why.

Use this window when you want to browse as one saved account, start a game from its page, or use a friend's Join button when that account is allowed to join them.

## Launch Sets and experiences

A Launch Set is a saved shortcut for accounts, one game, and one server choice. It does not save a public Job ID because that code stops working when the server closes. When a Launch Set uses a private server, you can choose a link from the saved private-server list. Private server links stay local and are excluded from normal backups.

The experience chooser records recent Place IDs and launch counts. It also saves the game's current name and icon when Roblox provides them. You can mark an entry as a favorite. A numeric Place ID stays the source of truth, so a metadata lookup is not required to launch.

## Backup and diagnostics

Open **Tools > Diagnostics and Backup**.

Normal backups can include account IDs, usernames, aliases, groups, notes, favorites, recent experiences, and Launch Sets. They exclude sessions, launch tickets, access codes, active process IDs, raw network responses, and private server links. Import matches accounts by Roblox user ID and never replaces a Keychain session.

The redacted diagnostic report contains only plain check results. It does not include cookies, tickets, private links, private access codes, or complete launch URLs.

## Roblox and macOS limits

Roblox declares that its normal macOS app should have only one instance. The manager starts separate exact copies directly and sends each launch request to the correct process. It does not use process injection or change the normal copied bundle.

Roblox can still see normal device, process, network, session, and account behavior. An unchanged copy does not make the manager invisible and does not override the rules of an experience.

Roblox can request microphone, camera, local-network, notification, or login-item permission. Roblox starts the access, but macOS can name the manager as the responsible app because it started the Roblox process. The manager includes clear privacy descriptions so macOS can show the request instead of terminating Roblox. The app cannot suppress valid Roblox permission requests while keeping each Roblox copy unchanged.

The optional modified fallback does not meet the unchanged-copy rule. Roblox states that modified clients can lead to account restrictions. See [Roblox anti-cheat messages](https://en.help.roblox.com/hc/en-us/articles/24275616578708-Anti-cheat-Messages).

## Data locations

- Account metadata: `~/Library/Application Support/Roblox Account Manager/Accounts.json`
- Group names: `~/Library/Application Support/Roblox Account Manager/Groups.json`
- Launch Sets, experiences, saved private servers, and active target records: the same local data folder
- Managed copies: `~/Library/Application Support/Roblox Account Manager/Instances`
- Roblox sign-ins: one encrypted macOS Keychain item named `sessions-v2`

Removing an account deletes its Roblox sign-in from the current Keychain item and removes its local account details.

## Development notes

[docs/V1_LIVE_TEST_REPORT.md](docs/V1_LIVE_TEST_REPORT.md) records the live checks completed for this release and the cases that still need controlled test accounts. [docs/V1_IMPLEMENTATION_SPEC.md](docs/V1_IMPLEMENTATION_SPEC.md) defines the release behavior. [docs/RESEARCH.md](docs/RESEARCH.md) records old experiments and current technical decisions. [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) is development history. These files do not replace this current guide.

Windows-only features from the original project remain outside this release. These include Win32 window placement, Windows registry work, a local control API, process injection, and gameplay automation.

## License

This port uses GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

# Roblox Account Manager for Mac

A native SwiftUI app for running several Roblox accounts on one Mac. It saves each Roblox session in macOS Keychain and launches a separate unchanged copy of the installed Roblox app for each managed account.

This project is independent. Roblox Corporation does not make or approve it. Use only accounts that you own or have permission to use.

## What the app can do

- Save several Roblox accounts without saving their passwords.
- Run several saved accounts at the same time in separate Roblox windows.
- Assign profiles to halves, quarters, or the full usable area of any connected display.
- Start one account, several selected accounts, or every account in a group.
- Stop one managed Roblox window or close all managed windows with **Stop All**.
- Give accounts easy-to-read names, encrypted profile notes, and membership in more than one group.
- Search saved accounts and show only the accounts in one group.
- Save common account and game choices as **Launch Sets** so you can reuse them later.
- Keep a list of recently played games and mark games as favorites.
- Let Roblox choose a server, choose a public server with enough open spaces, or use a supported private-server link.
- Save private-server links with names and browse them again without pasting them each time.
- Find friends whose current game is visible to at least one saved account.
- Join a visible friend with several accounts. The app can relay through existing friendships between saved accounts and confirms each server hop before it continues.
- Open Roblox Home, Profile, Settings, or Security as one saved account without signing the other accounts out.
- Use Roblox Play and Join buttons in that account's website window. The correct saved account opens in its own managed Roblox window.
- Check whether a saved account is still signed in and sign in again without losing its name, groups, notes, favorites, or Launch Sets.
- Export and import account names, groups, games, and Launch Sets without copying Roblox sign-ins or profile notes.
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
3. Use the checkboxes beside the account names to choose the accounts that should open together.
4. Optional: open **Launch Defaults** to set graphics, sound, and saved window placements.
5. Select **Choose Game**, paste the Roblox game link, and confirm its name and icon. You can also reuse a recent game.
6. Keep **Let Roblox choose** or select another server option.
7. Review the inline **Window arrangement** editor. It shows the arrangement from **Launch Defaults** by default. Move a profile only when this launch needs a different layout.
8. Select the blue launch button. Each selected account opens in its own Roblox window.

The app fills the Place ID after you choose a game. The number remains available as an advanced field. Most users do not need a Job ID. A Job ID is an advanced, temporary code for one server that is already running.

## Build from source

```sh
git clone <repository-url>
cd roblox-account-maneger-mac
swift test
RAM_ALLOW_AD_HOC_BUILD=1 ./scripts/build-app.sh
open "dist/Roblox Account Manager.app"
```

The build script creates one universal app for Apple silicon and Intel Macs. `VERSION` is the source for the app version written into the packaged Info.plist and used by runtime network headers. Versions through 1.1.1 use an installed Apple code-signing identity when one is available. Version 1.1.2 and later release builds use one project-owned self-signed certificate that contains only the project name. To choose a specific identity for a local build, set `RAM_SIGNING_IDENTITY` to its certificate hash or name.

For a local package check without the private release identity, run `./scripts/smoke-test-app.sh`. It creates an ad hoc-signed app that must not be published. The smoke run uses empty temporary storage and does not read saved accounts or Keychain items. Release packaging always rejects an ad hoc signature.

Release maintainers create the ZIP, checksum, and project signature with:

```sh
./scripts/create-project-signing-identity.sh
./scripts/package-release.sh
(cd dist && shasum -a 256 -c "Roblox-Account-Manager-for-Mac-1.2.0.zip.sha256")
```

Run the identity script only once on the release Mac. It creates a 20-year project certificate and non-exportable private key through a temporary memory disk, imports them into the user's Keychain, and leaves no private-key file in the repository or normal disk storage. The certificate subject contains the project name and no email address. Keychain can ask for approval when the release build uses this private key.

Version 1.1.1 is the signing bridge. Its signed app stores the exact SHA-256 fingerprint of the project certificate that will sign version 1.1.2 and later. Rebuilding version 1.1.1 requires `RAM_BRIDGE_BASE_APP` to point to the public version 1.1.0 app and proves that the two existing signatures accept each other. Version 1.1.2 and later do not use that bridge-base setting. The updater authorizes only the validated 1.1.2 code-signing requirement to read the existing Keychain items before it replaces 1.1.1. It validates the installed app again after replacement and restores the previous app if that check fails. Create the separate project update key once with `xcrun swift scripts/release-signature.swift create`. That key stays in the Mac Secure Enclave, and macOS requires user approval for each release signature.

Version 1.1.2 and later must match the pinned project certificate and the separate project update signature. Packaging stops if the app, certificate, or signing metadata contains an email address or local user home path. This project intentionally does not use Developer ID signing or Apple notarization because those systems connect a public build to an Apple Developer identity. The anonymous project certificate contains the project name only. macOS can show an unidentified-developer warning after a manual download.

For a first manual launch, download only from this repository, verify the published SHA-256 file, then Control-click the app in Finder and select **Open**. Do not disable Gatekeeper and do not remove quarantine attributes with a command. Existing users should use the signed in-app update path.

## Add accounts

Use **Add Account** and sign in on the Roblox page inside the app. Select **Save This Account** when the page is ready. The page does not keep browsing history. The app checks which Roblox account signed in and saves its Roblox session in Keychain, the private password storage built into macOS.

The app never sees or saves your Roblox password. The advanced paste option accepts a `.ROBLOSECURITY` session value. Treat that value like a password and never send it to another person.

The app stores all saved Roblox sessions inside one Keychain item. Version 1.0.2 uses a new item because older ad hoc builds could lose access after an app update and show error `-25293`. If macOS allows access to the old item, the app moves every session automatically. If macOS blocks the old item, account names and settings remain, but each affected account must sign in once. Version 1.0.2 and later release builds use a stable Apple signing identity so later updates keep access to the new item.

The managed Roblox website window keeps top-level browsing on `roblox.com`. Its temporary Roblox session cookie is secure and HTTP-only. Secure frames used inside Roblox pages can load without an external-link warning, and they do not receive the Roblox session cookie. A real link to another site asks before it opens in the default browser and names the destination.

You can give one account an alias, an encrypted profile note, and several groups. These fields do not change the Roblox account. Delete a group from the group menu when you no longer need it. The accounts in that group stay saved. Profile notes use a separate macOS Keychain item. Existing plain-text notes move into Keychain and are removed from the account file and its backup when the updated app first loads them.

## Update the app

Version 1.0.3 and later include the in-app updater. The app checks for a newer final release when it opens. If one is available, the main sidebar shows **Update available**, **Details**, and a dismiss action. When the update is ready, the same notice shows **Restart to update**. You can also choose **Roblox Account Manager > Check for Updates** or open **About > Check for Updates**.

The Update Center lists every published final release with its date and version. Select a release to read its full Markdown release notes. Opening the history does not download or install an update.

The app checks only final releases from this project's public GitHub page. It compares all final releases by version, so a bridge install can find a newer release even when GitHub does not mark that release as latest. When a newer version exists, it downloads the release ZIP, checksum, and project signature. It checks GitHub's file fingerprints, the published checksum, the project signature, app name, version, bundle identifier, and Intel and Apple silicon support before showing **Install and Restart**. Version 1.1.1 also records the approved project certificate fingerprint. It accepts version 1.1.2 and later only when the app has a valid signature from that exact certificate. Before the bridge installs 1.1.2, it also prepares the saved sign-ins and encrypted notes for the new stable app identity.

Version 1.1.1 was the temporary signing bridge from version 1.1.0. Version 1.1.2 completed that transition. Current releases use the stable project certificate and update signature. The updater compares all final project releases by version instead of trusting only GitHub's latest marker.

Version 1.2.2 and later skip the Keychain access migration when the installed app already uses the downloaded update's verified project signing identity. Routine updates therefore do not repeat the one-time signing-transition approval work.

```sh
release_version=$(tr -d '[:space:]' < VERSION)
gh release create "v$release_version" dist/Roblox-Account-Manager-for-Mac-"$release_version".zip{,.sha256,.sig} \
    --title "Roblox Account Manager for Mac $release_version" \
    --notes-file /path/to/release-notes.md \
    --latest
```

The updater never stores a GitHub login or token. It does not show or install a draft or prerelease. It downloads an update only after you select **Update**, and it replaces the app only after you select **Install and Restart**. The current app must be in a location that your macOS account can change, such as an app that you copied to `/Applications`. A hidden copy of the previous version stays beside the app as a recovery backup.

Version 1.0.2 and older do not have the updater. Install version 1.0.3 once with the release ZIP. Later public releases can use the in-app button.

## Launch accounts

Every managed launch uses a separate copy of `/Applications/Roblox.app`. This includes the first account. You can start another account later without closing the first one.

Before it prepares a copy, the manager checks the installed Roblox version against Roblox's current Mac release. If they differ, stop all managed clients, open `/Applications/Roblox.app`, let it update, then quit Roblox and retry. The next launch rebuilds any old copy. The manager does not update Roblox itself. It also stops the launch if the version check fails, so an unchecked copy cannot start its own update.

The normal copy stays unchanged. Every file must match the installed Roblox app. It keeps Roblox Corporation's original Apple-anchored signature. The manager stops the launch if the copy or signature check fails. It never edits `/Applications/Roblox.app`. Each managed account also gets separate Roblox app data and a small child-process environment that excludes unrelated parent secrets. Leaving a game and using the Roblox app does not switch the other managed copies to the same account.

Select one account and choose **Open Roblox App** to open that account's Roblox home screen without joining a game. You can also right-click an account and choose **Open Roblox App**. You do not need to wait for that app to finish opening before you start a different account.

To open several account apps without joining a game, use the checkboxes in the sidebar. The main view changes to **Launch Multiple Accounts** and lists each selected account handle. Select **Open Roblox Apps** there. The manager requests their account sessions and starts their Roblox copies together.

To launch:

1. Use the checkboxes to choose accounts from the list, or use **Select Group**.
2. Select **Choose Game**. Paste a Roblox game link, or choose a recent or favorite game. Confirm the name and icon.
3. Let Roblox choose a server, browse public servers, find a player, or enter a supported private server link.
4. Select the blue launch button.

A Place ID is the number after `/games/` in a Roblox experience link. **Choose Game** fills it automatically, so most people do not need to find or type it. A Job ID identifies one current server. Job IDs stop working when that server closes, so the app never saves them as a future launch choice. Choosing or typing a different Place ID returns the server choice to **Let Roblox choose**.

Open **Choose Server > Private Servers** to save a private-server link with a clear name. Current Roblox `roblox.com/share` links and older `/games/` private-server links both work. For a current share link, the app checks the link through one saved account to find its Place ID. Roblox then checks each launched account's access separately. The same account-specific check runs when you open a current private-server share link in the built-in Roblox website window. Select the saved name later to reuse the link and its Place ID. Links that were already saved to accounts or Launch Sets appear in this list after the app loads them.

The bottom **Advanced fallback** changes copied app settings and applies a different signature. Roblox can detect that change. Use it only for recovery tests. Normal managed launches use unchanged copies.

## Launch defaults

Open **Launch Defaults** from the main toolbar, choose **Tools > Launch Defaults**, or press **Command-Shift-L**. Set the graphics and sound defaults that apply before each launch. The window also lists each connected display with its current pixel resolution and usable workspace.

Select **Arrange Automatically** to fit up to four profiles on each connected display. The app uses a full desktop, halves, a three-window layout, or quarters based on the number of profiles. Select **Full Screen All** when every profile should have its own native macOS full-screen Space.

For a custom layout, drag a profile onto Top Left, Top, Top Right, Left, Fill Desktop, Right, Bottom Left, Bottom, or Bottom Right. Corners use one quarter of the usable display. Top, Bottom, Left, and Right use one half. Fill Desktop fills the usable display without covering the menu bar or Dock. The separate **Full-screen Spaces** target creates one Space per profile on that display. Selecting a profile and then selecting a target provides the same result without dragging.

Larger regions replace assignments that they overlap. For example, placing one profile on the left half removes profiles from the top-left and bottom-left quarters. A disconnected monitor remains assigned by name and resolution, but the manager does not move that profile to the wrong display. Reconnect the display and launch again.

macOS requires Accessibility permission before one app can move another app's windows. The manager checks this before it saves or applies an arrangement. If access is missing, it opens Accessibility settings so you can turn on Roblox Account Manager. If it is already on but the app still reports that permission is missing, turn it off and on again, then select **Check Again**. This one-time reset can be necessary after the app's signing identity changes. The manager uses the launched Roblox process ID and the standard macOS window position and size attributes. If Roblox restores its own minimum size, the manager keeps that native size and anchors it as close as possible to the selected region. Window placement does not scale the rendered window, edit Roblox, inject code, or change Roblox settings.

Batch launches show the graphics and sound choices from **Launch Defaults**. Changing a value creates a temporary override for that batch. **Use Launch Defaults** removes it. Batch launches also show the monitor and selected profiles below the **Launch Accounts** action. Moving or removing a profile creates a temporary layout for that launch. **Use Saved Arrangement** removes the window override. Launch Set settings can save their own graphics, sound, and window overrides with the set.

Each windowed Roblox placement starts as soon as its own managed process and game window are ready. A slow account does not delay other windowed placements. The manager retries temporary macOS Accessibility failures and does not activate Roblox for normal window movement. **Fill Desktop** uses the display's current usable desktop area.

Native full-screen transitions are different. macOS creates a Space for each window, so the manager queues them and requests the full-screen state on the exact managed Roblox process. This request sets full screen to true. It is not a toggle, so the manager can repeat it safely while the user changes apps, windows, or Spaces. The manager waits for macOS to confirm the state before it starts the next profile. It does not activate Roblox or change the user's current app or Space. The standard full-screen control remains a compatibility fallback for windows that do not expose a writable full-screen state.

The manager reads the current usable display area for every launch. This automatically accounts for the menu bar, Dock position, Dock auto-hide boundary, and camera housing. Global placements are local device preferences and are not included in backups. A custom layout saved inside a Launch Set is included with that Launch Set in metadata backups.

## Find Players

Open **Find Players** in the toolbar or choose **Tools > Joinable Players**.

The window checks the online friends that Roblox shows to each saved account, one account at a time. It merges duplicate players and shows which saved accounts can see each player. It does not guess hidden activity or scan public server pages.

To join a friend with several accounts:

1. Select the friend.
2. Select every account that you want to launch. Accounts that already have a managed Roblox client running are disabled.
3. Include at least one account shown under **Visible To**. Roblox gave that account the friend's server, so it must start first.
4. Select **Join Accounts with Friend Relay**.

The manager checks the existing friendships between the selected accounts and builds the shortest available layers from the **Visible To** accounts. It starts a source account through the selected player. It confirms the exact Place ID and Job ID, then starts the next account through that confirmed friend. It repeats this process for each layer. The account list shows the current path and result for every account.

Each server confirmation has a hard 15-second limit, including slow Roblox requests. If an account does not reach the exact server, the app marks it **Could not join**. A full, restricted, or changed server can all cause this result, so the app does not claim a specific cause that Roblox did not confirm. Close any Roblox client that stayed open, then select the account again to retry. Other independent friend paths continue.

If an account has no usable friend path, the manager keeps the old direct Job ID attempt as a fallback. It also checks that result. Select **Stop Relay** to prevent any accounts that have not started yet from opening. Accounts that already joined stay open.

The relay does not send friend requests or change any Roblox friendship. Roblox checks visibility, access, available space, age, region, and game limits for every account. A private or restricted server can still reject an account.

This friend flow makes no public-server requests. It reads existing friendship lists and uses each saved account's authenticated presence only to confirm arrival. Public-server browsing remains a separate manual tool.

Roblox controls online visibility and join access. See [Roblox Online Status and Visibility](https://en.help.roblox.com/hc/en-us/articles/39144167691284-Online-Status-and-Visibility).

## Selected-account Roblox website

Right-click an account or use its detail view to open Roblox Home, Profile, Settings, or Security. Each website window:

- Shows the active alias and Roblox username at all times.
- Uses a separate non-persistent WebKit data store.
- Receives only that account's saved session.
- Clears web data when it closes.
- Saves a changed session only after Roblox confirms the same user ID.
- Opens non-Roblox links in the normal browser only after confirmation.
- Accepts Roblox Play and Join actions only from the main page.
- Asks before it starts a native Roblox client for this account.

When you select Play or Join on the Roblox website, the manager reads only the Place ID and server choice. It does not reuse the website's launch ticket. After you confirm the launch, it requests a new ticket for the account shown at the top of the window, then starts that account in a separate unchanged Roblox copy. It does not open the normal Roblox app. If that account already has a managed client running, the manager stops the second launch and tells you why.

Use this window when you want to browse as one saved account, start a game from its page, or use a friend's Join button when that account is allowed to join them.

## Launch Sets and experiences

A Launch Set is a saved shortcut for accounts, one game, and one server choice. Its graphics and sound controls show **Launch Defaults** until a value changes. The changed choices save with the Launch Set, and **Use Launch Defaults** removes the override. In Launch Set settings, selecting a group also selects its current members in the Accounts section. Clearing a group clears those members unless another selected group still contains them. It does not save a public Job ID because that code stops working when the server closes. When a Launch Set uses a private server, you can choose a link from the saved private-server list. Private server links stay local and are excluded from normal backups.

The experience chooser records recent Place IDs and launch counts. It also saves the game's current name and icon when Roblox provides them. You can mark an entry as a favorite. A numeric Place ID stays the source of truth, so a metadata lookup is not required to launch.

## Backup and diagnostics

Open **Tools > Diagnostics and Backup**.

Normal backups can include account IDs, usernames, aliases, groups, favorites, recent experiences, and Launch Sets. They exclude encrypted profile notes, sessions, launch tickets, access codes, active process IDs, raw network responses, and private server links. Import matches accounts by Roblox user ID and keeps the Keychain session and encrypted profile note already stored on this Mac.

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
- Profile notes: one separate encrypted macOS Keychain item named `notes-v1`
- Window layout assignments: the app's local macOS preferences; these contain account IDs, display details, and snap regions only

Removing an account deletes its Roblox sign-in and encrypted profile note from Keychain, then removes its local account details.

## Development notes

[docs/V1_LIVE_TEST_REPORT.md](docs/V1_LIVE_TEST_REPORT.md) records the live checks completed for this release and the cases that still need controlled test accounts. [docs/V1_IMPLEMENTATION_SPEC.md](docs/V1_IMPLEMENTATION_SPEC.md) defines the release behavior. [docs/RESEARCH.md](docs/RESEARCH.md) records old experiments and current technical decisions. [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) is development history. These files do not replace this current guide.

The original Win32 window-placement code remains outside this release. The Mac app uses a separate native design based on connected displays, visible macOS workspace geometry, managed process IDs, and Accessibility window attributes. Windows registry work, private window scaling, a local control API, process injection, and gameplay automation remain outside this release.

## License

This port uses GNU GPL version 3 to match the original project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

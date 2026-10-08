# User guide

[Back to the README](../README.md) · [Development guide](DEVELOPMENT.md)

- [Install and update](#install-and-update)
- [Roblox closes at once](#roblox-closes-at-once)
- [Add accounts](#add-accounts)
- [Launch accounts](#launch-accounts)
- [Launch defaults](#launch-defaults)
- [Find Players](#find-players)
- [Account website](#selected-account-roblox-website)
- [Launch Sets and games](#launch-sets-and-experiences)
- [Backup and diagnostics](#backup-and-diagnostics)
- [Roblox and macOS limits](#roblox-and-macos-limits)
- [Data locations](#data-locations)

## Install and update

Download the ZIP and its matching `.sha256` file from the [project releases](https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest). In Terminal, change to the download folder and run:

```sh
shasum -a 256 -c Roblox-Account-Manager-for-Mac-*.zip.sha256
```

The result must say `OK` for the ZIP you plan to open. If several releases are in that folder, use the exact checksum filename for your download. Extract the ZIP and move **Roblox Account Manager.app** to Applications.

The project uses its own signing certificate and does not use Apple notarization. macOS can show an unidentified-developer warning after a manual download. After you try to open the trusted download, open **System Settings > Privacy & Security** and select **Open Anyway**, then confirm **Open**. Do not disable Gatekeeper or remove quarantine attributes with a command. If macOS says the app is damaged or will harm your computer, stop and check the download instead. See [Apple's instructions for opening downloaded apps](https://support.apple.com/en-us/102445).

The manager checks for a newer final release when it opens. Choose **Roblox Account Manager > Check for Updates** or **About > Check for Updates** to open the Update Center. You can read release history without downloading an update.

Select **Update** to download a release. The manager checks the download, project signature, app identity, version, and support for both Mac processor types before it offers **Install and Restart**. The app must be in a location that your macOS account can change. A normal update does not need administrator access. The updater keeps a hidden copy of the old app beside it for recovery.

Version 1.2.4 fixes a compatibility check that can reject a valid update on some Macs. An older manager still has the old check. If it reports that the download has the wrong name, version, identifier, or processor support, quit the manager and install the release ZIP manually. Replace the old app in Applications. This does not remove the saved account data.

Versions 1.0.2 and older have no updater. Install a release ZIP manually once. Older signing-transition details are in the [development guide](DEVELOPMENT.md#signing-history).

## Roblox closes at once

1. Choose **Roblox Account Manager > Check for Updates** and install an available manager update.
2. Select **Stop All** and retry one account. If the installed Roblox version differs from the current release, the manager opens `/Applications/Roblox.app` to let Roblox update. Let it finish, then quit Roblox and retry. If Roblox closes or does not update, use **Play** on an experience page at [roblox.com](https://www.roblox.com), as described by [Roblox Support](https://en.help.roblox.com/hc/en-us/articles/203313000-Mac-Upgrade-Fail-Message). If Roblox also fails outside the manager, repair the normal installation first.
3. Try **Open Roblox App** with one saved account. Then try **Launch Game**. Record which action fails and the exact manager error, if one appears.
4. Open **Tools > Diagnostics and Backup**, select **Run Check**, then use **Export Redacted Report**. A passed check confirms only what that check tested. It does not prove that Roblox can stay open or join a game.
5. If the problem remains, select **Feedback**. Include the manager version and build, macOS version, and processor type. The form lets you include these details before it loads. State whether Roblox works outside the manager and whether one account or all accounts fail.

Do not send a metadata backup as a diagnostic report. Backups contain account details. Never send passwords, session values, private-server links, access codes, or unreviewed Roblox logs. If you share a screenshot or crash report, first remove account details, local paths, and other private information.

Keep saved accounts while you check the problem. Removing an account deletes its saved sign-in and profile note. The modified fallback changes Roblox and can cause restrictions; it is not a confirmed fix for an unknown crash.

## Add accounts

Use **Add Account** and sign in on the Roblox page inside the app. Select **Save This Account** when the page is ready. The page does not keep browsing history. The app checks which Roblox account signed in and saves its Roblox session in Keychain, the private password storage built into macOS.

The manager does not store your Roblox password. The advanced paste option accepts a `.ROBLOSECURITY` session value. Treat that value like a password and never send it to another person.

The managed Roblox website window keeps top-level browsing on `roblox.com`. Its temporary Roblox session cookie is secure and HTTP-only. Secure frames used inside Roblox pages can load without an external-link warning, and they do not receive the Roblox session cookie. A real link to another site asks before it opens in the default browser and names the destination.

You can give one account an alias, an encrypted profile note, and several groups. These fields do not change the Roblox account. If you select accounts with the sidebar checkboxes before you create a group, the app adds those accounts to the new group. Delete a group from the group menu when you no longer need it. The accounts in that group stay saved. Profile notes use a separate macOS Keychain item. Existing plain-text notes move into Keychain and are removed from the account file and its backup when the updated app first loads them.

## Launch accounts

Every managed launch uses a separate copy of `/Applications/Roblox.app`. This includes the first account. You can start another account later without closing the first one.

Before it prepares a copy, the manager checks the installed Roblox version against Roblox's current Mac release. If they differ and Roblox is not running, it checks the installed app's signature and opens the normal Roblox app once to let Roblox update itself. It does not close running games. Let the update finish, quit Roblox, then retry. The manager checks the version and signature again before it rebuilds an old copy. It also stops the launch if the version check fails, so an unchecked copy cannot start its own update.

The normal copy stays unchanged. Every file must match the installed Roblox app. It keeps Roblox Corporation's original Apple-anchored signature. The manager stops the launch if the copy or signature check fails. It never edits `/Applications/Roblox.app`. Each managed account also gets separate Roblox app data and a small child-process environment that excludes unrelated parent secrets. Leaving a game and using the Roblox app does not switch the other managed copies to the same account.

Select one account and choose **Open Roblox App** to open that account's Roblox home screen without joining a game. You can also right-click an account and choose **Open Roblox App**. You do not need to wait for that app to finish opening before you start a different account.

To open several account apps without joining a game, use the checkboxes in the sidebar. The main view changes to **Launch Multiple Accounts** and lists each selected account handle. Select **Open Roblox Apps** there. The manager requests their account sessions and starts their Roblox copies together.

To launch:

1. Use the checkboxes to choose accounts from the list, or use **Select Group**.
2. Select **Choose Game**. Paste a Roblox game link, or choose a recent or favorite game. Confirm the name and icon.
3. Let Roblox choose a server, browse public servers, find a player, or enter a supported private server link.
4. Select **Launch Game** or **Launch Accounts**.

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

Diagnostics use the same installed Roblox signature requirement as the launcher. They do not start a Roblox client. **Export with Private Links** is a separate option and includes private-server links only after a warning. Protect that backup like a password.

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
- Private-server links: separate entries in macOS Keychain; the local files contain references only
- Window layout assignments: the app's local macOS preferences; these contain account IDs, display details, and snap regions only

Removing an account deletes its Roblox sign-in and encrypted profile note from Keychain, then removes its local account details.

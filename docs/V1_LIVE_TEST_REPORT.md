# Version 1.0.3 live test report

Date: August 10-11, 2026

This report uses saved account labels only. It does not contain usernames, cookies, private links, launch tickets, or personal account IDs.

## Version 1.0.3 updater

- The native Software Update window checked the public GitHub project without a login or token.
- Unit tests cover numeric version ordering, exact release filenames, prerelease rejection, standard SHA-256 output, and strict checksum filename parsing.
- The final updater package test is recorded below after the version 1.0.3 release assets are published.

## Version 1.0.2 Keychain update

- Version 1.0.1 reproduced macOS Keychain error `-25293` when Add Account tried to update the shared `sessions-v1` item from an app with a different ad hoc signature.
- Version 1.0.2 created the new `sessions-v2` item without deleting or weakening access to the old item.
- A real Roblox account was added through the normal browser sign-in flow. The app closed the sheet, added the account to the sidebar, and showed the account as ready. Error `-25293` did not return.
- The release build used an installed Apple code-signing identity. Its designated requirement stayed the same in a temporary update build whose code-directory hash was different.
- The temporary update build read the new saved session and confirmed the account as ready. This tested the same app-update boundary that caused the original failure.
- The final packaged version replaced the installed app, opened the saved account, and confirmed it as ready again.
- The installed version 1.0.0 app was preserved as a local backup before version 1.0.2 was installed.

## Passed

- The installed Roblox app passed its expected Roblox Corporation signature check.
- The manager prepared two unchanged copies. File comparison and strict signature checks passed.
- The manager launched two saved accounts together through the normal batch flow.
- The main window showed both accounts as running at the same time.
- **Stop All** closed both managed clients. The main window returned to zero running clients.
- The selected-account Roblox website opened an authenticated Home page for the chosen account. The account identity stayed visible in the manager window.
- Closing the website window cleared its temporary web data and returned control to the manager.
- A Play button on a live Roblox game page started the account shown in the managed website window. The manager accepted Roblox's current `www.roblox.com/Game/PlaceLauncher.ashx` format, requested its own fresh ticket, and launched one unchanged copy. The normal Roblox tray process stayed open. Selecting Play again showed **Account is already running** and did not start a second copy.
- The current Joinable Players flow loaded friend results through saved account sessions. It did not use the public-server search path.
- Missing player names were restored through Roblox's public user lookup.
- The public-server endpoint reported a three-request, 60-second window. The manager stopped locally after the available requests, showed **Check paused** with the reset time, and did not call the server private or offer a confirmed join.
- An immediate **Check Again** stayed local. Checking resumed after the reported reset time and stopped safely at the next request boundary.
- A macOS 27 crash report showed that TCC terminated two managed Roblox clients because the responsible manager bundle lacked a microphone usage description. The prepared Roblox copies already contained Roblox's original description and passed byte and signature checks. The manager bundle now declares microphone, camera, and local-network use for the Roblox clients it starts.
- After the privacy-metadata fix, the installed manager started all three saved accounts together with the current friend server target. All three unchanged Roblox copies stayed running past the previous crash point for more than one minute. No new TCC crash report appeared. **Stop All** then closed the three managed clients and left the separate normal Roblox client running.
- The friend account that supplied the result started first. The other two accounts started about ten seconds later with the same Place ID and Job ID. The launch records confirmed one shared target across all three accounts. The friend launch code and its tests make no public-server requests.
- Existing per-account Keychain items migrated to the first shared session item during the version 1.0 work. Version 1.0.2 replaces that item because an ad hoc app update could lose access to it.
- Diagnostics passed for the Roblox installation, signature, local storage, disk space, account data, Keychain entries, prepared copies, process records, friends service, and public server service.
- The opt-in exact-copy integration test started two unchanged Roblox processes, verified their copies and signatures, stopped both, and left no managed processes.

## Not completed

These cases need controlled test accounts and server settings. The test did not change privacy settings or private-server access on personal accounts.

- Friend-only target
- Hidden target
- Public server with too few spaces
- Private server with one allowed account
- Private server with one denied account
- Target changes servers during refresh
- Source account signs out during refresh
- Roblox updates between launches

Mocked tests cover the decision paths for capacity, expired sessions, partial failures, private access checks, hidden or missing presence, rate limits, and server changes. These tests do not replace the remaining live cases.

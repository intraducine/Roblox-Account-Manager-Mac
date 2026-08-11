# Version 0.5 preview live test report

Date: August 10-11, 2026

This report uses saved account labels only. It does not contain usernames, cookies, private links, launch tickets, or personal account IDs.

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
- Existing per-account Keychain items migrated to one shared session item. The migration required approval for each old item once. A later rebuilt app requested approval only once for the shared item, not once per account.
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

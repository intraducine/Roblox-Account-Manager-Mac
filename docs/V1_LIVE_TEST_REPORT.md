# Release verification report

Latest update: August 18, 2026

This report uses saved account labels only. It does not contain usernames, cookies, private links, launch tickets, or personal account IDs.

## Version 1.1.2 transition re-audit

- Version 1.1.2 was published as a final release on August 18, 2026. Its tag points to the release commit, and its ZIP, checksum, and project-signature assets are uploaded.
- The public repository still marks version 1.1.1 as the latest release so older updater clients cannot skip the bridge.
- A fresh download of the public version 1.1.1 ZIP matched its checksum. Its P-256 project update signature also passed against the public key embedded in the updater.
- The exact certificate fingerprint pinned inside the published version 1.1.1 app matches the project certificate still installed on the release Mac.
- The current version 1.1.2 release build uses that exact project certificate. The local signing-transition integration test accepted the published version 1.1.1 app and current version 1.1.2 candidate, then rejected a candidate changed to an ad hoc signer.
- The current source suite passes 206 tests with zero failures. Six explicit integration tests remain opt-in because they use installed Roblox clients, a published update, a local signed-app transition, or macOS approval UI.
- A temporary Keychain access-control integration test passed by authorizing a requirement-bound tool to read one disposable item. The test removed that item and did not change the app's saved session or profile-note items.
- The published-update integration test downloaded version 1.1.2 through a disposable copy of the public version 1.1.1 bridge. It verified the remote asset digests, checksum, project update signature, app certificate, identifier, version, and processor support; replaced version 1.1.1; confirmed the backup; and restored version 1.1.1. The test preserved the real Keychain while the separate disposable-item test covered the access-control migration.
- The current version 1.1.2 app reports build 112, contains Apple silicon and Intel code, and passes strict deep code-signature validation.
- Every unpublished commit after version 1.1.1 uses a GitHub noreply address. Current source and commit-content scans found no personal email, user home path, token, Roblox session, or private release key.

## Version 1.1.1 signing bridge

- The source suite passes 162 tests with zero failures. Three installed-app integration tests remain opt-in.
- The updater requires a project P-256 archive signature and pins version 1.1.2 and later to one project-owned certificate fingerprint stored in the signed v1.1.1 app.
- The project signing key is held by the Mac Secure Enclave. A live sign-and-verify check passed and required user approval.
- The unpublished legacy test key was removed from Keychain.
- The project code-signing certificate contains the project name and no email address. Its private key stays in the release Mac's Keychain.
- Version 1.1.1 was published on August 14, 2026 and remains the GitHub release marked as latest so older updater clients cannot skip the bridge.

## Version 1.1.0 release readiness

- The complete source suite passed 145 tests with zero failures. Three installed-app integration tests remain opt-in.
- Every commit after version 1.0.4 and the final release worktree passed dedicated secret and personal-data scans.
- The release app reports version 1.1.0 build 110 and contains Apple silicon and Intel code.
- `Roblox-Account-Manager-for-Mac-1.1.0.zip` matches its checksum sidecar. Its SHA-256 value is `c61493dca6016c07ab66d75c55a5ac42f17fd38fcc3f49d8b428a3aa3bcc7816`.
- The ZIP contains only the app bundle. It contains no user home path, account handle, personal email, token, private key, saved account data, `.DS_Store`, AppleDouble file, or repository source.
- The exact packaged app was opened and reviewed in the main, Add Account, Joinable Players, Launch Sets, Diagnostics and Backup, and Updates windows.
- The public release description lists user-facing changes only. It does not include a verification section.

## Version 1.0.4 release verification

- The complete source suite passed 124 tests with zero failures. Three tests stayed opt-in because they start installed Roblox clients or install a published update.
- A complete static security review covered all 70 repository files. It found no live Roblox cookie, launch ticket, private key, API token, GitHub token, or saved account data.
- Ten source-backed security issues were fixed before packaging. The fixes cover the managed browser cookie, sign-in origin, web launch confirmation, Roblox app trust, modified-copy reuse, child environment, avatar URLs, response identity checks, private-link process records, and release command paths.
- The release app reports version 1.0.4 build 104. It contains Apple silicon and Intel code and passes strict deep code-signature checks.
- The app uses the same Apple Development signing identity as version 1.0.3 so the in-app updater and Keychain access can recognize it. The public code signature includes the certificate identity. It does not include a password, token, or Roblox session.
- `Roblox-Account-Manager-for-Mac-1.0.4.zip` matches its SHA-256 sidecar. Its SHA-256 value is `4e11c585344e48d26ddad4816fe4ce7c62ea408ee7c80e7ad7b7c1ebed7e4dc2`.
- The ZIP contains only the app bundle and its required files. It contains no `.DS_Store`, AppleDouble `._` file, repository source, local account data, or user home path.
- The opt-in updater integration test downloaded the public version 1.0.4 assets, checked their fingerprints and app identity, replaced a temporary signed version 1.0.2 app, confirmed its backup, and restored version 1.0.2. It passed with zero failures.
- No real Roblox account launch ran during this release check. The account-launch integration tests remain opt-in. The earlier live results below still describe the tested platform boundaries.

## Version 1.0.3 updater

- The native Software Update window checked the public GitHub project without a login or token.
- Unit tests cover numeric version ordering, exact release filenames, prerelease rejection, standard SHA-256 output, and strict checksum filename parsing.
- The clean version 1.0.3 source passed 102 tests with zero failures. Three separate Roblox and updater live tests stayed opt-in during that run.
- The release package passed its strict code-signature check. It contains Apple silicon and Intel code, reports version 1.0.3 build 103, and matches its SHA-256 checksum file.
- The published GitHub release reported the same SHA-256 values as both local release files.
- The opt-in updater integration test downloaded the real version 1.0.3 GitHub release, checked both published fingerprints, checked the app signature and signing identity, replaced a temporary signed version 1.0.2 app, confirmed the version 1.0.2 backup, and restored that backup. The test passed with zero failures.
- A second end-to-end test used the visible Software Update window. The window found version 1.0.3 from a disposable version 1.0.2 app. **Download Update** prepared the signed release. **Install and Restart** replaced the app and opened it again at the same path. The restarted window reported version 1.0.3 and no newer final release. The saved account list remained available, and the hidden backup reported version 1.0.2.

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

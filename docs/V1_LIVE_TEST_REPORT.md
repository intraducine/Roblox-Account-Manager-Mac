# Version 1.0 live test report

Date: August 10, 2026

This report uses saved account labels only. It does not contain usernames, cookies, private links, launch tickets, or personal account IDs.

## Passed

- The installed Roblox app passed its expected Roblox Corporation signature check.
- The manager prepared two unchanged copies. File comparison and strict signature checks passed.
- The manager launched two saved accounts together through the normal batch flow.
- The main window showed both accounts as running at the same time.
- **Stop All** closed both managed clients. The main window returned to zero running clients.
- The selected-account Roblox website opened an authenticated Home page for the chosen account. The account identity stayed visible in the manager window.
- Closing the website window cleared its temporary web data and returned control to the manager.
- Joinable Players loaded public presence results and merged duplicate friends.
- Missing player names were restored through Roblox's public user lookup.
- A Roblox server rate limit produced a clear retry message. The app did not call the server private or offer a confirmed join.
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

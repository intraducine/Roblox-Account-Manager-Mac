# Implementation plan

## Product job

Give a Mac user one clear place to store their own Roblox account sessions and keep different accounts running in separate Roblox clients at the same time.

## Architecture

- `RAMacCore`: account model, metadata repository, Keychain vault, Roblox HTTPS client, launch URL builder, and isolated parallel-instance launcher.
- `RAMacApp`: SwiftUI account sidebar, account editor, launch bar, embedded WebKit sign-in, notices, and app commands.
- `RAMacCoreTests`: deterministic tests for storage, requests, and launch links.
- `RAMacAppTests`: batch-selection, concurrent-start, result, and retry tests.

The project has no third-party runtime dependencies.

## Interface direction

The app uses standard macOS structure and controls. It follows the system appearance. A native sidebar holds account selection, search, group actions, and batch checkboxes. A grouped form holds the selected account details. A bottom bar keeps the place, server, status, and launch action in one path.

## Current product behavior

- Every manager launch uses a separate, unchanged copy of the installed Roblox app.
- The first managed account also uses a separate copy. A second account can start later without closing it.
- Opening `/Applications/Roblox.app` is outside the manager.
- The optional advanced fallback changes and signs each copied app again. It stays off unless the user accepts the risk warning.
- A Place ID selects the experience or place.
- The server chooser can let Roblox choose, browse public servers, or use a player target that Roblox reports.
- Advanced options accept an existing Job ID or a supported private server link.
- Saved Roblox sessions use the `sessions-v2` Keychain item.
- Release builds use an installed stable Apple signing identity when one is available. This keeps Keychain access after app updates.
- If macOS blocks the older ad hoc Keychain item, the app keeps all non-secret account details and lets each affected account sign in once.
- The app checks for a newer final public GitHub release when it opens, shows an action notice, and lets users browse every final release description.
- The updater can verify the ZIP and app identity, install an approved update, and restart.

## Development history

The phases below record how the product was built. They are not current usage instructions. Phase 9 describes the active server-selection interface.

### Phase 1: complete in version 0.1.0

- Native Mac project and app bundle.
- Browser sign-in and manual session import.
- Keychain session storage.
- Account validation, list, search, alias, group, notes, and removal.
- Public place, job ID, and private-link launch paths.
- Automated tests, app packaging, license notice, and documentation.

### Phase 2: complete in version 0.2.0

- Verify the installed Roblox Corporation signature before every parallel launch.
- Make disposable APFS copies outside `/Applications`.
- Assign one unique Roblox bundle ID per managed account.
- Start and track concurrent clients without placing tickets in process arguments.
- Stop one selected account instance without closing other accounts.
- Clean stale copies after their processes exit.

### Phase 3: complete in version 0.3.0

- Native checkbox selection for any account mix.
- A group menu that selects or clears a complete account group.
- One shared place, job, or private server target for the batch.
- Concurrent ticket requests with no artificial launch delay.
- Continue-on-error behavior with failed accounts retained for one-step retry.
- Live batch progress, running state, and failure details.

### Phase 4: complete in version 0.4.0

- Replace the custom dark interface with standard SwiftUI macOS controls.
- Use a native split view, sidebar list, toolbar, grouped forms, sheets, and bottom bars.
- Follow the macOS system appearance and semantic colors.
- Keep the batch launch path visible without decorative effects or custom control styles.

### Phase 5: complete in version 0.5.0

- Keep one prepared Roblox copy per account instead of deleting it after each run.
- Sign the manager and parallel clients with an installed Apple identity when available.
- Give all parallel clients one stable shared permission identity.
- Track each account by its saved process ID and exact app path.
- Restore running-account state when the manager restarts.
- Stop all managed Roblox clients from the sidebar.
- Keep the optional Roblox menu-bar helper out of managed copies.
- Use one stable client identity for login-item and notification decisions.

### Phase 6: complete in version 0.6.0

- Make the exact Roblox app in `/Applications` the default launch path.
- Verify Roblox Corporation's signature before every official or fallback launch.
- Do not copy, edit, or sign Roblox in official mode.
- Track the replacement game process after Roblox hands off from its launch process.
- Keep the modified-copy method behind a clear user warning.
- Never switch from official mode to the fallback automatically.
- State the modified-client account risk in the app and README.

### Phase 7: complete in version 0.7.0

- Make byte-identical per-account copies of the official Roblox bundle.
- Keep Roblox Corporation's original Team ID, bundle ID, files, and code-directory hash.
- Store preparation metadata outside the copied app.
- Bypass Launch Services by starting each unchanged executable directly.
- Deliver each launch URL with a process-targeted Apple Event.
- Keep authentication tickets out of command-line arguments and logs.
- Reject and remove any copy that fails file or signature checks.
- Make Unmodified Parallel the default and keep the modified method behind its warning.

### Phase 8: complete in version 0.8.0

- Remove the direct Official Roblox choice from the interface.
- Use an exact, unmodified managed copy for every normal manager launch.
- Keep the modified fallback inside an advanced explanation with a clear warning.
- Replace the single group field with reusable multi-group membership.
- Add visible group creation, group filtering, and right-click membership actions.
- Add Shift-click batch selection for individual profiles.
- Explain job IDs and private server links beside the server field.
- Explain exact and modified bundles beside each launch action.
- Migrate old single-group account files without data loss.

### Phase 9: complete in version 0.9.0

- Replace the raw server field with one native Choose Server flow.
- Browse public servers by player count and open spaces.
- Put servers with enough room for the selected batch first.
- Find a player only when Roblox provides public, joinable presence.
- Keep discovery requests separate from saved account sign-ins.
- Cache public server results for one minute to respect Roblox request limits.
- Keep discovered Job IDs temporary because running servers can close.
- Keep manual Job ID entry under Advanced.
- Resolve current private-server share links separately for each saved account before launch.

### Phase 10: complete in version 1.0.2

- Fix Keychain error `-25293` after an ad hoc app update.
- Move sessions to a new versioned Keychain item without weakening its access rules.
- Migrate the older shared item when macOS permits access.
- Use a stable installed Apple signing identity automatically for release builds.
- Replace raw Keychain codes with direct recovery instructions.
- Define Place ID, Job ID, Launch Set, account selection, and friend visibility in plain language.
- Update the README, changelog, implementation specification, research notes, and live test report.

### Phase 11: complete in version 1.0.3

- Add Check for Updates to the app menu and About window.
- Read the public project's final release list and select the highest valid version.
- Require exact versioned ZIP and checksum asset names.
- Verify GitHub's SHA-256 digest and the release checksum.
- Extract into a private temporary folder and validate the app before installation.
- Require the same bundle identifier, version, universal processor support, and mutually compatible macOS signing requirements.
- Keep one hidden previous-version backup and restore it after a failed replacement.
- Require one explicit Install and Restart action.
- Keep draft releases, prereleases, GitHub credentials, and background installation outside the updater.

### Phase 12: complete in version 1.0.4

- Give every managed Roblox process a separate macOS home-data directory.
- Keep exact-copy app files and Roblox Corporation's original signature unchanged.
- Add an app-only account launch that uses an authentication ticket without a game target.
- Handle current `roblox://navigation/share_links` private-server requests from the built-in browser.
- Resolve the current share code with the selected account before launch.
- Track app-only startup by account instead of using one global launch lock.
- Open the Roblox app without a game for every account selected in the sidebar.
- Require a user confirmation for web-page Play and Join requests.
- Keep sign-in main-page navigation on secure Roblox domains.
- Mark managed session cookies as HTTP-only.
- Give Roblox children a minimal environment without parent-process secrets.
- Require an Apple-anchored Roblox Corporation signature before copying or launching Roblox.
- Rebuild the optional modified fallback before every use.
- Restrict account avatar requests to secure Roblox CDN addresses.
- Use fixed trusted command paths in release scripts.

### Phase 13: complete in version 1.1.0

- Simplify the main account and batch-launch screens for first-time users.
- Accept normal Roblox game links and show the game name and icon before selection.
- Keep aliases, encrypted notes, groups, account checkboxes, Find Players, and Launch Sets easy to reach.
- Add group deletion without deleting the accounts in that group.
- Make Launch Set group toggles select their current members in the Accounts section. Keep members selected when another enabled group also contains them.
- Run Launch Sets from their menu or by double-clicking a row.
- Check saved accounts and final app updates when the manager opens.
- Add a browsable Markdown release history and a compact update notice.
- Encrypt profile notes in a separate Keychain item and exclude them from backups.
- Prevent account avatar and game icon flicker while selections change.
- Give each isolated Roblox account home a working private Keychain.
- Stop all managed Roblox clients in one batched process pass.
- Quit the manager after its final window closes.
- Apply one concentric corner and spacing system across every custom app view.
- Use one continuous translucent material across the full account sidebar.

### Phase 14: version 1.1.1 signing bridge

- Sign every update archive with the project's Secure Enclave key.
- Require the archive signature before extraction or app replacement.
- Create one long-lived project signing certificate with a project-only subject and no email address.
- Embed that certificate's SHA-256 fingerprint in the signed bridge app.
- Require that exact project certificate for version 1.1.2 and later.
- Keep v1.1.1 marked as GitHub's latest release during the bridge period so v1.1.0 cannot skip it. After that transition, promote v1.1.2 or the current final release to latest.
- Prepare existing session and encrypted-note Keychain items for the new app identity before replacement.
- Stop v1.1.1 packaging until the project certificate is available.
- Stop v1.1.2 and later packaging if signing metadata or app files contain an email address or local user home path.
- Keep the v1.1.1 app on the existing signing identity so v1.1.0 can install the bridge.
- Require the public v1.1.0 app during packaging and prove mutual signing compatibility before creating v1.1.1 assets.
- Keep the release path free. State clearly that manual downloads are not Apple-notarized.

### Phase 15: version 1.1.2 native window layouts

- Show connected monitors with physical resolution and usable workspace.
- Put **Arrange Automatically** and **Full Screen All** before manual placement. Automatic layouts support up to four profiles per display and use a count-based full, half, three-window, or quarter pattern.
- Add drag-and-drop profile placement for halves, quarters, and the whole usable display.
- Name the whole usable display **Fill Desktop**. Keep native **Full Screen** separate and show the profiles that will receive their own macOS Spaces.
- Use current menu bar, Dock, camera-housing, scaling, and multi-monitor geometry for every launch.
- Save monitor assignments as local preferences and exclude them from backups.
- Bind every placement to the exact managed Roblox process ID.
- Use macOS Accessibility window attributes first and leave Roblox code unchanged.
- Wait for Roblox's settled frame after each resize. If Roblox enforces another size, anchor that native size inside the selected display region. Do not report the successful launch as failed.
- Start each placement as soon as its own managed Roblox process is ready. Do not wait for the slowest account in a batch. Retry temporary Accessibility and startup-window states without activating Roblox.
- Show the monitor and selected profiles inline below the Launch Accounts action for batch launches. Display saved placements until the user changes the inline layout, then use a temporary custom override.
- Show the same inline editor inside Launch Set settings. Store custom Launch Set layouts with the set and remap their account IDs during metadata import.
- Do not ship the rejected shared full-screen profile deck. Direct and bridged window moves into one type-4 full-screen Space were no-ops in the local proof.
- Support separate native full-screen Spaces through an idempotent Accessibility state request. Move the normal window to its display first, then serialize and confirm every Space transition without activating Roblox or changing the user's current Space. Keep the public Accessibility full-screen button as a compatibility fallback.
- Keep launches working when permission is missing or a saved display is disconnected.
- Test coordinate conversion, overlap replacement, persistence, PID binding, temporary batch overrides, legacy Launch Set decoding, and backup account-ID remapping.

### Phase 16: version 1.2.0 launch defaults

- Rename **Arrange Windows** to **Launch Defaults** and keep saved window placement in that window.
- Add clear graphics quality and volume defaults that run before every managed Roblox launch.
- Preserve every Roblox setting the manager does not control.
- Let batch launches use a one-launch graphics and sound override.
- Let Launch Sets save their own graphics and sound override and use it for direct and friend-relay launches.
- Prevent overlapping launch requests from starting duplicate clients or reporting a failed launch while another request succeeds.
- Replace the loaded feedback form details bar with one **Restart Form** action.

### Not planned without further research

- Process injection or anti-cheat workarounds.
- Password storage.
- Captcha solvers.
- Remote account-control or executor features.
- A local API that can expose account sessions.

These features add platform, account, or security risk and are not necessary for a correct account-switching workflow.

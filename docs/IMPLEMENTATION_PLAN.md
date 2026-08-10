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

## Delivery phases

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

### Suitable follow-up work

- Signed and notarized release builds.
- Export and import for non-secret account metadata.
- Better avatar caching and offline handling.
- Server browser using supported Roblox endpoints.
- Session health checks that run only when the user asks.

### Not planned without new research

- Process injection or anti-cheat workarounds.
- Password storage.
- Captcha solvers.
- Remote account-control or executor features.
- A local API that can expose account sessions.

These features add platform, account, or security risk and are not necessary for a correct account-switching workflow.

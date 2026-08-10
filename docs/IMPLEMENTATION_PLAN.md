# Implementation plan

## Product job

Give a Mac user one clear place to store their own Roblox account sessions and keep different accounts running in separate Roblox clients at the same time.

## Architecture

- `RAMacCore`: account model, metadata repository, Keychain vault, Roblox HTTPS client, launch URL builder, and isolated parallel-instance launcher.
- `RAMacApp`: SwiftUI account shelf, account editor, launch dock, embedded WebKit sign-in, notices, and app commands.
- `RAMacCoreTests`: deterministic tests for storage, requests, and launch links.

The project has no third-party runtime dependencies.

## Interface direction

The app uses a dark olive operations surface. Account avatars use one cut corner. The fixed launch dock repeats that cut at a larger scale. This links the account shelf to the final action without decorative cards, glows, or status chips.

The account shelf stays narrow. The selected account owns the detail view. The launch dock stays at the bottom and keeps the selected identity, place, server, status, and action in one path.

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

### Phase 3: suitable follow-up work

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

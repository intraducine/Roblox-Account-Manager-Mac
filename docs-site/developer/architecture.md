# Architecture

The app is a native macOS application built with Swift Package Manager. The package has two main targets and two corresponding test targets. It requires macOS 13 or later. For the SDK and build commands, see [Build, test, and release](../development).

## Package layout

| Path | Purpose |
| --- | --- |
| `Sources/RAMacApp` | SwiftUI and AppKit views, app lifecycle, account store, and window controls. |
| `Sources/RAMacCore` | Account persistence, Roblox services, launch handling, diagnostics, backups, and update checks. |
| `Tests/RAMacAppTests` | Tests for app-level behavior, views, and window support. |
| `Tests/RAMacCoreTests` | Tests for core services, storage, launch handling, and updates. |
| `scripts` | Build, smoke-test, signing, and release packaging scripts. |
| `packaging/Info.plist` and `VERSION` | App bundle metadata and marketing version. |

## Launch and account boundaries

`AccountStore` connects the interface to the core services. `RobloxLauncher` prepares and starts managed clients. The recommended path uses separate app copies and data directories, validates the installed Roblox version and verifies copies before launch.

`AccountRepository` stores account metadata. `KeychainVault` stores sign-ins and encrypted profile notes. Treat session values, tickets, private server links, and notes as private. Do not add them to logs, diagnostics, analytics, or normal backups.

## Finding the right code

- For account selection and launch controls, start with `ContentView`, `AccountDetailView`, and `BatchLaunchDock` in `Sources/RAMacApp`.
- For game links and server selection, see `RobloxGameReference`, `RobloxAPIClient`, and `ServerChooserView`.
- For finding friends and joining them, see `PlayerDiscoveryService`, `JoinAssessmentService`, and `FriendRelayService`.
- For window layouts, see `WindowLayoutController` in the app target and `WindowArrangement` in the core target. Window control uses macOS Accessibility permission.

Related tests are in `Tests/RAMacAppTests` and `Tests/RAMacCoreTests`.

## Backups and updates

`MetadataArchiveService` exports and imports metadata. Normal exports exclude sign-ins, notes, and private links; imports preserve existing Keychain items. `SoftwareUpdateService` validates downloaded updates and supports backup and restore. Tests cover both successful operations and failure recovery.

The updater checks the release asset digests, published checksum, update signature, app identity, code-signing certificate, and both supported processor architectures. It keeps a backup of the installed app and can restore it if replacement fails. Preserve those checks and recovery behavior when changing updates. A normal update must not need administrator privileges.

## Testing a focused change

Use `swift test --filter TestName` to run a related test while working. For example, `swift test --filter MetadataArchiveTests` exercises the backup code. The [development guide](../development) lists the broader checks and explains that the smoke test replaces the app in `dist`.

Launch and network tests use controlled inputs. They do not check whether a real account can join a game. Use test data rather than real account details, session values, or private links in fixtures and logs.

CI runs Swift tests, a strict-concurrency check, a release build, script checks, and a packaged-app smoke test.

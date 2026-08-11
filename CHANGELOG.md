# Changelog

## 2.0.0 - 2026-08-11

- Added friend discovery through saved account sessions without public-server scans.
- Added source-first friend joining for several selected accounts.
- Added managed Roblox website Play and Join actions that launch the correct saved account.
- Blocked a second launch when the same managed account is already running.
- Removed stale manual Job ID choices when the user changes the place or starts a different launch flow.
- Added local public-server request limits and clear reset times.
- Moved saved sessions into one encrypted Keychain item to reduce approval prompts after rebuilds.
- Added required macOS privacy descriptions for Roblox clients started by the manager.
- Improved running-process cleanup, Stop All behavior, launch guidance, and tests.
- Updated the app and docs for the Intraducine release identity.

## 1.0.0 - 2026-08-10

- First complete native macOS release.
- Added saved accounts, parallel unchanged Roblox copies, Launch Sets, groups, diagnostics, backup, and the SwiftUI interface.

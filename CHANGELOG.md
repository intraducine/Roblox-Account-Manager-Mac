# Changelog

## 1.0.3 - 2026-08-11

- Added **Check for Updates** to the app menu and About window.
- Added a native update window with checking, available, downloading, ready, installing, current, and error states.
- Downloads only final releases from the public project on GitHub.
- Requires the exact versioned app ZIP and checksum assets.
- Verifies GitHub's SHA-256 file digest and the published checksum file.
- Rejects an app with the wrong identifier, version, processor support, signature, or signing identity.
- Keeps a hidden previous-version backup and restores it if replacement fails.
- Requires the user to select **Install and Restart** before any app replacement.
- Added updater unit tests and current user and developer documentation.

## 1.0.2 - 2026-08-11

- Fixed macOS Keychain error `-25293` when adding an account after an app update.
- Moved saved Roblox sessions to the `sessions-v2` Keychain item.
- Migrates the older shared item when macOS still allows access to it.
- Keeps account names, groups, notes, games, and Launch Sets when macOS blocks the old item.
- Uses an installed Apple code-signing identity automatically so future builds keep one stable Keychain identity.
- Replaced raw Keychain status codes with recovery instructions.
- Rewrote account setup, multiple-launch, friend, server, Launch Set, About, and help text for new users.
- Updated every current guide and developer document for the new storage and signing behavior.

## 1.0.1 - 2026-08-11

- Saved the current Roblox game name and icon for recent and favorite games.
- Filled in missing names and icons for existing recent games.
- Limited saved icon addresses to secure Roblox CDN links.

## 1.0.0 - 2026-08-11

- First stable release of Roblox Account Manager for Mac.
- Added saved accounts, groups, Launch Sets, recent games, favorites, diagnostics, and non-secret backups.
- Added parallel launches through separate unchanged copies of the installed Roblox app.
- Added friend discovery through saved account sessions without public-server scans.
- Added friend joining for several selected accounts. An account that can see the friend starts first.
- Added managed Roblox website Play and Join actions that launch the correct saved account.
- Blocked a second launch when the same managed account is already running.
- Removed stale manual Job ID choices when the user changes the place or starts a different launch flow.
- Added local public-server request limits and clear reset times.
- Moved saved sessions into one encrypted Keychain item to reduce approval prompts after rebuilds.
- Added required macOS privacy descriptions for Roblox clients started by the manager.
- Improved running-process cleanup, Stop All behavior, launch guidance, and tests.
- Added named private-server links that can be browsed and reused.
- Added outside-click focus dismissal for text fields in windows and sheets.
- Added the handwritten RAM for Mac app icon.
- Updated the app and docs for the Intraducine release identity.

## 0.5.0 - 2026-08-10

- Preview release of the native SwiftUI app.
- Included saved accounts, parallel unchanged Roblox copies, Launch Sets, groups, diagnostics, backup, and the first complete interface.

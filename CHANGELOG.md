# Changelog

## Unreleased

- Standardized app-owned corners and edge controls with concentric radii and optical insets in every window.
- Replaced the update notice with a compact single-line action rail and tighter sidebar spacing.
- Added an update notice to the main sidebar when a newer final release is available.
- Added a browsable release history with dates, versions, and full Markdown release notes.
- Checked for a newer final release automatically when the account manager opens.
- Added group deletion to every group menu while keeping the accounts in that group.
- Ran saved Launch Sets from a right-click action or by double-clicking their list row.
- Quit the account manager automatically after its final window closes.
- Checked all saved accounts automatically when the account manager opens.
- Prevented a saved game icon from briefly disappearing when switching between accounts.
- Fixed the Roblox Keychain Not Found alert by giving each isolated account app its own temporary-password Keychain.
- Made Stop All close managed Roblox processes in one batch instead of repeating a full process scan for each account.
- Added group deletion without deleting accounts, and removed deleted group references from saved Launch Sets.
- Prevented account avatars from showing the previous account while the next avatar loads.
- Applied the full-row Advanced options control to the Launch Set editor.
- Clarified that backups exclude encrypted profile notes and that import preserves local Keychain notes.
- Corrected account-health spacing and shortened the empty Notes prompt.
- Fixed a false invalid-signature error on current macOS versions when starting unchanged Roblox copies.
- Fixed control hit areas and spacing in the game chooser, server row, advanced options, group controls, and multi-account launch screen.
- Kept multi-account checkboxes visible and listed every selected account handle before launch.
- Restored alias, encrypted notes, and multi-group editing to the main account page.
- Added group membership checkmarks to account menus and kept Find Players and Launch Sets visible in the toolbar.
- Opened Add Account in its own window and added Command-N as a second direct way to open it.
- Replaced the unclear Ready label with a direct description of what Launch Game will do.
- Simplified the main window around the two common tasks: opening an account app and launching a game.
- Kept direct Place ID entry inside a clearer full-row advanced options control.
- Added game lookup by normal Roblox link with a verified game name and icon before selection.
- Showed the selected game's name and icon on launch controls instead of relying on a Place ID alone.
- Rendered GitHub release notes as Markdown in the **What's New** update section.
- Replaced the technical no-release result with a direct **You're up to date** message.
- Moved profile notes from account JSON into a separate encrypted macOS Keychain item.
- Migrated existing profile notes and removed their plain-text values from account files and backups.
- Excluded profile notes from normal metadata exports.

## 1.0.4 - 2026-08-13

- Added **Open Roblox App** for an account-only launch with no game target.
- Allowed another account's Roblox app to start while the first app is still opening.
- Added **Open Roblox Apps** for all accounts selected in the sidebar.
- Isolated each managed Roblox copy's home, WebKit, cookie, cache, and preferences data by account.
- Fixed account sessions changing together after leaving a game for the Roblox app.
- Added current Roblox private-server share-link support in the built-in website window.
- Added current share-link support to saved private servers and Launch Sets.
- Added a confirmation before a Roblox website page starts a native managed client.
- Restricted the embedded sign-in window to secure Roblox main-page addresses.
- Marked managed Roblox session cookies as HTTP-only.
- Stopped Roblox clients from inheriting unrelated parent-process secrets.
- Required an Apple-anchored Roblox Corporation code-signing requirement.
- Rebuilt the optional modified fallback copy before every launch.
- Restricted imported avatar images to secure Roblox CDN addresses.
- Removed reusable private-server links from active process records.
- Hardened release scripts against inherited command search paths.

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

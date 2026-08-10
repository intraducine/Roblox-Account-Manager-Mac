# Port research

Research date: 2026-08-10.

This file records tests and earlier designs. It is not a user guide. See the README for current launch instructions.

## Upstream findings

The source is [ic3w0lf22/Roblox-Account-Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). The default branch is `master`. The latest published release found during research was 3.7.2. The project uses GNU GPL version 3.

The upstream application is a Windows Forms program that targets .NET Framework 4.7.2. Its main account type and launch code are in `RBX Alt Manager/Classes/Account.cs`. The portable launch sequence is:

1. Send `.ROBLOSECURITY` to `auth.roblox.com`.
2. Read the `x-csrf-token` challenge response.
3. Repeat the request with that token.
4. Read `rbx-authentication-ticket`.
5. Build a `roblox-player` launch URL with a Roblox PlaceLauncher URL.

The Windows account file uses Windows Data Protection API or password-based libsodium encryption. A Mac cannot use the machine-bound Windows Data Protection API. The port therefore keeps each session as a separate generic-password item in macOS Keychain. It keeps only non-secret metadata in JSON.

## Historical Mac findings

The installed client is `/Applications/Roblox.app`, bundle ID `com.roblox.RobloxPlayer`. Its `Info.plist` registers the `roblox-player` and `roblox` URL schemes. It also sets `LSMultipleInstancesProhibited` to `true`.

These facts support account-specific protocol launches. They do not support a promise of concurrent Roblox instances. Version 0.1.0 follows the platform declaration.

Version 0.6.0 makes the exact installed app the default. It verifies the original Roblox Corporation signature and opens the protocol URL through AppKit. It does not copy, write, or sign the Roblox bundle in this mode. The app waits for Roblox's short launch process to hand off to the stable game process before it saves the process ID.

A live test on 2026-08-10 launched two saved accounts toward place `1818` in official mode. One official client joined the game. The second official process did not stay open. The manager kept the first client marked as running and Stop All closed it. Before and after the test, the official `Info.plist` SHA-256 was `014e35df0f205938e50ebb10ebd9f7513906c183be305cca282bc1182cc33def`, the `RobloxPlayer` SHA-256 was `023659acbe36dec3b41503da5db5c37e70b995fbee1e2bf13f80893a0d3207cd`, and strict code-signature verification passed with Team ID `2CFABCH843`.

The same build required an explicit warning before enabling Modified Parallel Fallback. Two saved accounts then joined place `1818` in two managed processes. Stop All closed both. The app was returned to Official mode after the test.

## API behavior checked

An unauthenticated request to `https://users.roblox.com/v1/users/authenticated` returned HTTP 401 with an authentication-token error. The app uses this endpoint to reject an expired or incorrect imported session before Keychain storage.

The automated test suite uses isolated mock URL sessions. It checks the authenticated-user request, the two-step CSRF ticket exchange, header isolation, launch URL encoding, private-link parsing, metadata round-tripping, and backup creation. No real account secret is part of the tests.

Live testing on 2026-08-10 found that Roblox rejects the authentication-ticket POST with HTTP 415 when the request has no media type. Version 0.4.1 sends `{}` as `application/json` for both the CSRF challenge and ticket request. An end-to-end test then launched two saved accounts into place `1818` at the same time. macOS reported two running `Roblox Parallel` apps with distinct account-specific bundle IDs, and both Roblox windows loaded the experience.

Apple documents that local-network privacy tracks macOS programs through their code signatures and that ad hoc signing is not reliable for this purpose. Version 0.5.0 uses an installed Apple code-signing identity when available, gives all managed Roblox copies one shared bundle ID, and keeps the signed copies in Application Support. Two real clients launched together with that shared identity. After `Stop All`, the same two clients launched again without rebuilding their app bundles. Their modification times and CDHash values stayed unchanged, and no password or privacy prompt appeared during the test. Restarting the manager while both clients ran also restored both account states from their saved process records.

The same live logs showed that Roblox launched its bundled `RobloxMenuBar` helper. The helper registered the login item and requested notification permission. The current client ignored the old `FFlagEnableMacMenuBar` and `FFlagEnableMacDesktopNotifications` names. Roblox's live `MacDesktopClient` configuration showed the current names as `FFlagEnableMacMenuBar9` and `DFFlagEnableMacDesktopNotifications2`. The managed copies set both current settings to false, retain the old settings as a compatibility control, and remove the optional `RobloxMenuBar.app` helper before signing. The main Roblox executable is not modified.

A clean repeat test stopped the official Roblox tray and every old per-copy menu-bar process before launch. Two real accounts still joined place `1818`. No new tray or `RobloxMenuBar` process appeared. No visible password, microphone, local-network, login-item, or notification prompt appeared. Roblox still logged its menu-bar experiment and a denied notification-permission check, so the code does not claim that Roblox stopped making those API calls. macOS kept the shared managed background item disabled and already notified. A second launch reused both prepared copies with unchanged modification times, CDHash, bundle ID, and Team ID.

## Port boundary

Version 0.1.0 ports the account, storage, organization, and launch path. It does not copy Windows process injection, mutex control, registry access, Chromium download logic, Win32 window movement, local web control, or executor features. Those parts need separate Mac designs and separate safety review.

## Parallel-instance follow-up

The user supplied [Insadem/multi-roblox-macos](https://github.com/Insadem/multi-roblox-macos) as a prior Mac implementation. Its source was last pushed in 2024 and has no declared repository license. This project did not copy its source. The research used its observable method as a technical lead:

- Handle `roblox-player` links.
- Copy `/Applications/Roblox.app` into a temporary directory.
- Remove the old `/RobloxPlayerUniq` named semaphore.
- Allow multiple instances in the copy.

Live testing on 2026-08-10 showed that the old method no longer works unchanged. A copied app with the original `com.roblox.RobloxPlayer` bundle ID was redirected to the installed tray client. The current Roblox build also did not create `/RobloxPlayerUniq` during the probes.

The working version 0.2.0 method was:

1. Make an APFS clone of the valid installed Roblox bundle.
2. Assign the clone a unique bundle ID.
3. Set `LSMultipleInstancesProhibited` to false in the clone.
4. Apply an ad hoc local signature to the clone.
5. Open the game URL with that exact bundle and require a new application instance.

This produced two `RobloxPlayer` processes from different temporary bundles at the same time while the official `/Applications/Roblox.app` tray process stayed running. The test confirmed distinct process IDs, per-account process tracking, and selected-instance stop behavior. It used invalid tickets, so it could not join a game or expose an account. The test processes and bundles were removed afterward.

Version 0.2.0 implements that method per account. It uses AppKit to send the launch URL so the authentication ticket does not appear in a shell command or process argument. It verifies the official Roblox signature and Team ID `2CFABCH843` before making any copy.

Version 0.5.0 supersedes the temporary-copy and unique-ID parts of that method. It keeps one copy per account, gives every copy one shared stable ID, uses an installed Apple signing identity when available, and tracks each process by its saved PID and exact app path.

## Exact-copy parallel launch

Version 0.7.0 tests a different boundary. Every file in each managed Roblox app must stay byte-identical to `/Applications/Roblox.app`, and the copy must keep Roblox Corporation's original signature.

`open -n` and `NSWorkspace.OpenConfiguration.createsNewApplicationInstance` did not keep two exact copies open. Launch Services still applied `LSMultipleInstancesProhibited` from Roblox's unchanged `Info.plist`. Direct execution of `Contents/MacOS/RobloxPlayer` from two exact copies did keep two processes open on the same desktop. The old `/RobloxPlayerUniq` semaphore was absent and did not need removal.

A second isolated test launched two exact copies without URL arguments. It sent a `kInternetEventClass` and `kAEGetURL` Apple Event to each exact process ID. Each process received its own invalid test ticket and returned Roblox's expected HTTP 403 response. The URL was not present in either process argument list. This proves that the manager can route a launch link to one selected exact process without Launch Services and without command-line ticket exposure.

The implementation makes an APFS clone per account, runs recursive file comparison, performs strict deep code-signature validation, and compares the Team ID and code-directory hash with the installed app. Its small manifest stays outside the copied app. A changed file, changed signature, changed source version, or failed comparison causes a new copy or a stopped launch. The modified fallback remains separate.

The signed version 0.7.0 app then launched two saved accounts into place `1818` on the same desktop. Both clients reached the game in separate windows. Their process IDs were distinct, and each process ran from its own `Unmodified/Roblox.app` path. Recursive comparison against `/Applications/Roblox.app` found no changed files. Both copies passed strict deep signature validation with bundle ID `com.roblox.RobloxPlayer`, Team ID `2CFABCH843`, and CDHash `05d0d0f609d987b9d1812d310a5fd4f315090eb4`. Their `Info.plist` and `RobloxPlayer` SHA-256 values matched the installed app. No password, microphone, local-network, notification, login-item, or Automation prompt appeared during this test. Stop All closed both games and both copied menu helpers, and a system process check found no managed Roblox process afterward.

## Current parallel interface

Every manager launch uses a separate, unchanged copy of Roblox, even when only one account is selected. This lets another managed account start later without closing the first one. Opening `/Applications/Roblox.app` is outside the manager.

The account format stores a `groups` array. It can also read the older single `group` value and convert it to a one-item array. A separate `Groups.json` file keeps empty groups available. Group names are trimmed, sorted, and deduplicated without case sensitivity.

The native interface has a group filter, a visible New Group action, account-level membership checkboxes, and a right-click Groups menu. One account can belong to several groups. Shift-click selects the eligible account range for a batch. The bottom launch area explains unchanged copies and the advanced modified fallback. A separate information control explains that a Job ID selects one running public server and is not a Place ID.

# Port research

Research date: 2026-08-10.

## Upstream findings

The source is [ic3w0lf22/Roblox-Account-Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager). The default branch is `master`. The latest published release found during research was 3.7.2. The project uses GNU GPL version 3.

The upstream application is a Windows Forms program that targets .NET Framework 4.7.2. Its main account type and launch code are in `RBX Alt Manager/Classes/Account.cs`. The portable launch sequence is:

1. Send `.ROBLOSECURITY` to `auth.roblox.com`.
2. Read the `x-csrf-token` challenge response.
3. Repeat the request with that token.
4. Read `rbx-authentication-ticket`.
5. Build a `roblox-player` launch URL with a Roblox PlaceLauncher URL.

The Windows account file uses Windows Data Protection API or password-based libsodium encryption. A Mac cannot use the machine-bound Windows Data Protection API. The port therefore keeps each session as a separate generic-password item in macOS Keychain. It keeps only non-secret metadata in JSON.

## Local Mac findings

The installed client is `/Applications/Roblox.app`, bundle ID `com.roblox.RobloxPlayer`. Its `Info.plist` registers the `roblox-player` and `roblox` URL schemes. It also sets `LSMultipleInstancesProhibited` to `true`.

These facts support account-specific protocol launches. They do not support a promise of concurrent Roblox instances. Version 0.1.0 follows the platform declaration.

## API behavior checked

An unauthenticated request to `https://users.roblox.com/v1/users/authenticated` returned HTTP 401 with an authentication-token error. The app uses this endpoint to reject an expired or incorrect imported session before Keychain storage.

The automated test suite uses isolated mock URL sessions. It checks the authenticated-user request, the two-step CSRF ticket exchange, header isolation, launch URL encoding, private-link parsing, metadata round-tripping, and backup creation. No real account secret is part of the tests.

## Port boundary

Version 0.1.0 ports the account, storage, organization, and launch path. It does not copy Windows process injection, mutex control, registry access, Chromium download logic, Win32 window movement, local web control, or executor features. Those parts need separate Mac designs and separate safety review.

## Parallel-instance follow-up

The user supplied [Insadem/multi-roblox-macos](https://github.com/Insadem/multi-roblox-macos) as a prior Mac implementation. Its source was last pushed in 2024 and has no declared repository license. This project did not copy its source. The research used its observable method as a technical lead:

- Handle `roblox-player` links.
- Copy `/Applications/Roblox.app` into a temporary directory.
- Remove the old `/RobloxPlayerUniq` named semaphore.
- Allow multiple instances in the copy.

Live testing on 2026-08-10 showed that the old method no longer works unchanged. A copied app with the original `com.roblox.RobloxPlayer` bundle ID was redirected to the installed tray client. The current Roblox build also did not create `/RobloxPlayerUniq` during the probes.

The working current method was:

1. Make an APFS clone of the valid installed Roblox bundle.
2. Assign the clone a unique bundle ID.
3. Set `LSMultipleInstancesProhibited` to false in the clone.
4. Apply an ad hoc local signature to the clone.
5. Open the game URL with that exact bundle and require a new application instance.

This produced two `RobloxPlayer` processes from different temporary bundles at the same time while the official `/Applications/Roblox.app` tray process stayed running. The test confirmed distinct process IDs, per-account process tracking, and selected-instance stop behavior. It used invalid tickets, so it could not join a game or expose an account. The test processes and bundles were removed afterward.

Version 0.2.0 implements that method per account. It uses AppKit to send the launch URL so the authentication ticket does not appear in a shell command or process argument. It verifies the official Roblox signature and Team ID `2CFABCH843` before making any copy.

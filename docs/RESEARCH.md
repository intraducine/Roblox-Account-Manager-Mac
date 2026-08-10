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

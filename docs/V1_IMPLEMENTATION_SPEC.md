# Roblox Account Manager for Mac 1.0 Implementation Specification

## 1. Product goal

Version 1.0 must make this outcome reliable:

> A user can find a player visible to any saved Roblox account, identify the server, select other saved accounts, and launch every account that is expected to have access.

The app must never claim that an account can join when Roblox has not provided enough information. It must not bypass Roblox privacy or private-server access rules.

This specification assumes:

- The user owns or has permission to use every saved account.
- "Joinable players" means the union of online friends visible to the saved accounts.
- Followers and users followed are outside the initial 1.0 scope.
- The user has only a free Apple developer account.
- The app remains a native SwiftUI macOS application.
- The normal Roblox client copies remain unchanged.

Roblox lets users control who can see their current experience. The available audience can depend on age and region. A visible player is not always joinable by every account. See [Roblox Online Status and Visibility](https://en.help.roblox.com/hc/en-us/articles/39144167691284-Online-Status-and-Visibility).

## 2. Apple account constraint

A free Apple account is sufficient for local development. It is not sufficient for Developer ID distribution, notarization, the Mac App Store, or a normal trusted auto-update system. Apple states that Personal Team profiles expire after seven days and that program membership is required for distribution and notarization. See [Apple Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

### Required release approach

Version 1.0 must:

- Build a universal Intel and Apple silicon app.
- Use an ad hoc signature when no paid signing identity exists.
- Verify the final app with `codesign --verify`.
- Provide a source tag and reproducible build instructions.
- Produce an optional ZIP artifact with a SHA-256 checksum.
- Explain that a downloaded build is not notarized.
- Recommend building from source for the best local trust boundary.

Version 1.0 must not:

- Depend on Personal Team provisioning.
- Claim that the app is notarized.
- Ship an automatic updater that replaces the app with an untrusted build.
- Require iCloud, CloudKit, App Groups, or another paid capability.

WebKit, Keychain, local files, and normal HTTPS requests do not require paid Apple services for this unsandboxed Mac app.

## 3. Version 1.0 scope

### Required features

1. Selected-account Roblox website
2. Joinable Players discovery
3. Public-server verification
4. Per-account join assessment
5. Batch join into a verified public server
6. Restricted-server web fallback
7. Session health and reauthentication
8. Launch Sets
9. Recent and favorite experiences
10. Non-secret backup and restore
11. Local diagnostics
12. Reproducible free-account release build

### Explicitly excluded

- Password storage
- Captcha solving
- Automatic friend requests
- Mass account-setting changes
- Automatic background cookie refresh
- Quick Login code generation
- Local or remote account-control APIs
- AFK detection or automatic relaunch
- Process injection
- Client modification in the normal launch path
- Attempts to reveal hidden player presence
- Attempts to bypass private-server membership
- Gameplay automation

## 4. Selected-account Roblox website

### User outcome

The user can open Roblox Home, Profile, Settings, or Security as one selected saved account without affecting another account.

### Entry points

Add these actions to the selected account:

- Open Roblox Home
- Open My Profile
- Open Settings
- Open Security

The account context menu should contain the same actions under an "Open Roblox Website" submenu.

### Window design

Open a separate native window titled:

> Roblox Website as @username

The window toolbar must show:

- Account avatar
- Alias or display name
- `@username`
- Back
- Forward
- Reload
- Home
- Profile
- Settings
- Security
- Close

The account identity must remain visible while browsing. This prevents the user from changing the wrong account.

### Browser isolation

Each browser window must:

- Use `WKWebsiteDataStore.nonPersistent()`.
- Receive only the selected account's `.ROBLOSECURITY` value.
- Never share a `WKProcessPool`, cookie store, or website data store with another account window.
- Clear all web data when the window closes.
- Never log URLs that contain sensitive query values.
- Open non-Roblox links in the normal system browser after confirmation.

### Session synchronization

When the window closes:

1. Read the current `.ROBLOSECURITY` cookie.
2. Validate it with Roblox.
3. Confirm that its Roblox user ID matches the selected managed account.
4. If it matches and differs from the saved value, replace the Keychain value.
5. If no cookie remains, run a session health check.
6. If Roblox invalidated the old session, mark the account as signed out.
7. Never save a cookie that belongs to a different user ID.

### Restricted-player fallback

This browser is also the safe fallback for players whose servers cannot be verified as public.

The app should open the target player's Roblox profile as a source account that can see the player. The user can then use Roblox's own Join Experience button.

Roblox states that this button appears only when the player allows the current user to join and the current user has the required experience permissions. See [How to follow or join another player in experiences](https://en.help.roblox.com/hc/en-us/articles/203314220-How-to-follow-or-join-another-player-in-experiences).

## 5. Joinable Players

### Definitions

#### Source account

A managed account whose Roblox friends are being checked.

#### Candidate player

A Roblox user found through at least one source account's friend list.

#### Visible player

A candidate for whom Roblox provides online or in-experience information to at least one source account.

#### Verified public server

A server whose Job ID appears in Roblox's public server list for the reported Place ID.

#### Restricted or unlisted server

A server that does not appear in the complete public server search.

#### Unconfirmed server

A server that was not found before the public-server search budget ended.

#### Expected to join

A managed account that:

- Has a valid saved session.
- Is not already running.
- Can access the experience as far as the app can determine.
- Is targeting a verified public server.
- Fits within the last reported server capacity.

"Expected" is not a guarantee. Roblox can still reject the launch because of age, region, experience access, bans, a full server, or a server closing.

## 6. Discovery data sources

Roblox documents endpoints for public friend lists, online friends, friend status, and presence. Some online-friend operations use cookie authentication. See the [Roblox Connections reference](https://create.roblox.com/docs/cloud/reference/features/friends).

Legacy cookie-based Roblox APIs can change without notice. Keep all such calls behind a narrow protocol so they can be replaced without changing the UI. See [Roblox Cloud API guidance](https://create.roblox.com/docs/cloud).

### Phase 0 research requirement

Before agents build the production feature, they must test:

1. A target visible to everyone.
2. A target visible only to friends.
3. A target hidden from all tested accounts.
4. A target in a public server.
5. A target in a private server.
6. A source account that is the target's friend.
7. A loaded account that is not the target's friend.

For each case, compare:

- Anonymous Presence API response
- Presence request with the source account cookie
- Authenticated online-friends response
- Roblox website behavior for the same account
- Public server list results

### Required research decision

If an authenticated endpoint reliably returns relationship-specific presence:

- Use it for each source account.
- Record which source accounts can see each target.

If it does not:

- Limit automatic discovery to public presence.
- Label the result "Publicly visible."
- Do not claim that the app can compile friend-only presence.
- Keep friend-only joining in the selected-account website.

Agents must not use an undocumented workaround to expose hidden presence.

## 7. Discovery algorithm

### Step 1: choose source accounts

Default to all valid saved accounts.

Allow the user to limit discovery to:

- All accounts
- One group
- Selected accounts

Do not query accounts with expired sessions through authenticated endpoints.

### Step 2: load friends

For every source account:

1. Load its Roblox friend list.
2. Record the source account ID for every friend.
3. Merge duplicate players by Roblox user ID.
4. Keep all source relationships.

Example:

```swift
struct PlayerCandidate {
    let userID: Int64
    var username: String
    var displayName: String
    var avatarURL: URL?
    var visibleToAccountIDs: Set<UUID>
}
```

### Step 3: load presence

Request presence in bounded batches.

Initial values:

```swift
let presenceBatchSize = 50
let maximumConcurrentRequests = 2
let cacheLifetime: TimeInterval = 60
```

These values must be configurable.

For each player, record:

```swift
struct PlayerPresenceSnapshot {
    let userID: Int64
    let presenceType: PresenceType
    let placeID: Int64?
    let rootPlaceID: Int64?
    let universeID: Int64?
    let jobID: String?
    let locationName: String?
    let observedAt: Date
}
```

### Step 4: merge duplicates

If several source accounts see the same player:

- Show one player row.
- Show every source account that can see that player.
- Prefer the newest complete presence response.
- Record conflicting results for diagnostics.
- Do not expose cookies or raw response bodies in diagnostics.

### Step 5: verify the server

For each unique `(placeID, jobID)` pair:

1. Query Roblox's public server pages.
2. Stop when the matching Job ID is found.
3. Cache every fetched page for one minute.
4. Stop after 10 pages by default.
5. Allow the user to continue the search manually.
6. Respect HTTP 429 and `Retry-After`.

Classification:

- Found: `verifiedPublic`
- All pages exhausted: `restrictedOrUnavailable`
- Search budget ended: `unconfirmed`
- Network failed: `verificationFailed`

Absence from the first page must never mean "private."

### Step 6: calculate capacity

For a verified public server:

```swift
openSpaces = maxPlayers - playing
```

Before launch:

- Refresh the matching public-server page.
- Compare open spaces with the selected account count.
- Exclude accounts that are already running.
- Warn that capacity can change during launch.

If only two spaces remain and four accounts are selected, offer:

- Launch First 2
- Change Selection
- Cancel

Do not silently drop accounts.

## 8. Join decision tree

### Case A: verified public server

Allow any selected valid managed account to attempt the Job ID launch.

Show each account as:

- Expected to join
- Already running
- Signed out
- Server has no space for this account
- Account status unknown

Primary action:

> Join 4 Accounts

### Case B: public status unconfirmed

Do not label it private.

Offer:

- Continue Checking
- Try Selected Accounts
- Open Player Profile as @source

"Try Selected Accounts" must explain that Roblox may reject some accounts.

### Case C: server confirmed unlisted

Do not batch-launch arbitrary accounts by Job ID.

If the target is visible to a source account, offer:

> Open @target's Profile as @source

The user then uses Roblox's normal Join button.

### Case D: private server link is available

Use the existing private-server path.

For each selected account:

1. Request private-server access with that account's session.
2. Mark access as allowed or denied.
3. Launch only accounts with valid access.
4. Show denied accounts before launch.
5. Never share one account's access code with another account.

Roblox states that private-server access can depend on invitations, friend access, age, and privacy settings. Error 524 commonly means that the account lacks permission. See [Roblox Error 524 guidance](https://en.help.roblox.com/hc/en-us/articles/41933144508180-Error-Code-524-You-do-not-have-permission-to-join-this-game).

### Case E: no Job ID

Show:

> Roblox shows that this player is in an experience, but it did not provide a server that this app can target.

Offer only the account-browser fallback.

### Case F: offline or hidden

Show:

> Roblox did not provide a current experience for this player. They may be offline or may limit who can see their activity.

Do not distinguish hidden from offline unless Roblox explicitly does so.

## 9. Joinable Players interface

### Entry point

Add one toolbar action:

> Find Players

Also add a native menu command:

> View > Joinable Players

Open a separate window. Do not add another large block to the account detail screen.

### Window structure

#### Top controls

- Source: All Accounts or group
- Search
- Refresh
- Last updated time

#### Main player table

Columns:

- Player
- Visible To
- Experience
- Server
- Open Spaces

Server values:

- Public
- Public, full
- Checking
- Not confirmed
- Restricted or unavailable
- No server supplied

Do not use status pills for every row. Use text, weight, and a small system status symbol only where needed.

#### Detail area

When the user selects a player, show:

- Avatar
- Username
- Experience
- Source accounts that can see the player
- Server verification result
- Open-space count
- Managed account selection
- Per-account assessment
- One primary action

Possible primary actions:

- Join Selected Accounts
- Continue Checking
- Open Profile as @source

### Empty states

No source accounts:

> Add a Roblox account before finding players.

No online friends:

> Roblox did not return any friends in a visible experience.

All sessions expired:

> Sign in to at least one account before checking its online friends.

Rate limited:

> Roblox is limiting requests. Try again after 45 seconds.

## 10. Managed accounts already running

The app should place running managed accounts at the top of the player list.

Extend the process record so the app remembers the launch destination:

```swift
struct ActiveLaunchTargetRecord: Codable {
    let accountID: UUID
    let processIdentifier: Int32
    let placeID: Int64
    let targetKind: TargetKind
    let jobID: String?
    let privateServerReference: String?
    let launchedAt: Date
}
```

Never store:

- Authentication tickets
- Private-server access codes
- Session cookies

If the manager launched an account into a known public Job ID, other accounts can use that known target without waiting for Presence API discovery.

If the account used "Roblox chooses," the manager does not know the final Job ID. It may request presence after launch, but it must still respect the account's visibility result.

## 11. Session health

Add account states:

```swift
enum AccountHealth {
    case unchecked
    case checking
    case ready(lastChecked: Date)
    case signedOut
    case wrongAccount(actualUserID: Int64)
    case networkUnavailable
}
```

Required actions:

- Check Account
- Check Selected Accounts
- Sign In Again

Reauthentication must preserve:

- Alias
- Groups
- Notes
- Favorites
- Launch Sets
- Last-used information

A new session must replace the old Keychain value only after its Roblox user ID matches the saved account.

Do not run continuous background session checks. Check when the user asks, before sensitive web access, or immediately before launch.

## 12. Launch Sets

A Launch Set stores:

```swift
struct LaunchSet: Codable, Identifiable {
    let id: UUID
    var name: String
    var accountIDs: [UUID]
    var groupNames: [String]
    var placeID: Int64
    var experienceName: String?
    var serverStrategy: ServerStrategy
    var createdAt: Date
    var updatedAt: Date
}
```

Supported server strategies:

- Roblox chooses
- Browse before launch
- Join a player
- Private server link

Do not save a discovered public Job ID. Public servers can close.

Private server links must be treated as sensitive local data. Exclude them from normal exports unless the user explicitly chooses to include them.

## 13. Recent and favorite experiences

Store:

- Place ID
- Experience name
- Thumbnail URL
- Last launched date
- Launch count
- Favorite state

Add one native game chooser beside the Place ID field.

The user must still be able to paste a Place ID directly.

Do not depend on an experience name lookup for launching. The numeric Place ID remains the source of truth.

## 14. Backup and restore

Default exports may include:

- Account user IDs
- Usernames
- Aliases
- Groups
- Notes
- Favorites
- Recent experiences
- Launch Sets without private links

Default exports must exclude:

- `.ROBLOSECURITY`
- Authentication tickets
- Private-server access codes
- Active process IDs
- Raw network responses
- Private server links

Import must match accounts by Roblox user ID. It must never overwrite a Keychain session automatically.

## 15. Diagnostics

Add a local "Run Check" screen.

Check:

- Roblox exists in `/Applications`.
- Roblox has the expected Team ID and signature.
- Prepared copies match the installed Roblox app.
- Required directories are writable.
- Disk space is sufficient.
- Account metadata can be decoded.
- Keychain entries exist.
- Stale process records are removed safely.
- Social endpoints are reachable.
- Public server browsing is reachable.

The exportable report must redact:

- Cookies
- Tickets
- Private links
- Private access codes
- Complete Roblox launch URLs

## 16. Networking requirements

All new network code must:

- Use ephemeral `URLSessionConfiguration`.
- Disable automatic shared cookie storage.
- Set account cookies only on the exact request that needs them.
- Use HTTPS.
- Handle 401, 403, 404, 429, and 5xx separately.
- Respect `Retry-After`.
- Use exponential backoff only for safe read requests.
- Limit concurrent requests.
- Support cancellation when the discovery window closes.
- Cache social and presence data only in memory.
- Clear the cache when accounts are removed.

A partial failure must not discard successful results from other accounts.

## 17. Proposed source layout

### New core files

- `Sources/RAMacCore/RobloxSocialAPIClient.swift`
- `Sources/RAMacCore/PlayerDiscoveryModels.swift`
- `Sources/RAMacCore/PlayerDiscoveryService.swift`
- `Sources/RAMacCore/JoinAssessmentService.swift`
- `Sources/RAMacCore/AccountHealthService.swift`
- `Sources/RAMacCore/LaunchSet.swift`
- `Sources/RAMacCore/LaunchSetRepository.swift`
- `Sources/RAMacCore/ExperienceLibrary.swift`
- `Sources/RAMacCore/MetadataArchive.swift`
- `Sources/RAMacCore/DiagnosticReport.swift`

### New app files

- `Sources/RAMacApp/JoinablePlayersView.swift`
- `Sources/RAMacApp/JoinablePlayerDetailView.swift`
- `Sources/RAMacApp/AccountJoinMatrixView.swift`
- `Sources/RAMacApp/AccountWebView.swift`
- `Sources/RAMacApp/AccountWebSessionModel.swift`
- `Sources/RAMacApp/LaunchSetsView.swift`
- `Sources/RAMacApp/ExperienceChooserView.swift`
- `Sources/RAMacApp/AccountHealthView.swift`
- `Sources/RAMacApp/DiagnosticsView.swift`

### Existing files to extend

- `AccountStore.swift`
- `ContentView.swift`
- `AccountDetailView.swift`
- `RobloxAPIClient.swift`
- `RobloxLauncher.swift`
- `AccountRepository.swift`
- `RAMacApp.swift`
- `README.md`
- `docs/RESEARCH.md`

## 18. Protocol boundaries

Use protocols so tests do not contact Roblox:

```swift
protocol RobloxSocialProviding: Sendable {
    func friends(of userID: Int64) async throws -> [RobloxSocialUser]
    func onlineFriends(
        of userID: Int64,
        session: String
    ) async throws -> [RobloxVisibleFriend]

    func presences(
        for userIDs: [Int64],
        session: String?
    ) async throws -> [RobloxUserPresence]
}

protocol PlayerDiscovering: Sendable {
    func discover(
        sourceAccounts: [ManagedAccount]
    ) async -> PlayerDiscoveryResult
}

protocol JoinAssessing: Sendable {
    func assess(
        target: PlayerJoinTarget,
        accounts: [ManagedAccount]
    ) async -> [AccountJoinAssessment]
}
```

The UI must depend on these protocols, not concrete network clients.

## 19. Testing requirements

### Unit tests

Cover:

- Friend union and user-ID deduplication
- Multiple source accounts for one player
- Conflicting presence results
- Presence batching
- Cache expiration
- Public-server pagination
- Server found on a later page
- Search budget ending before a match
- Full server
- Partial capacity
- Offline player
- Hidden or missing presence
- Invalid source session
- HTTP 429 handling
- Partial account failures
- Private-server access per account
- Browser session belongs to correct account
- Browser session belongs to wrong account
- Cookie rotation
- Web logout
- Export contains no secrets
- Private links excluded by default
- Process records contain no launch tickets

### Integration tests with mocked HTTP

Simulate:

- Three loaded accounts
- Overlapping friend lists
- One target visible to two accounts
- One public server
- One unlisted server
- One expired account
- One rate-limited source account

The result must retain valid data from the other accounts.

### Live manual test matrix

Use test accounts owned by the developer.

1. Public target with joins set to everyone
2. Friend-only target
3. Hidden target
4. Public server with enough spaces
5. Public server with too few spaces
6. Private server with one allowed account
7. Private server with one denied account
8. Target changes servers during refresh
9. Source account signs out
10. Roblox updates between launches
11. Two managed accounts launch together
12. Stop All leaves zero managed Roblox processes

Record only account IDs created for testing. Do not commit cookies, usernames, private links, or launch tickets.

## 20. Implementation phases

### Phase 0: endpoint research

- Complete the relationship-specific presence test.
- Record exact status codes and response fields.
- Decide whether authenticated friend-only discovery is reliable.
- Do not build UI against assumed behavior.

### Phase 1: social models and mocked discovery

- Add protocols and models.
- Implement union and deduplication.
- Add deterministic tests.
- Do not add production network calls yet.

### Phase 2: production discovery client

- Implement friend and presence calls.
- Add request limits, caching, and cancellation.
- Add public-server verification.
- Add partial-failure handling.

### Phase 3: Joinable Players UI

- Add the window, table, detail view, and join matrix.
- Use existing account selection behavior.
- Add public batch join.
- Add restricted-server fallback.

### Phase 4: selected-account website

- Add isolated WebKit sessions.
- Add identity toolbar.
- Add cookie validation and synchronization.
- Connect restricted targets to profile fallback.

### Phase 5: health, presets, and experience library

- Add account health.
- Add Launch Sets.
- Add recent and favorite experiences.
- Add migration tests.

### Phase 6: backup and diagnostics

- Add redacted export and import.
- Add local diagnostics.
- Verify no secret leakage.

### Phase 7: release hardening

- Run all automated tests.
- Run the live test matrix.
- Build both architectures.
- Create the universal app.
- Apply ad hoc signing.
- Verify the signature.
- Create the source tag, ZIP, and checksum.
- Update README with the free-account distribution limit.

## 21. Acceptance criteria

Version 1.0 is complete only when:

- The app combines duplicate friends from several managed accounts.
- Every discovered player shows which managed accounts can see them.
- The app verifies a server as public before presenting a confident bulk-join action.
- Any valid selected account can attempt to join a verified public Job ID.
- Capacity is checked before batch launch.
- Each account gets a separate success or failure result.
- Restricted servers use the Roblox profile fallback.
- Private links are checked separately for each account.
- Hidden presence is never exposed or guessed.
- The selected-account website never shares cookies across accounts.
- A changed web cookie is saved only after same-user validation.
- Reauthentication preserves account metadata.
- Exports contain no account sessions.
- Diagnostics contain no secrets.
- The normal Roblox copies remain unchanged.
- Stop All closes every managed instance.
- The app builds with no paid Apple services.
- The release documentation does not claim notarization.
- The complete automated suite passes.
- The live public, private, full, hidden, and expired-session cases are recorded.

### Primary success measure

A user with three saved accounts can:

1. Refresh Joinable Players.
2. Select a visible player in a verified public server.
3. Select two other accounts.
4. Launch both accounts.
5. See a clear result for each account.

The full flow should take less than 30 seconds after cached data is available.

### Guardrails

- Zero session secrets in logs or exports
- Zero cross-account browser-cookie leaks
- Zero hidden-presence bypasses
- Zero automatic launches into unverified restricted servers
- Zero silent account drops from a batch
- Zero modified Roblox files in the normal launch method

## 22. Interface quality requirements

The interface must use native macOS windows, tables, forms, and controls. It must avoid decorative cards, status-pill clutter, gradients, glow, hidden entrance animation, fake app windows, and clipped information.

Every screen must provide:

- One clear primary action
- A visible account identity when an action uses one account
- Plain-language loading and error states
- Full keyboard access
- VoiceOver labels
- Non-color status indicators
- Readable contrast in light and dark system appearances
- A safe exit that preserves completed work

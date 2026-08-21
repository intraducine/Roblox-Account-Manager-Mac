import Foundation

public struct JoinAssessmentService: Sendable {
    public init() {}

    public func assess(
        target: PlayerJoinTarget,
        accounts: [ManagedAccount],
        health: [UUID: AccountHealth],
        runningAccountIDs: Set<UUID>
    ) async -> [AccountJoinAssessment] {
        var spaces: Int?
        if case .verifiedPublic(let server) = target.verification {
            spaces = server.openSpaces
        }
        var expectedCount = 0
        return accounts.map { account in
            if runningAccountIDs.contains(account.id) {
                return AccountJoinAssessment(
                    accountID: account.id,
                    state: .alreadyRunning,
                    explanation: "This account already has a managed Roblox client open."
                )
            }
            switch health[account.id] ?? .unchecked {
            case .signedOut, .wrongAccount:
                return AccountJoinAssessment(
                    accountID: account.id,
                    state: .signedOut,
                    explanation: "Sign in again before launching this account."
                )
            case .networkUnavailable, .unchecked, .checking:
                return AccountJoinAssessment(
                    accountID: account.id,
                    state: .statusUnknown,
                    explanation: "Check this account before launching it."
                )
            case .ready:
                guard target.verification.allowsDirectJoinAttempt else {
                    return AccountJoinAssessment(
                        accountID: account.id,
                        state: .statusUnknown,
                        explanation: "Roblox did not provide a server that this app can target."
                    )
                }
                if case .friendTarget = target.verification {
                    return AccountJoinAssessment(
                        accountID: account.id,
                        state: .expectedToJoin,
                        explanation: "The manager can send this account to the reported server. Roblox will decide access and space."
                    )
                }
                if let spaces, expectedCount >= spaces {
                    return AccountJoinAssessment(
                        accountID: account.id,
                        state: .serverHasNoSpace,
                        explanation: "The last server update did not show room for this account."
                    )
                }
                expectedCount += 1
                return AccountJoinAssessment(
                    accountID: account.id,
                    state: .expectedToJoin,
                    explanation: "Roblox may still reject the launch if access or capacity changes."
                )
            }
        }
    }
}

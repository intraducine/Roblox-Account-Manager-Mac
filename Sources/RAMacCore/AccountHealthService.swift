import Foundation

public protocol AccountHealthChecking: Sendable {
    func check(_ account: ManagedAccount) async -> AccountHealth
}

public struct AccountHealthService: AccountHealthChecking, Sendable {
    private let vault: any SecretVault
    private let api: any RobloxAPIProviding

    public init(vault: any SecretVault, api: any RobloxAPIProviding) {
        self.vault = vault
        self.api = api
    }

    public func check(_ account: ManagedAccount) async -> AccountHealth {
        do {
            guard let session = try vault.read(for: account.id), !session.isEmpty else { return .signedOut }
            let user = try await api.authenticatedUser(cookie: session)
            guard user.id == account.userID else { return .wrongAccount(actualUserID: user.id) }
            return .ready(lastChecked: Date())
        } catch RobloxAPIError.invalidSession {
            return .signedOut
        } catch {
            return .networkUnavailable
        }
    }
}

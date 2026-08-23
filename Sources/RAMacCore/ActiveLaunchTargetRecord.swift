import Foundation

public enum ActiveLaunchTargetKind: String, Codable, Equatable, Sendable {
    case automatic
    case publicJob
    case verifiedPublicJob
    case privateServer
}

public struct ActiveLaunchTargetRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { accountID }
    public let accountID: UUID
    public let processIdentifier: Int32
    public let placeID: Int64
    public let targetKind: ActiveLaunchTargetKind
    public let jobID: String?
    public let privateServerReference: String?
    public let launchedAt: Date

    public init(
        accountID: UUID,
        processIdentifier: Int32,
        placeID: Int64,
        targetKind: ActiveLaunchTargetKind,
        jobID: String? = nil,
        privateServerReference: String? = nil,
        launchedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.processIdentifier = processIdentifier
        self.placeID = placeID
        self.targetKind = targetKind
        self.jobID = jobID
        self.privateServerReference = privateServerReference
        self.launchedAt = launchedAt
    }
}

public typealias ActiveLaunchTargetRepository = JSONFileRepository<ActiveLaunchTargetRecord>

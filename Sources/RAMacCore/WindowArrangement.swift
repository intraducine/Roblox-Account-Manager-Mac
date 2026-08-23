import Foundation

public enum WindowPlacementRegion: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case wholeScreen
    case right
    case bottomLeft
    case bottom
    case bottomRight
    case fullScreen

    public var id: String { rawValue }
}

public struct WindowLayoutAssignment: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let displayID: String
    public let displayName: String
    public let displayPixelWidth: Int
    public let displayPixelHeight: Int
    public let region: WindowPlacementRegion

    public init(
        accountID: UUID,
        displayID: String,
        displayName: String,
        displayPixelWidth: Int,
        displayPixelHeight: Int,
        region: WindowPlacementRegion
    ) {
        self.accountID = accountID
        self.displayID = displayID
        self.displayName = displayName
        self.displayPixelWidth = displayPixelWidth
        self.displayPixelHeight = displayPixelHeight
        self.region = region
    }
}

public enum WindowArrangementPolicy: Codable, Equatable, Sendable {
    case savedPlacements
    case custom([WindowLayoutAssignment])
    case unchanged

    private enum CodingKeys: String, CodingKey { case kind, placements }
    private enum Kind: String, Codable { case savedPlacements, custom, unchanged }

    public var usesSavedPlacements: Bool {
        if case .savedPlacements = self { return true }
        return false
    }

    public func effectiveAssignments(
        savedAssignments: [WindowLayoutAssignment],
        accountIDs: Set<UUID>
    ) -> [WindowLayoutAssignment] {
        let source: [WindowLayoutAssignment]
        switch self {
        case .savedPlacements:
            source = savedAssignments
        case .custom(let assignments):
            source = assignments
        case .unchanged:
            source = []
        }
        return source
            .filter { accountIDs.contains($0.accountID) }
            .sorted { $0.accountID.uuidString < $1.accountID.uuidString }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .savedPlacements:
            self = .savedPlacements
        case .custom:
            self = .custom(try values.decodeIfPresent([WindowLayoutAssignment].self, forKey: .placements) ?? [])
        case .unchanged:
            self = .unchanged
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .savedPlacements:
            try values.encode(Kind.savedPlacements, forKey: .kind)
        case .custom(let placements):
            try values.encode(Kind.custom, forKey: .kind)
            try values.encode(placements, forKey: .placements)
        case .unchanged:
            try values.encode(Kind.unchanged, forKey: .kind)
        }
    }
}

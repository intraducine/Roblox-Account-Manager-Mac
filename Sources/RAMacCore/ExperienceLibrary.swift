import Foundation

public struct ExperienceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64 { placeID }
    public let placeID: Int64
    public var experienceName: String?
    public var thumbnailURLString: String?
    public var lastLaunchedAt: Date
    public var launchCount: Int
    public var isFavorite: Bool

    public init(
        placeID: Int64,
        experienceName: String? = nil,
        thumbnailURLString: String? = nil,
        lastLaunchedAt: Date = Date(),
        launchCount: Int = 0,
        isFavorite: Bool = false
    ) {
        self.placeID = placeID
        self.experienceName = experienceName
        self.thumbnailURLString = thumbnailURLString
        self.lastLaunchedAt = lastLaunchedAt
        self.launchCount = launchCount
        self.isFavorite = isFavorite
    }

    public var thumbnailURL: URL? {
        guard let url = thumbnailURLString.flatMap(URL.init(string:)),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "rbxcdn.com" || host.hasSuffix(".rbxcdn.com") else { return nil }
        return url
    }
}

public typealias ExperienceLibraryRepository = JSONFileRepository<ExperienceRecord>

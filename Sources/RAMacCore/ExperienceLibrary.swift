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

    public var thumbnailURL: URL? { thumbnailURLString.flatMap(URL.init(string:)) }
}

public final class ExperienceLibraryRepository: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(dataDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = (dataDirectory ?? AccountRepository.defaultDataDirectory(fileManager: fileManager))
            .appendingPathComponent("Experiences.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [ExperienceRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([ExperienceRecord].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ records: [ExperienceRecord]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

public struct ExperienceLibrary: Sendable {
    public init() {}

    public func recordingLaunch(
        placeID: Int64,
        name: String? = nil,
        thumbnailURLString: String? = nil,
        in records: [ExperienceRecord],
        at date: Date = Date()
    ) -> [ExperienceRecord] {
        var result = records
        if let index = result.firstIndex(where: { $0.placeID == placeID }) {
            result[index].lastLaunchedAt = date
            result[index].launchCount += 1
            if let name, !name.isEmpty { result[index].experienceName = name }
            if let thumbnailURLString { result[index].thumbnailURLString = thumbnailURLString }
        } else {
            result.append(ExperienceRecord(
                placeID: placeID,
                experienceName: name,
                thumbnailURLString: thumbnailURLString,
                lastLaunchedAt: date,
                launchCount: 1
            ))
        }
        return result.sorted { $0.lastLaunchedAt > $1.lastLaunchedAt }
    }
}

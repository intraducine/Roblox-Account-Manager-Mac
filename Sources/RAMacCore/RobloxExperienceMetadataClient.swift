import Foundation

public struct ExperienceMetadata: Equatable, Sendable {
    public let placeID: Int64
    public let universeID: Int64
    public let name: String
    public let thumbnailURLString: String?

    public init(placeID: Int64, universeID: Int64, name: String, thumbnailURLString: String?) {
        self.placeID = placeID
        self.universeID = universeID
        self.name = name
        self.thumbnailURLString = thumbnailURLString
    }
}

public protocol ExperienceMetadataProviding: Sendable {
    func metadata(placeID: Int64) async throws -> ExperienceMetadata
}

public struct RobloxExperienceMetadataClient: ExperienceMetadataProviding, Sendable {
    private struct UniverseResponse: Decodable {
        let universeId: Int64
    }

    private struct GamesResponse: Decodable {
        let data: [Game]
    }

    private struct Game: Decodable {
        let id: Int64
        let name: String
    }

    private struct ThumbnailResponse: Decodable {
        let data: [Thumbnail]
    }

    private struct Thumbnail: Decodable {
        let targetId: Int64
        let state: String
        let imageUrl: String?
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    public func metadata(placeID: Int64) async throws -> ExperienceMetadata {
        guard placeID > 0 else { throw RobloxLaunchError.invalidPlaceID }

        let universeURL = URL(string: "https://apis.roblox.com/universes/v1/places/\(placeID)/universe")!
        let universe: UniverseResponse = try await load(universeURL)

        async let game = game(universeID: universe.universeId)
        async let thumbnail = thumbnail(universeID: universe.universeId)
        let (resolvedGame, resolvedThumbnail) = try await (game, thumbnail)

        return ExperienceMetadata(
            placeID: placeID,
            universeID: universe.universeId,
            name: resolvedGame.name,
            thumbnailURLString: resolvedThumbnail
        )
    }

    private func game(universeID: Int64) async throws -> Game {
        var components = URLComponents(string: "https://games.roblox.com/v1/games")!
        components.queryItems = [URLQueryItem(name: "universeIds", value: String(universeID))]
        let response: GamesResponse = try await load(components.url!)
        guard let game = response.data.first(where: { $0.id == universeID }),
              !game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RobloxAPIError.invalidResponse
        }
        return game
    }

    private func thumbnail(universeID: Int64) async throws -> String? {
        var components = URLComponents(string: "https://thumbnails.roblox.com/v1/games/icons")!
        components.queryItems = [
            URLQueryItem(name: "universeIds", value: String(universeID)),
            URLQueryItem(name: "returnPolicy", value: "PlaceHolder"),
            URLQueryItem(name: "size", value: "150x150"),
            URLQueryItem(name: "format", value: "Png"),
            URLQueryItem(name: "isCircular", value: "false")
        ]
        let response: ThumbnailResponse = try await load(components.url!)
        guard let thumbnail = response.data.first(where: { $0.targetId == universeID }),
              thumbnail.state == "Completed" else { return nil }
        return thumbnail.imageUrl
    }

    private func load<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Roblox Account Manager for Mac/1.0.2", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RobloxAPIError.invalidResponse }
        guard http.statusCode == 200 else {
            throw RobloxAPIError.server(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw RobloxAPIError.invalidResponse
        }
    }
}

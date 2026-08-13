import Foundation

public enum RobloxGameReference {
    public static func placeID(from value: String) -> Int64? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let placeID = Int64(clean), placeID > 0 { return placeID }

        let candidate = clean.contains("://") ? clean : "https://\(clean)"
        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              host == "roblox.com" || host.hasSuffix(".roblox.com") else { return nil }

        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              parts[0].lowercased() == "games",
              let placeID = Int64(parts[1]),
              placeID > 0 else { return nil }
        return placeID
    }
}

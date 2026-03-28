import Foundation

/// Result from a TheGamesDB search.
struct ScraperResult: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let releaseDate: String
    let publisher: String
    let developer: String
    let description: String
    let players: Int
    let genres: [String]
    let boxArtFrontURL: String?
    let boxArtBackURL: String?
    let platform: String
    let region: String
}

/// Client for TheGamesDB API v2.
/// API docs: https://api.thegamesdb.net/
final class TheGamesDBClient {
    static let shared = TheGamesDBClient()

    private let baseURL = "https://api.thegamesdb.net/v1"
    // Public API key for hakchi2-ce compatibility
    private let apiKey = "1e821bf1bab6970d5dd3c84e507cbf21fada0f9a9cb91f27ab5ba45e11291ad0"

    private let session: URLSession
    private var platformMap: [String: Int] = [
        "NES": 7,
        "SNES": 6,
        "Genesis": 18,
        "GB": 4,
        "GBC": 41,
        "GBA": 5,
        "TG16": 34,
        "SMS": 35,
        "N64": 3,
        "PS1": 10,
        "Atari2600": 22,
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Search for games by name.
    func searchGames(name: String, platform: String? = nil) async throws -> [ScraperResult] {
        var components = URLComponents(string: "\(baseURL)/Games/ByGameName")!
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "fields", value: "players,publishers,genres,overview,boxart"),
            URLQueryItem(name: "include", value: "boxart,platform"),
        ]

        if let platform = platform, let platformID = platformMap[platform] {
            queryItems.append(URLQueryItem(name: "filter[platform]", value: String(platformID)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw HakchiError.invalidData("Invalid search URL")
        }

        let (data, _) = try await session.data(from: url)
        return try parseSearchResponse(data)
    }

    /// Get a game by its TheGamesDB ID.
    func getGame(id: Int) async throws -> ScraperResult? {
        var components = URLComponents(string: "\(baseURL)/Games/ByGameID")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "fields", value: "players,publishers,genres,overview,boxart"),
            URLQueryItem(name: "include", value: "boxart,platform"),
        ]

        guard let url = components.url else { return nil }

        let (data, _) = try await session.data(from: url)
        return try parseSearchResponse(data).first
    }

    /// Download box art image data.
    func downloadBoxArt(url: String) async throws -> Data {
        guard let imageURL = URL(string: url) else {
            throw HakchiError.invalidData("Invalid box art URL")
        }
        let (data, _) = try await session.data(from: imageURL)
        return data
    }

    // MARK: - Parsing

    private func parseSearchResponse(_ data: Data) throws -> [ScraperResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let games = dataObj["games"] as? [[String: Any]] else {
            return []
        }

        // Parse boxart base URL and images
        let includeObj = json["include"] as? [String: Any]
        let boxartObj = includeObj?["boxart"] as? [String: Any]
        let boxartBaseURL = (boxartObj?["base_url"] as? [String: String])?["original"] ?? ""
        let boxartData = boxartObj?["data"] as? [String: [[String: Any]]] ?? [:]

        var results: [ScraperResult] = []

        for game in games {
            let gameID = game["id"] as? Int ?? 0
            let gameName = game["game_title"] as? String ?? ""
            let releaseDate = game["release_date"] as? String ?? ""
            let overview = game["overview"] as? String ?? ""
            let players = game["players"] as? Int ?? 1

            let publishers = game["publishers"] as? [Int] ?? []
            let publisherName = publishers.isEmpty ? "" : "Publisher"

            let genreIDs = game["genres"] as? [Int] ?? []
            let genres = genreIDs.map { "Genre \($0)" }

            let platformID = game["platform"] as? Int ?? 0
            let platform = platformMap.first { $0.value == platformID }?.key ?? ""

            // Find box art
            let artworks = boxartData[String(gameID)] ?? []
            let frontArt = artworks.first { ($0["side"] as? String) == "front" }
            let backArt = artworks.first { ($0["side"] as? String) == "back" }
            let frontURL = (frontArt?["filename"] as? String).map { boxartBaseURL + $0 }
            let backURL = (backArt?["filename"] as? String).map { boxartBaseURL + $0 }

            results.append(ScraperResult(
                id: gameID,
                name: gameName,
                releaseDate: releaseDate,
                publisher: publisherName,
                developer: "",
                description: overview,
                players: players,
                genres: genres,
                boxArtFrontURL: frontURL,
                boxArtBackURL: backURL,
                platform: platform,
                region: ""
            ))
        }

        return results
    }
}

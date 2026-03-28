import Foundation

final class GameDatabase {
    static let shared = GameDatabase()

    private var entries: [String: GameMetadata] = [:]
    private var isLoaded = false

    private init() {
        loadDatabase()
    }

    func lookup(crc32: String) -> GameMetadata? {
        return entries[crc32.uppercased()]
    }

    func lookup(crc32: UInt32) -> GameMetadata? {
        let hex = CRC32.hexString(for: crc32)
        return lookup(crc32: hex)
    }

    func searchByName(_ query: String) -> [GameMetadata] {
        let lowered = query.lowercased()
        return entries.values.filter {
            $0.name.lowercased().contains(lowered)
        }
    }

    private func loadDatabase() {
        guard !isLoaded else { return }

        // Try loading from bundle resource
        if let url = Bundle.main.url(forResource: "game_db", withExtension: "json") {
            loadFromURL(url)
            return
        }

        // Try loading from Resources directory
        let resourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("game_db.json")

        if FileManager.default.fileExists(atPath: resourcePath.path) {
            loadFromURL(resourcePath)
            return
        }

        // Load built-in minimal database
        loadBuiltInDatabase()
    }

    private func loadFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: GameMetadata].self, from: data)
            // Normalize all keys to uppercase for consistent CRC32 lookups
            entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key.uppercased(), $0.value) })
            isLoaded = true
            HakchiLogger.games.info("Loaded game database: \(self.entries.count) entries")
        } catch {
            HakchiLogger.games.error("Failed to load game database: \(error.localizedDescription)")
            loadBuiltInDatabase()
        }
    }

    private func loadBuiltInDatabase() {
        // Built-in entries for common games
        let builtIn: [(String, GameMetadata)] = [
            ("3FE272FB", GameMetadata(name: "Super Mario Bros.", publisher: "Nintendo", releaseDate: "1985", players: 2, crc32: "3FE272FB", system: "NES")),
            ("0B742B3A", GameMetadata(name: "The Legend of Zelda", publisher: "Nintendo", releaseDate: "1986", players: 1, crc32: "0B742B3A", system: "NES")),
            ("A2F461F1", GameMetadata(name: "Super Mario Bros. 3", publisher: "Nintendo", releaseDate: "1988", players: 2, crc32: "A2F461F1", system: "NES")),
            ("B2103D04", GameMetadata(name: "Super Mario World", publisher: "Nintendo", releaseDate: "1990", players: 2, crc32: "B2103D04", system: "SNES")),
            ("3421B9FF", GameMetadata(name: "The Legend of Zelda: A Link to the Past", publisher: "Nintendo", releaseDate: "1991", players: 1, crc32: "3421B9FF", system: "SNES")),
            ("1B4B4F6E", GameMetadata(name: "Super Metroid", publisher: "Nintendo", releaseDate: "1994", players: 1, crc32: "1B4B4F6E", system: "SNES")),
            ("CFB0B22A", GameMetadata(name: "Super Mario Kart", publisher: "Nintendo", releaseDate: "1992", players: 2, crc32: "CFB0B22A", system: "SNES")),
            ("A3C1C7CC", GameMetadata(name: "Donkey Kong Country", publisher: "Rare", releaseDate: "1994", players: 2, crc32: "A3C1C7CC", system: "SNES")),
            ("B19ED489", GameMetadata(name: "Chrono Trigger", publisher: "Square", releaseDate: "1995", players: 1, crc32: "B19ED489", system: "SNES")),
            ("D0B68B1D", GameMetadata(name: "Final Fantasy VI", publisher: "Square", releaseDate: "1994", players: 1, crc32: "D0B68B1D", system: "SNES")),
            ("42F14E99", GameMetadata(name: "Street Fighter II Turbo", publisher: "Capcom", releaseDate: "1993", players: 2, crc32: "42F14E99", system: "SNES")),
            ("DDBEC727", GameMetadata(name: "Mega Man X", publisher: "Capcom", releaseDate: "1993", players: 1, crc32: "DDBEC727", system: "SNES")),
            ("3F200263", GameMetadata(name: "Metroid", publisher: "Nintendo", releaseDate: "1986", players: 1, crc32: "3F200263", system: "NES")),
            ("1D03A5DE", GameMetadata(name: "Mega Man 2", publisher: "Capcom", releaseDate: "1988", players: 1, crc32: "1D03A5DE", system: "NES")),
            ("0CCBF23C", GameMetadata(name: "Castlevania", publisher: "Konami", releaseDate: "1986", players: 1, crc32: "0CCBF23C", system: "NES")),
            ("3A3C9B28", GameMetadata(name: "Contra", publisher: "Konami", releaseDate: "1987", players: 2, crc32: "3A3C9B28", system: "NES")),
            ("52449508", GameMetadata(name: "Sonic the Hedgehog", publisher: "Sega", releaseDate: "1991", players: 1, crc32: "52449508", system: "Genesis")),
            ("6985B183", GameMetadata(name: "Streets of Rage 2", publisher: "Sega", releaseDate: "1992", players: 2, crc32: "6985B183", system: "Genesis")),
        ]

        for (crc, meta) in builtIn {
            entries[crc] = meta
        }
        isLoaded = true
        HakchiLogger.games.info("Loaded built-in game database: \(self.entries.count) entries")
    }
}

import Foundation

/// Export games as portable collections for backup or USB drive usage.
final class GameExporter {
    static let shared = GameExporter()

    private init() {}

    /// Export selected games to a directory (for USB drive or backup).
    func exportGames(
        games: [Game],
        to destination: URL,
        includeCovers: Bool = true,
        progress: @escaping (Double, String) -> Void
    ) throws {
        let fm = FileManager.default
        let gamesDir = destination.appendingPathComponent("hakchi", isDirectory: true)
            .appendingPathComponent("games", isDirectory: true)
        try fm.createDirectory(at: gamesDir, withIntermediateDirectories: true)

        let total = Double(games.count)

        for (index, game) in games.enumerated() {
            let gameCode = "CLV-Z-\(game.id.uuidString.prefix(5).uppercased())"
            let gameDir = gamesDir.appendingPathComponent(gameCode, isDirectory: true)
            try fm.createDirectory(at: gameDir, withIntermediateDirectories: true)

            progress(Double(index) / total, "Exporting \(game.name)...")

            // Copy ROM
            let romURL = URL(fileURLWithPath: game.romPath)
            let destROM = gameDir.appendingPathComponent(romURL.lastPathComponent)
            if fm.fileExists(atPath: destROM.path) {
                try fm.removeItem(at: destROM)
            }
            try fm.copyItem(at: romURL, to: destROM)

            // Generate .desktop file
            let desktopContent = generateDesktopFile(for: game, code: gameCode)
            try desktopContent.write(to: gameDir.appendingPathComponent("\(gameCode).desktop"),
                                      atomically: true, encoding: .utf8)

            // Copy cover art
            if includeCovers, let coverPath = game.coverArtPath,
               fm.fileExists(atPath: coverPath) {
                let coverDest = gameDir.appendingPathComponent("\(gameCode).png")
                try? fm.copyItem(at: URL(fileURLWithPath: coverPath), to: coverDest)
            }
        }

        // Write metadata
        let metadata: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "gameCount": games.count,
            "version": "1.0"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try metadataData.write(to: destination.appendingPathComponent("hakchi").appendingPathComponent("export_info.json"))

        progress(1.0, "Exported \(games.count) games")
        HakchiLogger.games.info("Exported \(games.count) games to \(destination.path)")
    }

    /// Import games from an exported collection.
    func importGames(from source: URL, gameManager: GameManager) throws -> [Game] {
        let fm = FileManager.default
        let gamesDir = source.appendingPathComponent("hakchi").appendingPathComponent("games")

        guard fm.fileExists(atPath: gamesDir.path) else {
            throw HakchiError.invalidData("No games found in export at \(source.path)")
        }

        var importedGames: [Game] = []
        let contents = try fm.contentsOfDirectory(at: gamesDir, includingPropertiesForKeys: nil)

        for gameDir in contents where gameDir.hasDirectoryPath {
            let files = try fm.contentsOfDirectory(at: gameDir, includingPropertiesForKeys: nil)
            let romFiles = files.filter { ROMFile.isSupportedExtension($0.pathExtension) }

            for romURL in romFiles {
                if let game = gameManager.addGame(from: romURL) {
                    importedGames.append(game)
                }
            }
        }

        return importedGames
    }

    private func generateDesktopFile(for game: Game, code: String) -> String {
        let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
        let exec = CoreManager.shared.execLine(coreID: game.assignedCore, game: game, gameCode: code)

        return """
        [Desktop Entry]
        Type=Application
        Exec=\(exec)
        Path=/var/lib/clover/profiles/0/\(code)
        Name=\(game.name)
        Icon=/usr/share/games/\(code)/\(code).png
        SortPriority=\(game.sortName)
        Publisher=\(game.publisher)
        ReleaseDate=\(game.releaseDate)
        Players=\(game.players)
        SaveCount=0
        """
    }
}

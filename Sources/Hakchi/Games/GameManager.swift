import Foundation

final class GameManager {
    private let database = GameDatabase.shared

    func addGame(from url: URL) -> Game? {
        // If it's an archive, extract and add all ROMs inside
        if ArchiveExtractor.isArchive(url) {
            return addGameFromArchive(url)
        }
        return addSingleGame(from: url)
    }

    func addGames(from url: URL) -> [Game] {
        if ArchiveExtractor.isArchive(url) {
            return addGamesFromArchive(url)
        }
        if let game = addSingleGame(from: url) {
            return [game]
        }
        return []
    }

    private func addSingleGame(from url: URL) -> Game? {
        do {
            let rom = try ROMFile(url: url)
            let metadata = database.lookup(crc32: rom.crc32)
            let storedURL = try FileUtils.copyROM(from: url, gameName: metadata?.name ?? rom.filename)

            var game = rom.toGame(metadata: metadata)
            game = Game(
                id: game.id,
                name: game.name,
                sortName: game.sortName,
                publisher: game.publisher,
                releaseDate: game.releaseDate,
                players: game.players,
                romPath: storedURL.path,
                romSize: game.romSize,
                romCRC32: game.romCRC32,
                coverArtPath: game.coverArtPath,
                consoleType: game.consoleType,
                isSelected: true,
                folder: game.folder
            )

            HakchiLogger.games.info("Added game: \(game.name) (CRC: \(game.romCRC32))")
            return game
        } catch {
            HakchiLogger.games.error("Failed to add game from \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private func addGameFromArchive(_ url: URL) -> Game? {
        return addGamesFromArchive(url).first
    }

    private func addGamesFromArchive(_ url: URL) -> [Game] {
        do {
            let romURLs = try ArchiveExtractor.extractROMs(from: url)
            defer {
                // Clean up temp extraction directory
                if let first = romURLs.first {
                    var dir = first.deletingLastPathComponent()
                    // Walk up to the temp extraction root
                    while dir.lastPathComponent != "tmp" && dir.path.contains("hakchi_extract_") {
                        let parent = dir.deletingLastPathComponent()
                        if parent.path.contains("hakchi_extract_") {
                            dir = parent
                        } else {
                            break
                        }
                    }
                    ArchiveExtractor.cleanup(dir)
                }
            }

            var games: [Game] = []
            for romURL in romURLs {
                if let game = addSingleGame(from: romURL) {
                    games.append(game)
                }
            }
            HakchiLogger.games.info("Added \(games.count) games from archive: \(url.lastPathComponent)")
            return games
        } catch {
            HakchiLogger.games.error("Failed to extract archive \(url.path): \(error.localizedDescription)")
            return []
        }
    }

    func removeGame(_ game: Game) {
        let gameDir = URL(fileURLWithPath: game.romPath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: gameDir)
        HakchiLogger.games.info("Removed game: \(game.name)")
    }

    func loadSavedGames() -> [Game] {
        let file = FileUtils.gamesFile
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }

        do {
            let data = try Data(contentsOf: file)
            let games = try JSONDecoder().decode([Game].self, from: data)
            HakchiLogger.games.info("Loaded \(games.count) saved games")
            return games
        } catch {
            HakchiLogger.games.error("Failed to load saved games: \(error.localizedDescription)")
            return []
        }
    }

    func saveGames(_ games: [Game]) {
        FileUtils.ensureDirectoriesExist()
        do {
            let data = try JSONEncoder().encode(games)
            try data.write(to: FileUtils.gamesFile)
            HakchiLogger.games.info("Saved \(games.count) games")
        } catch {
            HakchiLogger.games.error("Failed to save games: \(error.localizedDescription)")
        }
    }

    func syncToConsole(
        games: [Game],
        consoleType: ConsoleType,
        shell: ShellInterface? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        let ownedShell: ShellInterface
        let shouldDisconnect: Bool

        if let shell = shell {
            ownedShell = shell
            shouldDisconnect = false
        } else {
            ownedShell = try await SSHShell()
            shouldDisconnect = true
        }

        defer { if shouldDisconnect { ownedShell.disconnect() } }

        let basePath = consoleType.gamesPath
        _ = try await ownedShell.executeCommand("mkdir -p \(basePath)")

        let totalOps = Double(games.count)

        for (index, game) in games.enumerated() {
            let gameCode = "CLV-Z-\(game.id.uuidString.prefix(5).uppercased())"
            let gamePath = "\(basePath)/\(gameCode)"

            progress(Double(index) / totalOps, "Uploading \(game.name)...")

            // Create game directory
            _ = try await ownedShell.executeCommand("mkdir -p \(gamePath)")

            // Upload ROM
            let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
            try await ownedShell.uploadFile(
                localPath: game.romPath,
                remotePath: "\(gamePath)/\(romFilename)",
                progress: nil
            )

            // Create and upload game config
            let config = generateDesktopFile(for: game, code: gameCode)
            let configData = Data(config.utf8)
            let tempPath = FileUtils.hakchiDirectory.appendingPathComponent("temp_\(gameCode).desktop")
            try configData.write(to: tempPath)
            try await ownedShell.uploadFile(
                localPath: tempPath.path,
                remotePath: "\(gamePath)/\(gameCode).desktop",
                progress: nil
            )
            try? FileManager.default.removeItem(at: tempPath)

            progress(Double(index + 1) / totalOps, "\(game.name) uploaded")
        }

        // Refresh game list on console
        _ = try await ownedShell.executeCommand("hakchi reload")

        progress(1.0, "Sync complete - \(games.count) games uploaded")
        HakchiLogger.games.info("Synced \(games.count) games to console")
    }

    func calculateTotalSize(games: [Game]) -> Int64 {
        games.reduce(0) { $0 + $1.romSize }
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

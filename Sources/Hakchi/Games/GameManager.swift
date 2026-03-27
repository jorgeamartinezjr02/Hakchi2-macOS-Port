import Foundation

final class GameManager {
    private let database = GameDatabase.shared

    func addGame(from url: URL) -> Game? {
        do {
            let rom = try ROMFile(url: url)
            let metadata = database.lookup(crc32: rom.crc32)

            // Copy ROM to app's game storage
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
        progress: @escaping (Double, String) -> Void
    ) async throws {
        let ssh = SSHClient()
        try await ssh.connect()
        let sftp = SFTPClient(sshClient: ssh)

        defer { ssh.disconnect() }

        let basePath = consoleType.gamesPath
        try await ssh.execute("mkdir -p \(basePath)")

        // Get existing games on console
        let existingGames: [String]
        do {
            existingGames = try sftp.listDirectory(path: basePath)
        } catch {
            existingGames = []
        }

        let totalOps = Double(games.count)

        for (index, game) in games.enumerated() {
            let gameCode = "CLV-Z-\(game.id.uuidString.prefix(5).uppercased())"
            let gamePath = "\(basePath)/\(gameCode)"

            progress(Double(index) / totalOps, "Uploading \(game.name)...")

            // Create game directory
            try await ssh.execute("mkdir -p \(gamePath)")

            // Upload ROM
            let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
            try await sftp.upload(
                localPath: game.romPath,
                remotePath: "\(gamePath)/\(romFilename)"
            )

            // Create game config
            let config = generateDesktopFile(for: game, code: gameCode)
            let configData = Data(config.utf8)
            let tempPath = FileUtils.hakchiDirectory.appendingPathComponent("temp_\(gameCode).desktop")
            try configData.write(to: tempPath)
            try await sftp.upload(
                localPath: tempPath.path,
                remotePath: "\(gamePath)/\(gameCode).desktop"
            )
            try? FileManager.default.removeItem(at: tempPath)

            progress(Double(index + 1) / totalOps, "\(game.name) uploaded")
        }

        // Refresh game list on console
        try await ssh.execute("hakchi reload")

        progress(1.0, "Sync complete - \(games.count) games uploaded")
        HakchiLogger.games.info("Synced \(games.count) games to console")
    }

    func calculateTotalSize(games: [Game]) -> Int64 {
        games.reduce(0) { $0 + $1.romSize }
    }

    private func generateDesktopFile(for game: Game, code: String) -> String {
        let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
        let exec: String
        switch game.consoleType {
        case .nesClassic:
            exec = "/bin/clover-kachikachi /usr/share/games/\(code)/\(romFilename)"
        case .snesClassic:
            exec = "/bin/clover-canoe-shvc /usr/share/games/\(code)/\(romFilename)"
        case .segaMini:
            exec = "/bin/retroarch /usr/share/games/\(code)/\(romFilename)"
        case .unknown:
            exec = "/bin/retroarch /usr/share/games/\(code)/\(romFilename)"
        }

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

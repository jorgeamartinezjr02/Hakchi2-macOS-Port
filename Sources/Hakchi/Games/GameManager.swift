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

        // Pre-flight: check available storage
        let storageInfo = try await ownedShell.executeCommand("df -k \(basePath) 2>/dev/null | tail -1 | awk '{print $4}'")
        let availableKB = Int64(storageInfo.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let requiredKB = calculateTotalSize(games: games) / 1024
        if availableKB > 0 && requiredKB > availableKB {
            throw HakchiError.invalidData(
                "Not enough storage: need \(requiredKB)KB but only \(availableKB)KB available")
        }

        // Unmount games partition to prevent corruption during writes (matching C#)
        _ = try? await ownedShell.executeCommand("hakchi eval 'umount \"$gamepath\"' 2>/dev/null")

        _ = try await ownedShell.executeCommand("mkdir -p \(basePath)")

        // Build delta: list what's already on the console
        let remoteListStr = try await ownedShell.executeCommand("ls -1 \(basePath) 2>/dev/null")
        let remoteGames = Set(remoteListStr.split(separator: "\n").map(String.init))

        let selectedGames = games.filter { $0.isSelected }
        let localGameCodes = Set(selectedGames.map { $0.clvCode })

        // Delete games that are no longer in the local list
        for remoteCode in remoteGames {
            if remoteCode.hasPrefix("CLV-") && !localGameCodes.contains(remoteCode) {
                _ = try? await ownedShell.executeCommand("rm -rf \(basePath)/\(remoteCode)")
                HakchiLogger.games.info("Removed remote game: \(remoteCode)")
            }
        }

        // Build tar archive for batch upload (much faster than individual SFTP)
        let totalOps = Double(selectedGames.count)
        let tarDir = FileUtils.hakchiDirectory.appendingPathComponent("sync_staging")
        try? FileManager.default.removeItem(at: tarDir)
        try FileManager.default.createDirectory(at: tarDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tarDir) }

        for (index, game) in selectedGames.enumerated() {
            let gameCode = game.clvCode
            let gamePath = "\(basePath)/\(gameCode)"

            // Skip if already on console (basic delta check)
            if remoteGames.contains(gameCode) {
                progress(Double(index + 1) / totalOps, "\(game.name) (already synced)")
                continue
            }

            progress(Double(index) / totalOps, "Preparing \(game.name)...")

            // Create local staging directory
            let stageDir = tarDir.appendingPathComponent(gameCode, isDirectory: true)
            try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

            // Copy ROM
            let romURL = URL(fileURLWithPath: game.romPath)
            let destROM = stageDir.appendingPathComponent(romURL.lastPathComponent)
            try FileManager.default.copyItem(at: romURL, to: destROM)

            // Generate .desktop file (complete format matching C# hakchi2-CE)
            let config = generateDesktopFile(for: game, code: gameCode)
            try config.write(to: stageDir.appendingPathComponent("\(gameCode).desktop"),
                            atomically: true, encoding: .utf8)

            // Copy cover art (both full-size and small icon)
            if let coverPath = game.coverArtPath,
               FileManager.default.fileExists(atPath: coverPath) {
                let coverDest = stageDir.appendingPathComponent("\(gameCode).png")
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: coverPath), to: coverDest)
                // Also create small icon (40x40 — used by some menu themes)
                let smallDest = stageDir.appendingPathComponent("\(gameCode)_small.png")
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: coverPath), to: smallDest)
            }
        }

        // Upload via tar stream (matching C# SyncRemoteGamesShell)
        progress(0.6, "Uploading games to console...")

        let tarPath = tarDir.appendingPathComponent("sync.tar")
        let tarResult = try runProcess("/usr/bin/tar", args: [
            "-cf", tarPath.path, "-C", tarDir.path
        ] + (try FileManager.default.contentsOfDirectory(atPath: tarDir.path)
            .filter { $0.hasPrefix("CLV-") }))

        if FileManager.default.fileExists(atPath: tarPath.path) {
            // Upload tar and extract on console
            try await ownedShell.uploadFile(
                localPath: tarPath.path,
                remotePath: "/tmp/hakchi_sync.tar",
                progress: { value in
                    progress(0.6 + (value ?? 0) * 0.3, "Transferring...")
                }
            )
            let extractResult = try await ownedShell.executeCommand(
                "tar -xf /tmp/hakchi_sync.tar -C \(basePath) 2>&1; echo EXIT:$?"
            )
            _ = try? await ownedShell.executeCommand("rm -f /tmp/hakchi_sync.tar")

            if !extractResult.contains("EXIT:0") {
                HakchiLogger.games.warning("Tar extract had issues: \(extractResult)")
            }
        } else {
            // Fallback: upload individually if tar failed
            for game in selectedGames where !remoteGames.contains(game.clvCode) {
                let stageDir = tarDir.appendingPathComponent(game.clvCode)
                guard FileManager.default.fileExists(atPath: stageDir.path) else { continue }

                let gamePath = "\(basePath)/\(game.clvCode)"
                _ = try await ownedShell.executeCommand("mkdir -p \(gamePath)")

                let files = try FileManager.default.contentsOfDirectory(at: stageDir, includingPropertiesForKeys: nil)
                for file in files {
                    try await ownedShell.uploadFile(
                        localPath: file.path,
                        remotePath: "\(gamePath)/\(file.lastPathComponent)",
                        progress: nil
                    )
                }
            }
        }

        // Set correct permissions
        _ = try? await ownedShell.executeCommand("chmod -R 755 \(basePath)")

        // Remount and sync
        _ = try? await ownedShell.executeCommand("sync")
        _ = try? await ownedShell.executeCommand("hakchi eval 'mount_base' 2>/dev/null")

        progress(1.0, "Sync complete - \(selectedGames.count) games")
        HakchiLogger.games.info("Synced \(selectedGames.count) games to console")
    }

    func calculateTotalSize(games: [Game]) -> Int64 {
        games.reduce(0) { total, game in
            // ROM + estimated .desktop + cover art overhead + filesystem block alignment
            let blockSize: Int64 = 4096
            let romBlocks = (game.romSize + blockSize - 1) / blockSize * blockSize
            let desktopEstimate: Int64 = blockSize  // .desktop file (small)
            let coverEstimate: Int64 = blockSize * 16 // ~64KB for cover art
            return total + romBlocks + desktopEstimate + coverEstimate
        }
    }

    @discardableResult
    private func runProcess(_ executable: String, args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Generate a complete .desktop file matching C# hakchi2-CE DesktopFile.GetConfig().
    /// Includes [Desktop Entry], [X-CLOVER Game], and [Description] sections.
    private func generateDesktopFile(for game: Game, code: String) -> String {
        let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
        let exec = CoreManager.shared.execLine(coreID: game.assignedCore, game: game, gameCode: code)
        let isSNES = game.consoleType.family == .snes

        var lines: [String] = []

        // [Desktop Entry] section
        lines.append("[Desktop Entry]")
        lines.append("Type=Application")
        lines.append("Exec=\(exec)")
        lines.append("Path=/var/lib/clover/profiles/0/\(code)")
        lines.append("Name=\(game.name)")
        lines.append("CePrefix=\(game.consoleType.clvPrefix)")
        lines.append("Icon=/usr/share/games/\(code)/\(code).png")
        lines.append("")

        // [X-CLOVER Game] section (critical for console UI display)
        lines.append("[X-CLOVER Game]")
        lines.append("Code=\(code)")
        lines.append("TestID=777")
        lines.append("ID=0")
        lines.append("Players=\(game.players)")
        lines.append("Simultaneous=\(game.simultaneous ? "1" : "0")")
        lines.append("ReleaseDate=\(game.releaseDate)")
        lines.append("SaveCount=\(game.saveCount)")
        lines.append("SortRawTitle=\(game.sortName.uppercased())")
        lines.append("SortRawPublisher=\(game.publisher.uppercased())")
        lines.append("Copyright=\(game.publisher) \(String(game.releaseDate.prefix(4)))")
        if isSNES {
            lines.append("MyPlayDemoTime=45")
        }
        lines.append("")

        // [m2engage] section (for Sega and extended metadata)
        lines.append("[m2engage]")
        lines.append("regionTag=\(game.region)")
        lines.append("sortRawGenre=\(game.genre.uppercased())")
        lines.append("index=0")
        lines.append("demo_time=45")
        lines.append("country=us")
        lines.append("")

        // [Description] section
        lines.append("[Description]")
        lines.append("\(game.name) by \(game.publisher)")

        return lines.joined(separator: "\n")
    }
}

import Foundation

/// Soft-delete system for games with restore capability.
final class TrashBin {
    static let shared = TrashBin()

    static let trashDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("trash", isDirectory: true)
    }()

    private let metadataFile: URL

    private init() {
        metadataFile = Self.trashDirectory.appendingPathComponent("trash_metadata.json")
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.trashDirectory.path) {
            try? fm.createDirectory(at: Self.trashDirectory, withIntermediateDirectories: true)
        }
    }

    /// Move a game to trash (soft delete).
    func trash(_ game: Game) throws -> TrashedGame {
        let trashDir = Self.trashDirectory.appendingPathComponent(game.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // Move ROM file
        let romURL = URL(fileURLWithPath: game.romPath)
        let trashedROM = trashDir.appendingPathComponent(romURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: romURL.path) {
            try FileManager.default.moveItem(at: romURL, to: trashedROM)
        }

        // Move cover art
        var trashedCoverPath: String?
        if let coverPath = game.coverArtPath, FileManager.default.fileExists(atPath: coverPath) {
            let coverURL = URL(fileURLWithPath: coverPath)
            let trashedCover = trashDir.appendingPathComponent(coverURL.lastPathComponent)
            try FileManager.default.moveItem(at: coverURL, to: trashedCover)
            trashedCoverPath = trashedCover.path
        }

        let trashed = TrashedGame(
            game: game,
            trashedROMPath: trashedROM.path,
            trashedCoverPath: trashedCoverPath,
            trashedDate: Date()
        )

        // Save metadata
        var allTrashed = loadTrashedGames()
        allTrashed.append(trashed)
        saveTrashedGames(allTrashed)

        HakchiLogger.games.info("Trashed game: \(game.name)")
        return trashed
    }

    /// Restore a game from trash.
    func restore(_ trashed: TrashedGame) throws -> Game {
        var game = trashed.game

        // Restore ROM
        let romURL = URL(fileURLWithPath: trashed.trashedROMPath)
        let restoredDir = FileUtils.gamesDirectory.appendingPathComponent(
            game.name.replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_", options: .regularExpression),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: restoredDir, withIntermediateDirectories: true)

        let restoredROM = restoredDir.appendingPathComponent(romURL.lastPathComponent)
        try FileManager.default.moveItem(at: romURL, to: restoredROM)
        game.romPath = restoredROM.path

        // Restore cover art (non-fatal — ROM is the critical asset)
        if let coverPath = trashed.trashedCoverPath, FileManager.default.fileExists(atPath: coverPath) {
            let coverURL = URL(fileURLWithPath: coverPath)
            let restoredCover = BoxArtManager.coverArtDirectory.appendingPathComponent(coverURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: coverURL, to: restoredCover)
                game.coverArtPath = restoredCover.path
            } catch {
                HakchiLogger.games.warning("Failed to restore cover art for \(game.name): \(error.localizedDescription)")
                game.coverArtPath = nil
            }
        }

        // Clean up trash directory
        let trashDir = Self.trashDirectory.appendingPathComponent(game.id.uuidString)
        try? FileManager.default.removeItem(at: trashDir)

        // Update metadata
        var allTrashed = loadTrashedGames()
        allTrashed.removeAll { $0.game.id == game.id }
        saveTrashedGames(allTrashed)

        HakchiLogger.games.info("Restored game: \(game.name)")
        return game
    }

    /// Permanently delete a trashed game.
    func permanentlyDelete(_ trashed: TrashedGame) {
        let trashDir = Self.trashDirectory.appendingPathComponent(trashed.game.id.uuidString)
        try? FileManager.default.removeItem(at: trashDir)

        var allTrashed = loadTrashedGames()
        allTrashed.removeAll { $0.game.id == trashed.game.id }
        saveTrashedGames(allTrashed)
    }

    /// Empty the entire trash.
    func emptyTrash() {
        let trashed = loadTrashedGames()
        for item in trashed {
            permanentlyDelete(item)
        }
    }

    func loadTrashedGames() -> [TrashedGame] {
        guard let data = try? Data(contentsOf: metadataFile) else { return [] }
        return (try? JSONDecoder().decode([TrashedGame].self, from: data)) ?? []
    }

    private func saveTrashedGames(_ games: [TrashedGame]) {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: metadataFile)
    }
}

struct TrashedGame: Identifiable, Codable {
    var id: UUID { game.id }
    let game: Game
    let trashedROMPath: String
    let trashedCoverPath: String?
    let trashedDate: Date
}

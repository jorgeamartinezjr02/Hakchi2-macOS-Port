import Foundation

/// Represents a save state or SRAM save for a game.
struct SaveState: Identifiable, Codable {
    let id: UUID
    let gameCode: String
    let gameName: String
    let slot: Int          // 0 = SRAM, 1-4 = suspend points
    let timestamp: Date
    let filePath: String   // local path to exported .clvs
    let fileSize: Int64

    var displayName: String {
        slot == 0 ? "SRAM Save" : "Suspend Point \(slot)"
    }

    init(id: UUID = UUID(), gameCode: String, gameName: String, slot: Int, timestamp: Date = Date(), filePath: String, fileSize: Int64 = 0) {
        self.id = id
        self.gameCode = gameCode
        self.gameName = gameName
        self.slot = slot
        self.timestamp = timestamp
        self.filePath = filePath
        self.fileSize = fileSize
    }
}

/// Manages save states: export, import, backup from connected console.
final class SaveStateManager {
    static let shared = SaveStateManager()

    static let savesDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("saves", isDirectory: true)
    }()

    private init() {
        ensureDirectory()
    }

    // MARK: - Export saves from console

    /// Export all saves for a game from the console.
    func exportSaves(gameCode: String, gameName: String, shell: ShellInterface) async throws -> [SaveState] {
        let remotePath = "/var/lib/clover/profiles/0/\(gameCode)"

        // List save files
        let listing = try await shell.executeCommand("ls -la \(remotePath)/ 2>/dev/null || echo ''")
        guard !listing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let gameDir = Self.savesDirectory.appendingPathComponent(gameCode)
        try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)

        var saves: [SaveState] = []

        // Export as .clvs (tar.gz archive)
        let clvsName = "\(gameCode)_\(Date().timeIntervalSince1970).clvs"
        let localPath = gameDir.appendingPathComponent(clvsName)

        // Create tar on console and download
        let tempRemote = "/tmp/\(clvsName)"
        _ = try await shell.executeCommand("cd /var/lib/clover/profiles/0 && tar czf \(tempRemote) \(gameCode)/")

        try await shell.downloadFile(remotePath: tempRemote, localPath: localPath.path, progress: nil)
        _ = try await shell.executeCommand("rm -f \(tempRemote)")

        let size = FileUtils.fileSize(at: localPath)

        saves.append(SaveState(
            gameCode: gameCode,
            gameName: gameName,
            slot: 0,
            filePath: localPath.path,
            fileSize: size
        ))

        HakchiLogger.games.info("Exported saves for \(gameName) (\(size) bytes)")
        return saves
    }

    /// Import a .clvs save file to the console.
    func importSave(clvsPath: String, shell: ShellInterface) async throws {
        let tempRemote = "/tmp/import_save.clvs"
        try await shell.uploadFile(localPath: clvsPath, remotePath: tempRemote, progress: nil)
        _ = try await shell.executeCommand("cd /var/lib/clover/profiles/0 && tar xzf \(tempRemote) && rm -f \(tempRemote)")
        HakchiLogger.games.info("Imported save from \(clvsPath)")
    }

    /// List locally exported saves.
    func listExportedSaves() -> [SaveState] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: Self.savesDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }

        var saves: [SaveState] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "clvs" else { continue }
            let gameCode = url.deletingLastPathComponent().lastPathComponent
            let size = FileUtils.fileSize(at: url)
            saves.append(SaveState(
                gameCode: gameCode,
                gameName: gameCode,
                slot: 0,
                filePath: url.path,
                fileSize: size
            ))
        }

        return saves.sorted { $0.timestamp > $1.timestamp }
    }

    /// Delete an exported save.
    func deleteSave(_ save: SaveState) {
        try? FileManager.default.removeItem(atPath: save.filePath)
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.savesDirectory.path) {
            try? fm.createDirectory(at: Self.savesDirectory, withIntermediateDirectories: true)
        }
    }
}

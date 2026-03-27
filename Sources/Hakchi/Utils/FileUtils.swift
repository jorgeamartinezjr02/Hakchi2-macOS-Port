import Foundation

enum FileUtils {
    static let hakchiDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Hakchi", isDirectory: true)
    }()

    static let gamesDirectory: URL = {
        hakchiDirectory.appendingPathComponent("games", isDirectory: true)
    }()

    static let modsDirectory: URL = {
        hakchiDirectory.appendingPathComponent("mods", isDirectory: true)
    }()

    static let kernelBackupDirectory: URL = {
        hakchiDirectory.appendingPathComponent("kernel_backup", isDirectory: true)
    }()

    static let configFile: URL = {
        hakchiDirectory.appendingPathComponent("config.json")
    }()

    static let gamesFile: URL = {
        hakchiDirectory.appendingPathComponent("games.json")
    }()

    static func ensureDirectoriesExist() {
        let fm = FileManager.default
        let dirs = [hakchiDirectory, gamesDirectory, modsDirectory, kernelBackupDirectory]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    static func copyROM(from source: URL, gameName: String) throws -> URL {
        ensureDirectoriesExist()
        let gameDir = gamesDirectory.appendingPathComponent(
            gameName.replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_", options: .regularExpression),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)

        let destination = gameDir.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }

    static func extractTarGz(at path: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", path.path, "-C", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HakchiError.extractionFailed(path.lastPathComponent)
        }
    }

    static func createTarGz(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", destination.path, "-C", source.deletingLastPathComponent().path, source.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HakchiError.compressionFailed(source.lastPathComponent)
        }
    }
}

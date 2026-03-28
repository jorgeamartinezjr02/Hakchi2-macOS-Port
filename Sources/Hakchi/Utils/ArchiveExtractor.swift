import Foundation

/// Extracts archives of various formats using system tools.
/// Supports: .zip, .7z, .rar, .tar, .tar.gz, .tgz, .clvg
enum ArchiveExtractor {
    static let supportedArchiveExtensions = ["zip", "7z", "rar", "tar", "gz", "tgz", "clvg"]

    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedArchiveExtensions.contains(ext) { return true }
        // Handle .tar.gz
        if ext == "gz" && url.deletingPathExtension().pathExtension.lowercased() == "tar" { return true }
        return false
    }

    /// Extract an archive to a temporary directory and return URLs of extracted ROM files.
    static func extractROMs(from archiveURL: URL) throws -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hakchi_extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try extract(archiveURL, to: tempDir)

        // Find all ROM files recursively
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        var romFiles: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            if ROMFile.isSupportedExtension(fileURL.pathExtension) {
                romFiles.append(fileURL)
            }
        }

        if romFiles.isEmpty {
            // Cleanup if no ROMs found
            try? FileManager.default.removeItem(at: tempDir)
            throw HakchiError.extractionFailed("No ROM files found in archive: \(archiveURL.lastPathComponent)")
        }

        return romFiles
    }

    /// Extract a .clvg package (hakchi game package) and return the game directory.
    static func extractCLVG(from archiveURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hakchi_clvg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try extract(archiveURL, to: tempDir)
        return tempDir
    }

    /// Clean up extracted temp directory
    static func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Private

    private static func extract(_ archive: URL, to destination: URL) throws {
        let ext = archive.pathExtension.lowercased()
        let filename = archive.lastPathComponent.lowercased()

        if ext == "zip" || ext == "clvg" {
            try runProcess("/usr/bin/ditto", arguments: ["-xk", archive.path, destination.path])
        } else if ext == "gz" || ext == "tgz" || filename.hasSuffix(".tar.gz") {
            try runProcess("/usr/bin/tar", arguments: ["-xzf", archive.path, "-C", destination.path])
        } else if ext == "tar" {
            try runProcess("/usr/bin/tar", arguments: ["-xf", archive.path, "-C", destination.path])
        } else if ext == "7z" {
            // 7z requires p7zip (brew install p7zip)
            let sevenZip = findExecutable("7z") ?? findExecutable("7za")
            guard let exe = sevenZip else {
                throw HakchiError.extractionFailed("7z not found. Install with: brew install p7zip")
            }
            try runProcess(exe, arguments: ["x", archive.path, "-o\(destination.path)", "-y"])
        } else if ext == "rar" {
            // unrar required (brew install unrar)
            guard let exe = findExecutable("unrar") else {
                throw HakchiError.extractionFailed("unrar not found. Install with: brew install unrar")
            }
            try runProcess(exe, arguments: ["x", archive.path, destination.path + "/", "-y"])
        } else {
            throw HakchiError.extractionFailed("Unsupported archive format: \(ext)")
        }
    }

    private static func runProcess(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw HakchiError.extractionFailed(errorMsg.prefix(200).description)
        }
    }

    private static func findExecutable(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

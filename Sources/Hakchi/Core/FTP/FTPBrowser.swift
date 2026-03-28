import Foundation

/// Entry in a remote file listing.
struct RemoteFileEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let permissions: String

    var displaySize: String {
        if isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

/// Browse and manage files on the console via SFTP/Clovershell.
final class FTPBrowser {
    private var shell: ShellInterface?

    var isConnected: Bool { shell != nil }

    func connect(shell: ShellInterface) {
        self.shell = shell
    }

    func disconnect() {
        shell?.disconnect()
        shell = nil
    }

    /// List files in a directory.
    func listFiles(path: String) async throws -> [RemoteFileEntry] {
        guard let shell = shell else { throw HakchiError.notConnected }

        let output = try await shell.executeCommand("ls -la \(path) 2>/dev/null")
        return parseLsOutput(output, basePath: path)
    }

    /// Download a file to local path.
    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let shell = shell else { throw HakchiError.notConnected }
        try await shell.downloadFile(remotePath: remotePath, localPath: localPath, progress: progress)
    }

    /// Upload a file to remote path.
    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let shell = shell else { throw HakchiError.notConnected }
        try await shell.uploadFile(localPath: localPath, remotePath: remotePath, progress: progress)
    }

    /// Delete a remote file or directory.
    func deleteFile(path: String) async throws {
        guard let shell = shell else { throw HakchiError.notConnected }
        _ = try await shell.executeCommand("rm -rf \(path)")
    }

    /// Create a remote directory.
    func createDirectory(path: String) async throws {
        guard let shell = shell else { throw HakchiError.notConnected }
        _ = try await shell.executeCommand("mkdir -p \(path)")
    }

    // MARK: - Private

    private func parseLsOutput(_ output: String, basePath: String) -> [RemoteFileEntry] {
        let lines = output.split(separator: "\n")
        var entries: [RemoteFileEntry] = []

        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 9 else { continue }

            let permissions = parts[0]
            guard permissions.count >= 10 else { continue }

            let isDir = permissions.hasPrefix("d")
            let size = Int64(parts[4]) ?? 0
            let name = parts[8...].joined(separator: " ")

            guard name != "." && name != ".." else { continue }

            let fullPath = basePath.hasSuffix("/") ? "\(basePath)\(name)" : "\(basePath)/\(name)"

            entries.append(RemoteFileEntry(
                name: name,
                path: fullPath,
                isDirectory: isDir,
                size: size,
                permissions: permissions
            ))
        }

        return entries.sorted { (a, b) in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.lowercased() < b.name.lowercased()
        }
    }
}

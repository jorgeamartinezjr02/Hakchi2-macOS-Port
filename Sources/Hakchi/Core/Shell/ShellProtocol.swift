import Foundation

/// Unified interface for console communication over SSH or Clovershell USB.
protocol ShellInterface {
    func executeCommand(_ command: String) async throws -> String
    func readFile(remotePath: String) async throws -> Data
    func writeFile(remotePath: String, data: Data) async throws
    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)?) async throws
    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)?) async throws
    func listDirectory(path: String) async throws -> [String]
    func disconnect()
}

/// SSH + SFTP implementation of ShellInterface
final class SSHShell: ShellInterface {
    private let ssh: SSHClient
    private lazy var sftp = SFTPClient(sshClient: ssh)

    init(host: String = "169.254.1.1", port: Int = 22) async throws {
        self.ssh = SSHClient()
        try await ssh.connect(host: host, port: port)
    }

    func executeCommand(_ command: String) async throws -> String {
        try await ssh.execute(command)
    }

    func readFile(remotePath: String) async throws -> Data {
        let tempDir = FileUtils.hakchiDirectory.appendingPathComponent("tmp")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localPath = tempDir.appendingPathComponent(UUID().uuidString).path
        try await sftp.download(remotePath: remotePath, localPath: localPath)
        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        try? FileManager.default.removeItem(atPath: localPath)
        return data
    }

    func writeFile(remotePath: String, data: Data) async throws {
        let tempDir = FileUtils.hakchiDirectory.appendingPathComponent("tmp")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localPath = tempDir.appendingPathComponent(UUID().uuidString).path
        try data.write(to: URL(fileURLWithPath: localPath))
        try await sftp.upload(localPath: localPath, remotePath: remotePath)
        try? FileManager.default.removeItem(atPath: localPath)
    }

    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)?) async throws {
        try await sftp.upload(localPath: localPath, remotePath: remotePath, progress: progress)
    }

    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)?) async throws {
        try await sftp.download(remotePath: remotePath, localPath: localPath, progress: progress)
    }

    func listDirectory(path: String) async throws -> [String] {
        try sftp.listDirectory(path: path)
    }

    func disconnect() {
        sftp.closeSFTP()
        ssh.disconnect()
    }
}

/// Clovershell USB implementation of ShellInterface
final class ClovershellShell: ShellInterface {
    private let client: ClovershellClient

    init() throws {
        self.client = ClovershellClient()
        try client.connect()
    }

    func executeCommand(_ command: String) async throws -> String {
        try client.executeCommand(command)
    }

    func readFile(remotePath: String) async throws -> Data {
        try client.readFile(remotePath: remotePath)
    }

    func writeFile(remotePath: String, data: Data) async throws {
        // Clovershell stdin streaming is unreliable for large files (no backpressure).
        // Use base64 chunked transfer via executeCommand instead — each chunk is an
        // independent command that completes before the next one starts.
        let safePath = remotePath.replacingOccurrences(of: "'", with: "'\\''")
        let chunkSize = 32768 // 32KB raw → ~44KB base64, fits in one Clovershell packet
        HakchiLogger.fileLog("clovershell", "writeFile(base64): \(data.count) bytes → \(remotePath)")

        // Create/truncate the file
        let initResult = try client.executeCommand(": > '\(safePath)' && echo OK")
        guard initResult.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            throw HakchiError.sftpTransferFailed("Failed to create \(remotePath): \(initResult)")
        }

        var offset = 0
        var chunkIndex = 0
        let totalChunks = (data.count + chunkSize - 1) / chunkSize

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            let base64 = chunk.base64EncodedString()

            // Use printf to avoid echo's newline interpretation issues with special chars
            let result = try client.executeCommand(
                "printf '%s' '\(base64)' | base64 -d >> '\(safePath)' && echo OK"
            )
            guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
                throw HakchiError.sftpTransferFailed(
                    "Chunk \(chunkIndex+1)/\(totalChunks) failed for \(remotePath): \(result)"
                )
            }

            offset = end
            chunkIndex += 1
            if chunkIndex % 20 == 0 {
                HakchiLogger.fileLog("clovershell", "writeFile(base64): chunk \(chunkIndex)/\(totalChunks)")
            }
        }

        HakchiLogger.fileLog("clovershell", "writeFile(base64): complete (\(totalChunks) chunks)")
    }

    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)?) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        try await writeFile(remotePath: remotePath, data: data)
        progress?(1.0)
    }

    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)?) async throws {
        let data = try client.readFile(remotePath: remotePath)
        try data.write(to: URL(fileURLWithPath: localPath))
        progress?(1.0)
    }

    func listDirectory(path: String) async throws -> [String] {
        let safePath = path.replacingOccurrences(of: "'", with: "'\\''")
        let output = try client.executeCommand("ls -1 '\(safePath)'")
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func disconnect() {
        client.disconnect()
    }
}

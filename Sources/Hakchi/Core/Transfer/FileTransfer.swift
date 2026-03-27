import Foundation

actor FileTransfer {
    enum TransferMode {
        case ssh
        case clovershell
    }

    private let sshClient: SSHClient?
    private let clovershell: ClovershellClient?
    private let mode: TransferMode

    init(sshClient: SSHClient) {
        self.sshClient = sshClient
        self.clovershell = nil
        self.mode = .ssh
    }

    init(clovershell: ClovershellClient) {
        self.sshClient = nil
        self.clovershell = clovershell
        self.mode = .clovershell
    }

    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) async throws {
        switch mode {
        case .ssh:
            guard let ssh = sshClient else { throw HakchiError.notConnected }
            let sftp = SFTPClient(sshClient: ssh)
            try await sftp.upload(localPath: localPath, remotePath: remotePath, progress: progress)

        case .clovershell:
            guard let clover = clovershell else { throw HakchiError.notConnected }
            let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
            try clover.writeFile(remotePath: remotePath, data: data)
            progress?(1.0)
        }
    }

    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) async throws {
        switch mode {
        case .ssh:
            guard let ssh = sshClient else { throw HakchiError.notConnected }
            let sftp = SFTPClient(sshClient: ssh)
            try await sftp.download(remotePath: remotePath, localPath: localPath, progress: progress)

        case .clovershell:
            guard let clover = clovershell else { throw HakchiError.notConnected }
            let data = try clover.readFile(remotePath: remotePath)
            try data.write(to: URL(fileURLWithPath: localPath))
            progress?(1.0)
        }
    }

    func executeCommand(_ command: String) async throws -> String {
        switch mode {
        case .ssh:
            guard let ssh = sshClient else { throw HakchiError.notConnected }
            return try await ssh.execute(command)

        case .clovershell:
            guard let clover = clovershell else { throw HakchiError.notConnected }
            return try clover.executeCommand(command)
        }
    }

    func syncFiles(
        operations: [SyncOperation],
        basePath: String,
        progress: ((Double, String) -> Void)? = nil
    ) async throws {
        let total = Double(operations.count)

        for (index, op) in operations.enumerated() {
            let gameDir = "\(basePath)/CLV-Z-\(op.game.id.uuidString.prefix(5).uppercased())"

            switch op.type {
            case .upload:
                progress?(Double(index) / total, "Uploading \(op.game.name)...")
                try await executeCommand("mkdir -p \(gameDir)")
                try await uploadFile(
                    localPath: op.game.romPath,
                    remotePath: "\(gameDir)/\(URL(fileURLWithPath: op.game.romPath).lastPathComponent)"
                )

            case .delete:
                progress?(Double(index) / total, "Removing \(op.game.name)...")
                try await executeCommand("rm -rf \(gameDir)")

            case .update:
                progress?(Double(index) / total, "Updating \(op.game.name)...")
                try await executeCommand("rm -rf \(gameDir)")
                try await executeCommand("mkdir -p \(gameDir)")
                try await uploadFile(
                    localPath: op.game.romPath,
                    remotePath: "\(gameDir)/\(URL(fileURLWithPath: op.game.romPath).lastPathComponent)"
                )
            }
        }

        progress?(1.0, "Sync complete")
    }
}

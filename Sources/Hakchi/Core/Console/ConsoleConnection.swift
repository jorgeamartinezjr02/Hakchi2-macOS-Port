import Foundation
import Combine

actor ConsoleConnection {
    private var sshClient: SSHClient?
    private var felDevice: FELDevice?
    private var info: ConsoleInfo?

    var isConnected: Bool {
        sshClient != nil || felDevice != nil
    }

    func connectSSH(host: String = "169.254.1.1", port: Int = 22) async throws -> ConsoleInfo {
        let client = SSHClient()
        try await client.connect(host: host, port: port, username: "root")
        sshClient = client

        let consoleInfo = try await gatherConsoleInfo(via: client)
        info = consoleInfo
        return consoleInfo
    }

    func connectFEL() async throws {
        let device = FELDevice()
        try device.open()
        let version = try device.getVersion()
        felDevice = device

        info = ConsoleInfo(
            consoleType: ConsoleType.from(felVersion: version),
            firmwareVersion: "FEL Mode"
        )
    }

    func disconnect() {
        sshClient?.disconnect()
        sshClient = nil
        felDevice?.close()
        felDevice = nil
        info = nil
    }

    func executeCommand(_ command: String) async throws -> String {
        guard let ssh = sshClient else {
            throw HakchiError.notConnected
        }
        return try await ssh.execute(command)
    }

    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let ssh = sshClient else {
            throw HakchiError.notConnected
        }
        let sftp = SFTPClient(sshClient: ssh)
        try await sftp.upload(localPath: localPath, remotePath: remotePath, progress: progress)
    }

    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let ssh = sshClient else {
            throw HakchiError.notConnected
        }
        let sftp = SFTPClient(sshClient: ssh)
        try await sftp.download(remotePath: remotePath, localPath: localPath, progress: progress)
    }

    private func gatherConsoleInfo(via ssh: SSHClient) async throws -> ConsoleInfo {
        let hakchiVersion = (try? await ssh.execute("cat /var/lib/hakchi/rootfs/etc/hakchi_version")) ?? "Unknown"
        let storageInfo = (try? await ssh.execute("df /var/lib/hakchi | tail -1")) ?? ""
        let mac = (try? await ssh.execute("cat /sys/class/net/usb0/address")) ?? ""

        var total: Int64 = 0
        var used: Int64 = 0
        let storageComponents = storageInfo.split(separator: " ").map(String.init)
        if storageComponents.count >= 4 {
            total = (Int64(storageComponents[1]) ?? 0) * 1024
            used = (Int64(storageComponents[2]) ?? 0) * 1024
        }

        let consoleTypeStr = (try? await ssh.execute("cat /etc/clover/profile/console.type")) ?? ""
        let consoleType: ConsoleType
        if consoleTypeStr.contains("nes") {
            consoleType = .nesClassic
        } else if consoleTypeStr.contains("snes") || consoleTypeStr.contains("shvc") {
            consoleType = .snesClassic
        } else if consoleTypeStr.contains("md") || consoleTypeStr.contains("sega") {
            consoleType = .segaMini
        } else {
            consoleType = .unknown
        }

        return ConsoleInfo(
            consoleType: consoleType,
            hakchiVersion: hakchiVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            totalStorage: total,
            usedStorage: used,
            macAddress: mac.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

extension ConsoleType {
    static func from(felVersion: FELVersion) -> ConsoleType {
        // NES/SNES Classic both use Allwinner R16, differentiate by board
        switch felVersion.board {
        case let b where b.contains("NES"):
            return .nesClassic
        case let b where b.contains("SNES"), let b where b.contains("SHVC"):
            return .snesClassic
        default:
            return .unknown
        }
    }
}

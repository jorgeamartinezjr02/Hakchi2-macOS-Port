import Foundation
import Combine

actor ConsoleConnection {
    enum ConnectionMode {
        case ssh
        case clovershell
        case fel
        case none
    }

    private(set) var shell: ShellInterface?
    private var felDevice: FELDevice?
    private var info: ConsoleInfo?
    private(set) var mode: ConnectionMode = .none

    var isConnected: Bool {
        shell != nil || felDevice != nil
    }

    func connectSSH(host: String = "169.254.1.1", port: Int = 22) async throws -> ConsoleInfo {
        let sshShell = try await SSHShell(host: host, port: port)
        shell = sshShell
        mode = .ssh

        let consoleInfo = try await gatherConsoleInfo(via: sshShell)
        info = consoleInfo
        return consoleInfo
    }

    func connectClovershell() async throws -> ConsoleInfo {
        let clovershell = try ClovershellShell()
        shell = clovershell
        mode = .clovershell

        let consoleInfo = try await gatherConsoleInfo(via: clovershell)
        info = consoleInfo
        return consoleInfo
    }

    func connectFEL() async throws {
        let device = FELDevice()
        try device.open()
        let version = try device.getVersion()
        felDevice = device
        mode = .fel

        info = ConsoleInfo(
            consoleType: ConsoleType.from(felVersion: version),
            firmwareVersion: "FEL Mode"
        )
    }

    func disconnect() {
        shell?.disconnect()
        shell = nil
        felDevice?.close()
        felDevice = nil
        info = nil
        mode = .none
    }

    func executeCommand(_ command: String) async throws -> String {
        guard let shell = shell else {
            throw HakchiError.notConnected
        }
        return try await shell.executeCommand(command)
    }

    func uploadFile(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let shell = shell else {
            throw HakchiError.notConnected
        }
        try await shell.uploadFile(localPath: localPath, remotePath: remotePath, progress: progress)
    }

    func downloadFile(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) async throws {
        guard let shell = shell else {
            throw HakchiError.notConnected
        }
        try await shell.downloadFile(remotePath: remotePath, localPath: localPath, progress: progress)
    }

    private func gatherConsoleInfo(via shell: ShellInterface) async throws -> ConsoleInfo {
        let hakchiVersion = (try? await shell.executeCommand("cat /var/lib/hakchi/rootfs/etc/hakchi_version")) ?? "Unknown"
        let storageInfo = (try? await shell.executeCommand("df /var/lib/hakchi | tail -1")) ?? ""
        let mac = (try? await shell.executeCommand("cat /sys/class/net/usb0/address")) ?? ""

        var total: Int64 = 0
        var used: Int64 = 0
        let storageComponents = storageInfo.split(separator: " ").map(String.init)
        if storageComponents.count >= 4 {
            total = (Int64(storageComponents[1]) ?? 0) * 1024
            used = (Int64(storageComponents[2]) ?? 0) * 1024
        }

        let consoleTypeStr = (try? await shell.executeCommand("cat /etc/clover/profile/console.type"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let regionStr = (try? await shell.executeCommand("cat /etc/clover/profile/region"))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let consoleType = ConsoleType.detect(from: consoleTypeStr, region: regionStr)

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
        let board = felVersion.board.uppercased()
        if board.contains("NES") {
            if board.contains("EU") || board.contains("CLV-101") { return .nesEU }
            if board.contains("HVC") || board.contains("JP") { return .famicomMini }
            return .nesUSA
        }
        if board.contains("SNES") || board.contains("SHVC") {
            if board.contains("EU") || board.contains("CLV-301") { return .snesEU }
            if board.contains("SHVC") || board.contains("JP") { return .superFamicomMini }
            return .snesUSA
        }
        if board.contains("MD") || board.contains("GENESIS") || board.contains("MEGA") {
            if board.contains("EU") { return .megaDriveEU }
            if board.contains("JP") { return .megaDriveJP }
            return .genesisUSA
        }
        return .unknown
    }

    /// Detect console type from the profile files on the console filesystem.
    /// IMPORTANT: Check SNES/SHVC before NES since "snes" contains "nes".
    static func detect(from typeString: String, region: String) -> ConsoleType {
        let t = typeString.lowercased()
        let r = region.lowercased()

        // Check SNES/SHVC first (before NES, since "snes" contains "nes")
        if t.contains("snes") || t.contains("shvc") {
            if t.contains("shvc") || r.contains("jpn") || r.contains("japan") { return .superFamicomMini }
            if r.contains("eur") || r.contains("eu") { return .snesEU }
            return .snesUSA
        }
        if t.contains("nes") || t.contains("hvc") {
            if t.contains("hvc") || r.contains("jpn") || r.contains("japan") { return .famicomMini }
            if r.contains("eur") || r.contains("eu") { return .nesEU }
            return .nesUSA
        }
        if t.contains("md") || t.contains("sega") || t.contains("genesis") || t.contains("mega") {
            if r.contains("jpn") || r.contains("japan") { return .megaDriveJP }
            if r.contains("eur") || r.contains("eu") { return .megaDriveEU }
            return .genesisUSA
        }
        return .unknown
    }
}

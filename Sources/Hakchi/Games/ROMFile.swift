import Foundation

struct ROMFile {
    let url: URL
    let filename: String
    let fileExtension: String
    let fileSize: Int64
    let crc32: String
    let consoleType: ConsoleType

    init(url: URL) throws {
        self.url = url
        self.filename = url.deletingPathExtension().lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.fileSize = FileUtils.fileSize(at: url)

        guard Self.isSupportedExtension(fileExtension) else {
            throw HakchiError.romNotSupported(fileExtension)
        }

        self.crc32 = try CRC32.hexString(fileAt: url)
        self.consoleType = Self.detectConsoleType(extension: fileExtension)
    }

    /// All ROM extensions supported (native + RetroArch cores)
    static let allSupportedExtensions = [
        // NES
        "nes", "fds", "unf", "unif", "qd",
        // SNES
        "sfc", "smc", "fig", "swc", "sfrom",
        // Genesis / Mega Drive
        "md", "smd", "gen", "bin",
        // Game Boy
        "gb",
        // Game Boy Color
        "gbc",
        // Game Boy Advance
        "gba",
        // TurboGrafx-16 / PC Engine
        "pce",
        // Sega Master System / Game Gear
        "sms", "gg",
        // N64
        "n64", "z64", "v64",
        // PS1
        "cue", "iso", "pbp", "chd",
        // Neo Geo Pocket
        "ngp", "ngc",
        // Atari 2600
        "a26",
    ]

    static func isSupportedExtension(_ ext: String) -> Bool {
        allSupportedExtensions.contains(ext.lowercased())
    }

    static func detectConsoleType(extension ext: String) -> ConsoleType {
        switch ext.lowercased() {
        case "nes", "fds", "unf", "unif", "qd":
            return .nesUSA
        case "sfc", "smc", "fig", "swc", "sfrom":
            return .snesUSA
        case "md", "smd", "gen", "bin", "sms", "gg":
            return .genesisUSA
        default:
            // RetroArch-only systems default to unknown console type
            // (they run via RetroArch, not a native emulator)
            return .unknown
        }
    }

    /// Detect the system string for RetroArch core matching
    static func detectSystem(extension ext: String) -> String? {
        CoreManager.shared.detectSystem(for: ext)
    }

    func toGame(metadata: GameMetadata? = nil) -> Game {
        let meta = metadata ?? GameDatabase.shared.lookup(crc32: crc32)
        let system = Self.detectSystem(extension: fileExtension)
        let defaultCore = system.flatMap { CoreManager.shared.defaultCoreID(for: $0) }
        // Only assign a RetroArch core for non-native systems
        let needsCore = consoleType == .unknown && system != nil

        return Game(
            name: meta?.name ?? filename,
            sortName: meta?.sortName ?? filename,
            publisher: meta?.publisher ?? "",
            releaseDate: meta?.releaseDate ?? "",
            players: meta?.players ?? 1,
            romPath: url.path,
            romSize: fileSize,
            romCRC32: crc32,
            consoleType: consoleType,
            assignedCore: needsCore ? defaultCore : nil,
            system: system ?? meta?.system,
            region: meta?.region ?? "USA"
        )
    }

    var hasNESHeader: Bool {
        guard fileExtension == "nes" else { return false }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        guard data.count >= 16 else { return false }
        return data[0] == 0x4E && data[1] == 0x45 && data[2] == 0x53 && data[3] == 0x1A // "NES\x1A"
    }

    var hasSMCHeader: Bool {
        guard ["smc", "fig", "swc"].contains(fileExtension) else { return false }
        return fileSize % 1024 == 512
    }

    func strippedData() throws -> Data {
        var data = try Data(contentsOf: url)
        if hasSMCHeader && data.count > 512 {
            data = Data(data.dropFirst(512))
        }
        return data
    }
}

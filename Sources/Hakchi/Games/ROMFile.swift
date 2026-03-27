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

    static func isSupportedExtension(_ ext: String) -> Bool {
        let supported = ["nes", "fds", "unf", "unif", "sfc", "smc", "fig", "swc", "md", "smd", "gen", "bin"]
        return supported.contains(ext.lowercased())
    }

    static func detectConsoleType(extension ext: String) -> ConsoleType {
        switch ext.lowercased() {
        case "nes", "fds", "unf", "unif":
            return .nesClassic
        case "sfc", "smc", "fig", "swc":
            return .snesClassic
        case "md", "smd", "gen", "bin":
            return .segaMini
        default:
            return .unknown
        }
    }

    func toGame(metadata: GameMetadata? = nil) -> Game {
        let meta = metadata ?? GameDatabase.shared.lookup(crc32: crc32)

        return Game(
            name: meta?.name ?? filename,
            sortName: meta?.sortName ?? filename,
            publisher: meta?.publisher ?? "",
            releaseDate: meta?.releaseDate ?? "",
            players: meta?.players ?? 1,
            romPath: url.path,
            romSize: fileSize,
            romCRC32: crc32,
            consoleType: consoleType
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
        if hasSMCHeader {
            data = data.dropFirst(512)
        }
        return data
    }
}

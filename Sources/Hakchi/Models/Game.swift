import Foundation

struct Game: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sortName: String
    var publisher: String
    var releaseDate: String
    var players: Int
    var romPath: String
    var romSize: Int64
    var romCRC32: String
    var coverArtPath: String?
    var consoleType: ConsoleType
    var isSelected: Bool
    var folder: String
    var genre: String
    var commandLine: String
    var saveCount: Int
    var simultaneous: Bool
    var clvCode: String
    var assignedCore: String?
    var system: String?
    var region: String

    init(
        id: UUID = UUID(),
        name: String,
        sortName: String = "",
        publisher: String = "",
        releaseDate: String = "",
        players: Int = 1,
        romPath: String,
        romSize: Int64 = 0,
        romCRC32: String = "",
        coverArtPath: String? = nil,
        consoleType: ConsoleType = .unknown,
        isSelected: Bool = true,
        folder: String = "/",
        genre: String = "",
        commandLine: String = "",
        saveCount: Int = 0,
        simultaneous: Bool = false,
        clvCode: String = "",
        assignedCore: String? = nil,
        system: String? = nil,
        region: String = "USA"
    ) {
        self.id = id
        self.name = name
        self.sortName = sortName.isEmpty ? name : sortName
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.players = players
        self.romPath = romPath
        self.romSize = romSize
        self.romCRC32 = romCRC32
        self.coverArtPath = coverArtPath
        self.consoleType = consoleType
        self.isSelected = isSelected
        self.folder = folder
        self.genre = genre
        self.saveCount = saveCount
        self.simultaneous = simultaneous
        self.assignedCore = assignedCore
        self.system = system
        self.region = region

        if clvCode.isEmpty {
            // Use CRC32-based deterministic code when CRC is available
            if !romCRC32.isEmpty, let crcValue = UInt32(romCRC32, radix: 16) {
                self.clvCode = Self.generateCLVCode(consoleType: consoleType, crc32: crcValue)
            } else {
                self.clvCode = Self.generateCLVCode(consoleType: consoleType)
            }
        } else {
            self.clvCode = clvCode
        }

        if commandLine.isEmpty {
            let romFilename = URL(fileURLWithPath: romPath).lastPathComponent
            self.commandLine = "\(consoleType.stockEmulator) /usr/share/games/\(self.clvCode)/\(romFilename)"
        } else {
            self.commandLine = commandLine
        }
    }

    /// Generate a deterministic CLV code from CRC32 hash (matching C# hakchi2-CE).
    /// Same ROM always produces the same code, preserving save states across re-syncs.
    static func generateCLVCode(consoleType: ConsoleType, crc32: UInt32) -> String {
        var crc = crc32
        let c0 = Character(UnicodeScalar(UInt8(65 + crc % 26))); crc >>= 5  // A-Z
        let c1 = Character(UnicodeScalar(UInt8(65 + crc % 26))); crc >>= 5
        let c2 = Character(UnicodeScalar(UInt8(65 + crc % 26))); crc >>= 5
        let c3 = Character(UnicodeScalar(UInt8(65 + crc % 26))); crc >>= 5
        let c4 = Character(UnicodeScalar(UInt8(65 + crc % 26)))
        return "\(consoleType.clvPrefix)-\(c0)\(c1)\(c2)\(c3)\(c4)"
    }

    /// Fallback for when CRC32 is not available.
    static func generateCLVCode(consoleType: ConsoleType) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let suffix = String((0..<5).map { _ in chars.randomElement() ?? Character("A") })
        return "\(consoleType.clvPrefix)-\(suffix)"
    }
}

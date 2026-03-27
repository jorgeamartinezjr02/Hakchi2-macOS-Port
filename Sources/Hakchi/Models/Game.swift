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
        clvCode: String = ""
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

        if clvCode.isEmpty {
            self.clvCode = Self.generateCLVCode(consoleType: consoleType)
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

    static func generateCLVCode(consoleType: ConsoleType) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let suffix = String((0..<5).map { _ in chars.randomElement()! })
        return "\(consoleType.clvPrefix)-\(suffix)"
    }
}

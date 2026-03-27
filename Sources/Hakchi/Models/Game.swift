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
        folder: String = "/"
    ) {
        self.id = id
        self.name = name
        let resolvedSortName = sortName.isEmpty ? name : sortName
        self.sortName = resolvedSortName
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
    }
}

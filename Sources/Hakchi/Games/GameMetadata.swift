import Foundation

struct GameMetadata: Codable {
    let name: String
    let sortName: String
    let publisher: String
    let releaseDate: String
    let players: Int
    let crc32: String
    let system: String
    let region: String
    let coverUrl: String?

    init(
        name: String,
        sortName: String = "",
        publisher: String = "",
        releaseDate: String = "",
        players: Int = 1,
        crc32: String = "",
        system: String = "",
        region: String = "",
        coverUrl: String? = nil
    ) {
        self.name = name
        self.sortName = sortName.isEmpty ? name : sortName
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.players = players
        self.crc32 = crc32
        self.system = system
        self.region = region
        self.coverUrl = coverUrl
    }
}

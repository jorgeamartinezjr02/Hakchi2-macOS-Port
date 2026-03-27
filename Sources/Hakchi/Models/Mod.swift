import Foundation

struct Mod: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var version: String
    var author: String
    var description: String
    var category: ModCategory
    var filePath: String
    var isInstalled: Bool
    var fileSize: Int64

    init(
        id: UUID = UUID(),
        name: String,
        version: String = "1.0",
        author: String = "",
        description: String = "",
        category: ModCategory = .other,
        filePath: String = "",
        isInstalled: Bool = false,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.category = category
        self.filePath = filePath
        self.isInstalled = isInstalled
        self.fileSize = fileSize
    }
}

enum ModCategory: String, Codable, CaseIterable {
    case emulator = "Emulator"
    case retroarch = "RetroArch"
    case ui = "UI Enhancement"
    case system = "System"
    case other = "Other"
}

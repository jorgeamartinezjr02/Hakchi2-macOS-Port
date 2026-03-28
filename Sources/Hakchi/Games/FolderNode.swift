import Foundation

/// Represents a folder in the game organization hierarchy.
struct FolderNode: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var position: Int
    var iconPath: String?

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        position: Int = 0,
        iconPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.position = position
        self.iconPath = iconPath
    }

    /// The root folder (virtual, not stored)
    static let root = FolderNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Root")
}

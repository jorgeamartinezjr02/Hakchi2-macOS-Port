import Foundation

/// Manages game folder hierarchy and auto-splitting algorithms.
final class FolderManager {
    static let shared = FolderManager()

    var folders: [FolderNode] = []
    private let saveURL = FileUtils.hakchiDirectory.appendingPathComponent("folders.json")

    private init() {
        loadFolders()
    }

    // MARK: - CRUD

    func createFolder(name: String, parentID: UUID? = nil) -> FolderNode {
        let position = folders.filter { $0.parentID == parentID }.count
        let folder = FolderNode(name: name, parentID: parentID, position: position)
        folders.append(folder)
        saveFolders()
        return folder
    }

    func deleteFolder(_ id: UUID) {
        // Move children to parent
        let folder = folders.first { $0.id == id }
        let parentID = folder?.parentID
        for i in folders.indices where folders[i].parentID == id {
            folders[i].parentID = parentID
        }
        folders.removeAll { $0.id == id }
        saveFolders()
    }

    func renameFolder(_ id: UUID, to name: String) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = name
            saveFolders()
        }
    }

    func moveFolder(_ id: UUID, toParent parentID: UUID?) {
        // Prevent circular dependency: walk up from parentID to ensure id is not an ancestor
        if let targetParent = parentID {
            var current: UUID? = targetParent
            while let cur = current {
                if cur == id { return } // Would create a cycle
                current = folders.first(where: { $0.id == cur })?.parentID
            }
        }
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].parentID = parentID
            saveFolders()
        }
    }

    func childFolders(of parentID: UUID?) -> [FolderNode] {
        folders.filter { $0.parentID == parentID }.sorted { $0.position < $1.position }
    }

    // MARK: - Auto-split algorithms

    enum SplitMode: String, CaseIterable {
        case alphabetic = "Alphabetic"
        case genre = "By Genre"
        case region = "By Region"
        case system = "By System"
        case equal = "Equal Split"
    }

    /// Auto-split games into folders, returning updated games with folder assignments.
    func autoSplit(games: inout [Game], mode: SplitMode, maxPerFolder: Int = 30) {
        // Clear existing auto-generated folders
        folders.removeAll()

        switch mode {
        case .alphabetic:
            splitAlphabetic(games: &games, maxPerFolder: maxPerFolder)
        case .genre:
            splitByField(games: &games, keyPath: \.genre, defaultValue: "Other")
        case .region:
            splitByField(games: &games, keyPath: \.region, defaultValue: "USA")
        case .system:
            splitByField(games: &games, keyPath: \.consoleType.systemFamily, defaultValue: "Other")
        case .equal:
            splitEqual(games: &games, maxPerFolder: maxPerFolder)
        }

        saveFolders()
    }

    private func splitAlphabetic(games: inout [Game], maxPerFolder: Int) {
        let sorted = games.sorted { $0.sortName.lowercased() < $1.sortName.lowercased() }
        var currentLetter = ""
        var currentFolder: FolderNode?
        var count = 0

        for game in sorted {
            let firstLetter = String(game.sortName.prefix(1)).uppercased()
            let letter = firstLetter.first?.isLetter == true ? firstLetter : "#"

            if letter != currentLetter || count >= maxPerFolder {
                currentLetter = letter
                count = 0
                let folder = createFolder(name: letter)
                currentFolder = folder
            }

            if let index = games.firstIndex(where: { $0.id == game.id }) {
                games[index].folder = currentFolder?.id.uuidString ?? "/"
            }
            count += 1
        }
    }

    private func splitByField(games: inout [Game], keyPath: KeyPath<Game, String>, defaultValue: String) {
        var groups: [String: UUID] = [:]

        for i in games.indices {
            let value = games[i][keyPath: keyPath]
            let key = value.isEmpty ? defaultValue : value

            if groups[key] == nil {
                let folder = createFolder(name: key)
                groups[key] = folder.id
            }

            guard let folderID = groups[key] else { continue }
            games[i].folder = folderID.uuidString
        }
    }

    private func splitEqual(games: inout [Game], maxPerFolder: Int) {
        let totalFolders = max(1, (games.count + maxPerFolder - 1) / maxPerFolder)

        for folderIdx in 0..<totalFolders {
            let folder = createFolder(name: "Page \(folderIdx + 1)")
            let startIdx = folderIdx * maxPerFolder
            let endIdx = min(startIdx + maxPerFolder, games.count)

            for i in startIdx..<endIdx {
                games[i].folder = folder.id.uuidString
            }
        }
    }

    // MARK: - Sync support

    /// Generate .desktop files for folders during console sync.
    func generateFolderDesktopFiles(basePath: String) -> [(path: String, content: String)] {
        var results: [(String, String)] = []

        for folder in folders {
            let code = "CLV-F-\(folder.id.uuidString.prefix(5).uppercased())"
            let path = "\(basePath)/\(code)/\(code).desktop"
            let content = """
            [Desktop Entry]
            Type=Folder
            Name=\(folder.name)
            Icon=/usr/share/games/\(code)/\(code).png
            SortPriority=\(String(format: "%03d", folder.position))
            """
            results.append((path, content))
        }

        return results
    }

    // MARK: - Persistence

    func loadFolders() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            folders = try JSONDecoder().decode([FolderNode].self, from: data)
        } catch {
            HakchiLogger.games.error("Failed to load folders: \(error.localizedDescription)")
        }
    }

    func saveFolders() {
        FileUtils.ensureDirectoriesExist()
        do {
            let data = try JSONEncoder().encode(folders)
            try data.write(to: saveURL)
        } catch {
            HakchiLogger.games.error("Failed to save folders: \(error.localizedDescription)")
        }
    }
}

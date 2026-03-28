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

    /// Sequential folder index counter for deterministic CLV-S-XXXXX codes (matching C#).
    private var folderIndex = 0

    /// Generate folder CLV code using sequential numbering (matching C# NesMenuFolder).
    private func nextFolderCode() -> String {
        folderIndex += 1
        return "CLV-S-\(String(format: "%05d", folderIndex))"
    }

    /// Generate .desktop files for folders during console sync.
    /// Includes back-navigation entries so users can navigate up from subfolders.
    func generateFolderDesktopFiles(basePath: String) -> [(path: String, content: String)] {
        var results: [(String, String)] = []
        folderIndex = 0

        for folder in folders {
            let code = nextFolderCode()
            let path = "\(basePath)/\(code)/\(code).desktop"

            // Cyrillic prefix for sort ordering (matching C#: folders sort before games)
            let sortPrefix = "\u{0410}" // Cyrillic "А" sorts before ASCII

            var lines: [String] = []
            lines.append("[Desktop Entry]")
            lines.append("Type=Application")
            lines.append("Exec=/bin/chmenu \(code)")
            lines.append("Path=/var/lib/clover/profiles/0/\(code)")
            lines.append("Name=\(folder.name)")
            lines.append("Icon=/usr/share/games/\(code)/\(code).png")
            lines.append("")
            lines.append("[X-CLOVER Game]")
            lines.append("Code=\(code)")
            lines.append("TestID=777")
            lines.append("ID=0")
            lines.append("Players=1")
            lines.append("Simultaneous=0")
            lines.append("ReleaseDate=0000-00-00")
            lines.append("SaveCount=0")
            lines.append("SortRawTitle=\(sortPrefix)\(String(format: "%03d", folder.position))")
            lines.append("SortRawPublisher=")
            lines.append("Copyright=")

            results.append((path, lines.joined(separator: "\n")))

            // Generate "Back" entry for this folder (critical for navigation)
            let backCode = nextFolderCode()
            let backPath = "\(basePath)/\(code)/\(backCode).desktop"

            var backLines: [String] = []
            backLines.append("[Desktop Entry]")
            backLines.append("Type=Application")
            backLines.append("Exec=/bin/chmenu \(folder.parentID?.uuidString ?? "000")")
            backLines.append("Path=/var/lib/clover/profiles/0/\(backCode)")
            backLines.append("Name=..")
            backLines.append("Icon=/usr/share/games/\(backCode)/\(backCode).png")
            backLines.append("")
            backLines.append("[X-CLOVER Game]")
            backLines.append("Code=\(backCode)")
            backLines.append("TestID=777")
            backLines.append("ID=0")
            backLines.append("Players=1")
            backLines.append("Simultaneous=0")
            backLines.append("ReleaseDate=0000-00-00")
            backLines.append("SaveCount=0")
            backLines.append("SortRawTitle=\u{0409}") // Sorts first (before folder content)
            backLines.append("SortRawPublisher=")
            backLines.append("Copyright=")

            results.append((backPath, backLines.joined(separator: "\n")))
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

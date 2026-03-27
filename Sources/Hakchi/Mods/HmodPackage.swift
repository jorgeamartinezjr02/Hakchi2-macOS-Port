import Foundation

struct HmodPackage {
    let name: String
    let version: String
    let author: String
    let description: String
    let category: ModCategory
    let url: URL
    let fileSize: Int64

    var hasInstallScript: Bool
    var hasUninstallScript: Bool

    init(url: URL) throws {
        self.url = url
        self.fileSize = FileUtils.fileSize(at: url)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Extract the hmod
        try FileUtils.extractTarGz(at: url, to: tempDir)

        // Find the hmod root directory
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let hmodRoot = contents.first ?? tempDir

        // Parse metadata
        let readmePath = hmodRoot.appendingPathComponent("readme.md")
        let readmeAltPath = hmodRoot.appendingPathComponent("README.md")
        let readme: String
        if FileManager.default.fileExists(atPath: readmePath.path) {
            readme = (try? String(contentsOf: readmePath)) ?? ""
        } else if FileManager.default.fileExists(atPath: readmeAltPath.path) {
            readme = (try? String(contentsOf: readmeAltPath)) ?? ""
        } else {
            readme = ""
        }

        // Parse name from directory or readme
        let dirName = hmodRoot.lastPathComponent
        if dirName.hasSuffix(".hmod") {
            self.name = String(dirName.dropLast(5))
        } else {
            self.name = dirName
        }

        // Parse version, author from readme
        var parsedVersion = "1.0"
        var parsedAuthor = ""
        var parsedDescription = ""
        var parsedCategory = ModCategory.other

        for line in readme.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("version:") {
                parsedVersion = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("author:") {
                parsedAuthor = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("category:") {
                let cat = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces).lowercased()
                if cat.contains("emulator") { parsedCategory = .emulator }
                else if cat.contains("retroarch") { parsedCategory = .retroarch }
                else if cat.contains("ui") { parsedCategory = .ui }
                else if cat.contains("system") { parsedCategory = .system }
            } else if parsedDescription.isEmpty && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                parsedDescription = trimmed
            }
        }

        self.version = parsedVersion
        self.author = parsedAuthor
        self.description = parsedDescription
        self.category = parsedCategory

        // Check for install/uninstall scripts
        let installPath = hmodRoot.appendingPathComponent("install")
        let uninstallPath = hmodRoot.appendingPathComponent("uninstall")
        self.hasInstallScript = FileManager.default.fileExists(atPath: installPath.path)
        self.hasUninstallScript = FileManager.default.fileExists(atPath: uninstallPath.path)

        HakchiLogger.mods.info("Parsed hmod: \(self.name) v\(self.version) by \(self.author)")
    }

    func toMod() -> Mod {
        Mod(
            name: name,
            version: version,
            author: author,
            description: description,
            category: category,
            filePath: url.path,
            isInstalled: false,
            fileSize: fileSize
        )
    }
}

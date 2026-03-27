import Foundation

struct ModRepositoryEntry: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let author: String
    let description: String
    let category: String
    let downloadURL: String
    let fileSize: Int64
}

final class ModRepository {
    static let shared = ModRepository()

    private var entries: [ModRepositoryEntry] = []

    private init() {
        loadBuiltInMods()
    }

    func getAvailableMods() -> [ModRepositoryEntry] {
        return entries
    }

    func getModsByCategory(_ category: String) -> [ModRepositoryEntry] {
        return entries.filter { $0.category.lowercased() == category.lowercased() }
    }

    func searchMods(_ query: String) -> [ModRepositoryEntry] {
        let lowered = query.lowercased()
        return entries.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.description.lowercased().contains(lowered) ||
            $0.author.lowercased().contains(lowered)
        }
    }

    private func loadBuiltInMods() {
        // Common hakchi mods that users typically install
        entries = [
            ModRepositoryEntry(
                id: "retroarch",
                name: "RetroArch",
                version: "1.9.0",
                author: "Team Shinkansen",
                description: "Multi-system emulator frontend for running additional console ROMs",
                category: "Emulator",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "fceumm",
                name: "FCEUmm (NES Emulator)",
                version: "1.0",
                author: "libretro",
                description: "Enhanced NES/Famicom emulator core for RetroArch",
                category: "Emulator",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "snes9x2010",
                name: "Snes9x 2010",
                version: "1.0",
                author: "libretro",
                description: "SNES emulator core for RetroArch",
                category: "Emulator",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "genesis_plus_gx",
                name: "Genesis Plus GX",
                version: "1.0",
                author: "libretro",
                description: "Sega Genesis/Mega Drive emulator core",
                category: "Emulator",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "gambatte",
                name: "Gambatte (Game Boy)",
                version: "1.0",
                author: "libretro",
                description: "Game Boy / Game Boy Color emulator core",
                category: "Emulator",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "font_hack",
                name: "Font Hack",
                version: "1.0",
                author: "ClusterM",
                description: "Replaces system font to support extended characters",
                category: "UI Enhancement",
                downloadURL: "",
                fileSize: 0
            ),
            ModRepositoryEntry(
                id: "usb_storage",
                name: "USB Storage",
                version: "1.0",
                author: "Team Shinkansen",
                description: "Enables loading games from external USB storage",
                category: "System",
                downloadURL: "",
                fileSize: 0
            ),
        ]
    }
}

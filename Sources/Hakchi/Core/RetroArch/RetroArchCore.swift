import Foundation

/// Represents a RetroArch libretro core that can emulate specific systems.
struct RetroArchCore: Identifiable, Codable, Hashable {
    let id: String          // e.g. "fceumm", "snes9x2010"
    let name: String        // Display name
    let systems: [String]   // Supported system families: "NES", "SNES", "Genesis", etc.
    let extensions: [String] // ROM extensions this core handles
    let binaryName: String  // filename on console: e.g. "fceumm_libretro.so"

    var binaryPath: String {
        "/usr/share/libretro/\(binaryName)"
    }
}

/// Manages the mapping between ROM systems and RetroArch cores.
final class CoreManager {
    static let shared = CoreManager()

    private let cores: [RetroArchCore]
    private let defaultCoreMap: [String: String] // system -> default core id

    private init() {
        cores = Self.builtInCores()
        defaultCoreMap = [
            "NES": "fceumm",
            "SNES": "snes9x2010",
            "Genesis": "genesis_plus_gx",
            "GB": "gambatte",
            "GBC": "gambatte",
            "GBA": "mgba",
            "TG16": "mednafen_pce_fast",
            "SMS": "genesis_plus_gx",
            "GG": "genesis_plus_gx",
            "N64": "mupen64plus_next",
            "PS1": "pcsx_rearmed",
            "NGP": "mednafen_ngp",
            "Atari2600": "stella",
            "Arcade": "fbalpha2012",
        ]
    }

    /// Get all available cores
    func getAllCores() -> [RetroArchCore] {
        cores
    }

    /// Get cores that support a given system
    func cores(for system: String) -> [RetroArchCore] {
        cores.filter { $0.systems.contains(system) }
    }

    /// Get the default core ID for a system
    func defaultCoreID(for system: String) -> String? {
        defaultCoreMap[system]
    }

    /// Get the default core for a system
    func defaultCore(for system: String) -> RetroArchCore? {
        guard let id = defaultCoreMap[system] else { return nil }
        return cores.first { $0.id == id }
    }

    /// Get a core by its ID
    func core(byID id: String) -> RetroArchCore? {
        cores.first { $0.id == id }
    }

    /// Detect the system from a file extension
    func detectSystem(for ext: String) -> String? {
        let ext = ext.lowercased()
        switch ext {
        case "nes", "fds", "unf", "unif": return "NES"
        case "sfc", "smc", "fig", "swc": return "SNES"
        case "md", "smd", "gen", "bin": return "Genesis"
        case "gb": return "GB"
        case "gbc": return "GBC"
        case "gba": return "GBA"
        case "pce": return "TG16"
        case "sms": return "SMS"
        case "gg": return "GG"
        case "n64", "z64", "v64": return "N64"
        case "cue", "iso", "pbp", "chd": return "PS1"
        case "ngp", "ngc": return "NGP"
        case "a26": return "Atari2600"
        default: return nil
        }
    }

    /// Build the exec line for a game with a specific core
    func execLine(coreID: String?, game: Game, gameCode: String) -> String {
        let romFilename = URL(fileURLWithPath: game.romPath).lastPathComponent
        let gamePath = "/usr/share/games/\(gameCode)/\(romFilename)"

        if let coreID = coreID, let core = core(byID: coreID) {
            return "/bin/retroarch \(core.binaryPath) \(gamePath)"
        }

        // Use native emulator for NES/SNES if no core specified
        return "\(game.consoleType.nativeEmulatorPath) \(gamePath)"
    }

    // MARK: - Built-in core definitions

    private static func builtInCores() -> [RetroArchCore] {
        [
            RetroArchCore(
                id: "fceumm",
                name: "FCEUmm (NES)",
                systems: ["NES"],
                extensions: ["nes", "fds", "unf", "unif"],
                binaryName: "fceumm_libretro.so"
            ),
            RetroArchCore(
                id: "nestopia",
                name: "Nestopia UE (NES)",
                systems: ["NES"],
                extensions: ["nes", "fds", "unf", "unif"],
                binaryName: "nestopia_libretro.so"
            ),
            RetroArchCore(
                id: "snes9x2010",
                name: "Snes9x 2010 (SNES)",
                systems: ["SNES"],
                extensions: ["sfc", "smc", "fig", "swc"],
                binaryName: "snes9x2010_libretro.so"
            ),
            RetroArchCore(
                id: "snes9x",
                name: "Snes9x (SNES)",
                systems: ["SNES"],
                extensions: ["sfc", "smc", "fig", "swc"],
                binaryName: "snes9x_libretro.so"
            ),
            RetroArchCore(
                id: "genesis_plus_gx",
                name: "Genesis Plus GX",
                systems: ["Genesis", "SMS", "GG"],
                extensions: ["md", "smd", "gen", "bin", "sms", "gg"],
                binaryName: "genesis_plus_gx_libretro.so"
            ),
            RetroArchCore(
                id: "picodrive",
                name: "PicoDrive (Genesis/32X)",
                systems: ["Genesis"],
                extensions: ["md", "smd", "gen", "bin", "32x"],
                binaryName: "picodrive_libretro.so"
            ),
            RetroArchCore(
                id: "gambatte",
                name: "Gambatte (GB/GBC)",
                systems: ["GB", "GBC"],
                extensions: ["gb", "gbc"],
                binaryName: "gambatte_libretro.so"
            ),
            RetroArchCore(
                id: "mgba",
                name: "mGBA (GBA)",
                systems: ["GBA", "GB", "GBC"],
                extensions: ["gba", "gb", "gbc"],
                binaryName: "mgba_libretro.so"
            ),
            RetroArchCore(
                id: "gpsp",
                name: "gpSP (GBA)",
                systems: ["GBA"],
                extensions: ["gba"],
                binaryName: "gpsp_libretro.so"
            ),
            RetroArchCore(
                id: "mednafen_pce_fast",
                name: "Mednafen PCE Fast (TG16)",
                systems: ["TG16"],
                extensions: ["pce", "cue"],
                binaryName: "mednafen_pce_fast_libretro.so"
            ),
            RetroArchCore(
                id: "mednafen_ngp",
                name: "Mednafen Neo Geo Pocket",
                systems: ["NGP"],
                extensions: ["ngp", "ngc"],
                binaryName: "mednafen_ngp_libretro.so"
            ),
            RetroArchCore(
                id: "pcsx_rearmed",
                name: "PCSX ReARMed (PS1)",
                systems: ["PS1"],
                extensions: ["cue", "iso", "pbp", "chd"],
                binaryName: "pcsx_rearmed_libretro.so"
            ),
            RetroArchCore(
                id: "mupen64plus_next",
                name: "Mupen64Plus-Next (N64)",
                systems: ["N64"],
                extensions: ["n64", "z64", "v64"],
                binaryName: "mupen64plus_next_libretro.so"
            ),
            RetroArchCore(
                id: "stella",
                name: "Stella (Atari 2600)",
                systems: ["Atari2600"],
                extensions: ["a26"],
                binaryName: "stella_libretro.so"
            ),
            RetroArchCore(
                id: "fbalpha2012",
                name: "FB Alpha 2012 (Arcade)",
                systems: ["Arcade"],
                extensions: ["zip"],
                binaryName: "fbalpha2012_libretro.so"
            ),
        ]
    }
}

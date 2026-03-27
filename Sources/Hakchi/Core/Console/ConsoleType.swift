import Foundation

enum ConsoleType: String, Codable, CaseIterable {
    case nesClassic = "NES Classic"
    case snesClassic = "SNES Classic"
    case segaMini = "Sega Mini"
    case unknown = "Unknown"

    var shortName: String {
        switch self {
        case .nesClassic: return "NES"
        case .snesClassic: return "SNES"
        case .segaMini: return "Sega"
        case .unknown: return "???"
        }
    }

    var gamesPath: String {
        switch self {
        case .nesClassic: return "/var/lib/hakchi/games/nes-usa"
        case .snesClassic: return "/var/lib/hakchi/games/snes-usa"
        case .segaMini: return "/var/lib/hakchi/games/sega-usa"
        case .unknown: return "/var/lib/hakchi/games"
        }
    }

    var supportedExtensions: [String] {
        switch self {
        case .nesClassic: return ["nes", "fds", "unf", "unif"]
        case .snesClassic: return ["sfc", "smc", "fig", "swc"]
        case .segaMini: return ["md", "smd", "gen", "bin"]
        case .unknown: return []
        }
    }

    var maxGameSize: Int64 {
        switch self {
        case .nesClassic: return 5 * 1024 * 1024     // 5MB
        case .snesClassic: return 10 * 1024 * 1024    // 10MB
        case .segaMini: return 10 * 1024 * 1024       // 10MB
        case .unknown: return 0
        }
    }
}

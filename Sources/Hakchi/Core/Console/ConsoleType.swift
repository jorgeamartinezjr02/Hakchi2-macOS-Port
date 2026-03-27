import Foundation

// All console variants supported by Hakchi2 CE
enum ConsoleType: String, Codable, CaseIterable, Identifiable {
    // Nintendo NES family
    case nesClassic = "NES Classic"
    case nesClassicEUR = "NES Classic (EUR)"
    case famicomMini = "Famicom Mini"

    // Nintendo SNES family
    case snesClassic = "SNES Classic"
    case snesClassicEUR = "SNES Classic (EUR)"
    case superFamicomMini = "Super Famicom Mini"

    // Sega
    case segaMini = "Sega Genesis Mini"
    case megaDriveMini = "Mega Drive Mini"

    case unknown = "Unknown"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .nesClassic: return "NES"
        case .nesClassicEUR: return "NES (EUR)"
        case .famicomMini: return "FC"
        case .snesClassic: return "SNES"
        case .snesClassicEUR: return "SNES (EUR)"
        case .superFamicomMini: return "SFC"
        case .segaMini: return "Genesis"
        case .megaDriveMini: return "MD"
        case .unknown: return "???"
        }
    }

    var fullName: String { rawValue }

    // Console family grouping
    var family: ConsoleFamily {
        switch self {
        case .nesClassic, .nesClassicEUR, .famicomMini:
            return .nes
        case .snesClassic, .snesClassicEUR, .superFamicomMini:
            return .snes
        case .segaMini, .megaDriveMini:
            return .sega
        case .unknown:
            return .unknown
        }
    }

    var region: ConsoleRegion {
        switch self {
        case .nesClassic, .snesClassic, .segaMini:
            return .usa
        case .nesClassicEUR, .snesClassicEUR, .megaDriveMini:
            return .eur
        case .famicomMini, .superFamicomMini:
            return .jpn
        case .unknown:
            return .usa
        }
    }

    var gamesPath: String {
        switch self {
        case .nesClassic:        return "/var/lib/hakchi/games/nes-usa"
        case .nesClassicEUR:     return "/var/lib/hakchi/games/nes-eur"
        case .famicomMini:       return "/var/lib/hakchi/games/nes-jpn"
        case .snesClassic:       return "/var/lib/hakchi/games/snes-usa"
        case .snesClassicEUR:    return "/var/lib/hakchi/games/snes-eur"
        case .superFamicomMini:  return "/var/lib/hakchi/games/snes-jpn"
        case .segaMini:          return "/var/lib/hakchi/games/sega-usa"
        case .megaDriveMini:     return "/var/lib/hakchi/games/sega-eur"
        case .unknown:           return "/var/lib/hakchi/games"
        }
    }

    var supportedExtensions: [String] {
        switch family {
        case .nes:  return ["nes", "fds", "unf", "unif", "qd"]
        case .snes: return ["sfc", "smc", "fig", "swc", "sfrom"]
        case .sega: return ["md", "smd", "gen", "bin", "sg", "gg"]
        case .unknown: return []
        }
    }

    var maxGameSize: Int64 {
        switch family {
        case .nes:     return 5 * 1024 * 1024     // 5MB
        case .snes:    return 10 * 1024 * 1024     // 10MB
        case .sega:    return 10 * 1024 * 1024     // 10MB
        case .unknown: return 0
        }
    }

    // Stock emulator binary for this console
    var stockEmulator: String {
        switch family {
        case .nes:  return "/bin/clover-kachikachi"
        case .snes: return "/bin/clover-canoe-shvc"
        case .sega: return "/bin/retroarch"
        case .unknown: return "/bin/retroarch"
        }
    }

    // Stock emulator display name
    var stockEmulatorName: String {
        switch family {
        case .nes:  return "Kachikachi (Stock NES)"
        case .snes: return "Canoe (Stock SNES)"
        case .sega: return "M2Engage (Stock Sega)"
        case .unknown: return "RetroArch"
        }
    }

    // NAND storage size
    var nandSize: Int64 {
        switch family {
        case .nes:  return 512 * 1024 * 1024  // 512MB
        case .snes: return 512 * 1024 * 1024
        case .sega: return 512 * 1024 * 1024
        case .unknown: return 256 * 1024 * 1024
        }
    }

    // CLV code prefix per console type (as used by hakchi2 CE)
    var clvPrefix: String {
        switch self {
        case .nesClassic, .nesClassicEUR, .famicomMini: return "CLV-H"
        case .snesClassic: return "CLV-U"
        case .snesClassicEUR: return "CLV-P"
        case .superFamicomMini: return "CLV-S"
        case .segaMini, .megaDriveMini: return "CLV-G"
        case .unknown: return "CLV-Z"
        }
    }

    // Selectable console types (excludes .unknown)
    static var selectableCases: [ConsoleType] {
        allCases.filter { $0 != .unknown }
    }

    // Grouped for picker UI
    static var nesFamily: [ConsoleType] { [.nesClassic, .nesClassicEUR, .famicomMini] }
    static var snesFamily: [ConsoleType] { [.snesClassic, .snesClassicEUR, .superFamicomMini] }
    static var segaFamily: [ConsoleType] { [.segaMini, .megaDriveMini] }
}

enum ConsoleFamily: String, Codable {
    case nes = "NES"
    case snes = "SNES"
    case sega = "Sega"
    case unknown = "Unknown"
}

enum ConsoleRegion: String, Codable {
    case usa = "USA"
    case eur = "EUR"
    case jpn = "JPN"

    var displayName: String {
        switch self {
        case .usa: return "North America"
        case .eur: return "Europe"
        case .jpn: return "Japan"
        }
    }
}

import Foundation

/// A cheat code entry (Game Genie, Action Replay, or RetroArch .cht format).
struct CheatCode: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var code: String
    var type: CheatType
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, code: String, type: CheatType = .gameGenie, isEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.code = code
        self.type = type
        self.isEnabled = isEnabled
    }

    enum CheatType: String, Codable, CaseIterable {
        case gameGenie = "Game Genie"
        case actionReplay = "Action Replay"
        case retroarch = "RetroArch"
    }
}

/// Game Genie code decoder for NES.
enum GameGenieNES {
    /// Decode a 6 or 8-letter NES Game Genie code.
    static func decode(_ code: String) -> (address: UInt16, value: UInt8, compare: UInt8?)? {
        let letters = "APZLGITYEOXUKSVN"
        let code = code.uppercased().filter { $0 != "-" }
        guard code.count == 6 || code.count == 8 else { return nil }

        var values: [UInt8] = []
        for char in code {
            guard let index = letters.firstIndex(of: char) else { return nil }
            values.append(UInt8(letters.distance(from: letters.startIndex, to: index)))
        }

        if code.count == 6 {
            let address = UInt16(0x8000) +
                (UInt16(values[3] & 7) << 12) |
                (UInt16(values[5] & 7) << 8) |
                (UInt16(values[4]) << 4) |
                (UInt16(values[2]) )
            let value = ((values[1] & 7) << 4) |
                ((values[0] & 8) << 0) |
                (values[0] & 7) |
                ((values[5] & 8) << 0)
            return (address, value, nil)
        } else {
            let address = UInt16(0x8000) +
                (UInt16(values[3] & 7) << 12) |
                (UInt16(values[5] & 7) << 8) |
                (UInt16(values[4]) << 4) |
                (UInt16(values[2]))
            let value = ((values[1] & 7) << 4) |
                ((values[0] & 8) << 0) |
                (values[0] & 7) |
                ((values[7] & 8) << 0)
            let compare = ((values[7] & 7) << 4) |
                ((values[6] & 8) << 0) |
                (values[6] & 7) |
                ((values[5] & 8) << 0)
            return (address, value, compare)
        }
    }

    /// Validate a Game Genie code format.
    static func isValid(_ code: String) -> Bool {
        decode(code) != nil
    }
}

/// Game Genie code decoder for SNES.
enum GameGenieSNES {
    /// Decode an 8-character SNES Game Genie code (XXXX-YYYY format).
    static func decode(_ code: String) -> (address: UInt32, value: UInt8)? {
        let clean = code.uppercased().filter { $0 != "-" }
        guard clean.count == 8 else { return nil }
        guard let _ = UInt32(clean, radix: 16) else { return nil }

        // SNES Game Genie uses hex directly with address scrambling
        guard let addr = UInt32(String(clean.prefix(6)), radix: 16),
              let val = UInt8(String(clean.suffix(2)), radix: 16) else { return nil }

        // Unscramble address bits
        let decoded = ((addr & 0x003C00) << 10) |
            ((addr & 0x00003C) << 14) |
            ((addr & 0xF00000) >> 8) |
            ((addr & 0x000003) << 10) |
            ((addr & 0x00C000) >> 6) |
            ((addr & 0x0F0000) >> 12) |
            ((addr & 0x0003C0) >> 6)

        return (decoded, val)
    }

    static func isValid(_ code: String) -> Bool {
        decode(code) != nil
    }
}

/// Manages cheat codes for games.
final class CheatManager {
    static let shared = CheatManager()

    private let cheatsDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("cheats", isDirectory: true)
    }()

    private init() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cheatsDirectory.path) {
            try? fm.createDirectory(at: cheatsDirectory, withIntermediateDirectories: true)
        }
    }

    /// Load cheats for a game.
    func loadCheats(for game: Game) -> [CheatCode] {
        let path = cheatsDirectory.appendingPathComponent("\(game.romCRC32).json")
        guard let data = try? Data(contentsOf: path) else { return [] }
        return (try? JSONDecoder().decode([CheatCode].self, from: data)) ?? []
    }

    /// Save cheats for a game.
    func saveCheats(_ cheats: [CheatCode], for game: Game) {
        let path = cheatsDirectory.appendingPathComponent("\(game.romCRC32).json")
        guard let data = try? JSONEncoder().encode(cheats) else { return }
        try? data.write(to: path)
    }

    /// Generate RetroArch .cht file content for upload to console.
    func generateCHTFile(cheats: [CheatCode]) -> String {
        var lines: [String] = []
        lines.append("cheats = \(cheats.count)")
        for (i, cheat) in cheats.enumerated() {
            lines.append("cheat\(i)_desc = \"\(cheat.name)\"")
            lines.append("cheat\(i)_code = \"\(cheat.code)\"")
            lines.append("cheat\(i)_enable = \(cheat.isEnabled ? "true" : "false")")
        }
        return lines.joined(separator: "\n")
    }

    /// Generate NES native --game-genie-code args.
    func gameGenieArgs(for game: Game) -> String? {
        let cheats = loadCheats(for: game).filter { $0.isEnabled && $0.type == .gameGenie }
        guard !cheats.isEmpty else { return nil }
        return cheats.map { "--game-genie-code \($0.code)" }.joined(separator: " ")
    }
}

import XCTest
@testable import Hakchi

final class GameManagerTests: XCTestCase {
    func testCRC32Calculation() {
        let data = Data("Hello, World!".utf8)
        let crc = CRC32.calculate(data: data)
        XCTAssertEqual(CRC32.hexString(for: crc), "EC4AC3D0")
    }

    func testCRC32EmptyData() {
        let data = Data()
        let crc = CRC32.calculate(data: data)
        XCTAssertEqual(CRC32.hexString(for: crc), "00000000")
    }

    func testROMExtensionDetection() {
        XCTAssertTrue(ROMFile.isSupportedExtension("nes"))
        XCTAssertTrue(ROMFile.isSupportedExtension("sfc"))
        XCTAssertTrue(ROMFile.isSupportedExtension("smc"))
        XCTAssertTrue(ROMFile.isSupportedExtension("md"))
        XCTAssertTrue(ROMFile.isSupportedExtension("fds"))
        XCTAssertTrue(ROMFile.isSupportedExtension("sfrom"))
        XCTAssertTrue(ROMFile.isSupportedExtension("gg"))
        XCTAssertTrue(ROMFile.isSupportedExtension("gb"))
        XCTAssertTrue(ROMFile.isSupportedExtension("gba"))
        XCTAssertFalse(ROMFile.isSupportedExtension("exe"))
        XCTAssertFalse(ROMFile.isSupportedExtension("txt"))
        XCTAssertFalse(ROMFile.isSupportedExtension(""))
    }

    func testConsoleTypeDetection() {
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "nes"), .nesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "fds"), .nesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "sfc"), .snesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "smc"), .snesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "sfrom"), .snesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "md"), .segaMini)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "gen"), .segaMini)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "gg"), .segaMini)
    }

    func testConsoleFamilies() {
        // NES family
        XCTAssertEqual(ConsoleType.nesClassic.family, .nes)
        XCTAssertEqual(ConsoleType.nesClassicEUR.family, .nes)
        XCTAssertEqual(ConsoleType.famicomMini.family, .nes)

        // SNES family
        XCTAssertEqual(ConsoleType.snesClassic.family, .snes)
        XCTAssertEqual(ConsoleType.snesClassicEUR.family, .snes)
        XCTAssertEqual(ConsoleType.superFamicomMini.family, .snes)

        // Sega family
        XCTAssertEqual(ConsoleType.segaMini.family, .sega)
        XCTAssertEqual(ConsoleType.megaDriveMini.family, .sega)
    }

    func testConsoleRegions() {
        XCTAssertEqual(ConsoleType.nesClassic.region, .usa)
        XCTAssertEqual(ConsoleType.nesClassicEUR.region, .eur)
        XCTAssertEqual(ConsoleType.famicomMini.region, .jpn)
        XCTAssertEqual(ConsoleType.snesClassic.region, .usa)
        XCTAssertEqual(ConsoleType.snesClassicEUR.region, .eur)
        XCTAssertEqual(ConsoleType.superFamicomMini.region, .jpn)
        XCTAssertEqual(ConsoleType.segaMini.region, .usa)
        XCTAssertEqual(ConsoleType.megaDriveMini.region, .eur)
    }

    func testConsoleTypePaths() {
        XCTAssertTrue(ConsoleType.nesClassic.gamesPath.contains("nes-usa"))
        XCTAssertTrue(ConsoleType.nesClassicEUR.gamesPath.contains("nes-eur"))
        XCTAssertTrue(ConsoleType.famicomMini.gamesPath.contains("nes-jpn"))
        XCTAssertTrue(ConsoleType.snesClassic.gamesPath.contains("snes-usa"))
        XCTAssertTrue(ConsoleType.snesClassicEUR.gamesPath.contains("snes-eur"))
        XCTAssertTrue(ConsoleType.superFamicomMini.gamesPath.contains("snes-jpn"))
        XCTAssertTrue(ConsoleType.segaMini.gamesPath.contains("sega-usa"))
        XCTAssertTrue(ConsoleType.megaDriveMini.gamesPath.contains("sega-eur"))
    }

    func testCLVCodePrefixes() {
        XCTAssertEqual(ConsoleType.nesClassic.clvPrefix, "CLV-H")
        XCTAssertEqual(ConsoleType.snesClassic.clvPrefix, "CLV-U")
        XCTAssertEqual(ConsoleType.snesClassicEUR.clvPrefix, "CLV-P")
        XCTAssertEqual(ConsoleType.superFamicomMini.clvPrefix, "CLV-S")
        XCTAssertEqual(ConsoleType.segaMini.clvPrefix, "CLV-G")
    }

    func testConsoleTypeSupportedExtensions() {
        // All NES family share same extensions
        XCTAssertEqual(ConsoleType.nesClassic.supportedExtensions, ConsoleType.famicomMini.supportedExtensions)
        XCTAssertTrue(ConsoleType.nesClassic.supportedExtensions.contains("nes"))
        XCTAssertTrue(ConsoleType.nesClassic.supportedExtensions.contains("qd"))

        // All SNES family share same extensions
        XCTAssertEqual(ConsoleType.snesClassic.supportedExtensions, ConsoleType.superFamicomMini.supportedExtensions)
        XCTAssertTrue(ConsoleType.snesClassic.supportedExtensions.contains("sfc"))
        XCTAssertTrue(ConsoleType.snesClassic.supportedExtensions.contains("sfrom"))

        // Sega
        XCTAssertTrue(ConsoleType.segaMini.supportedExtensions.contains("md"))
        XCTAssertTrue(ConsoleType.segaMini.supportedExtensions.contains("gg"))
        XCTAssertTrue(ConsoleType.unknown.supportedExtensions.isEmpty)
    }

    func testGameCreation() {
        let game = Game(
            name: "Test Game",
            publisher: "Test Publisher",
            romPath: "/tmp/test.nes",
            romSize: 262144,
            romCRC32: "ABCD1234",
            consoleType: .nesClassic
        )

        XCTAssertEqual(game.name, "Test Game")
        XCTAssertEqual(game.publisher, "Test Publisher")
        XCTAssertEqual(game.romSize, 262144)
        XCTAssertEqual(game.consoleType, .nesClassic)
        XCTAssertTrue(game.isSelected)
        XCTAssertTrue(game.clvCode.hasPrefix("CLV-H-"))
        XCTAssertEqual(game.clvCode.count, 11) // CLV-H-XXXXX
    }

    func testGameCLVCodeGeneration() {
        let nesGame = Game(name: "NES Game", romPath: "/tmp/test.nes", consoleType: .nesClassic)
        XCTAssertTrue(nesGame.clvCode.hasPrefix("CLV-H-"))

        let snesGame = Game(name: "SNES Game", romPath: "/tmp/test.sfc", consoleType: .snesClassic)
        XCTAssertTrue(snesGame.clvCode.hasPrefix("CLV-U-"))

        let sfcGame = Game(name: "SFC Game", romPath: "/tmp/test.sfc", consoleType: .superFamicomMini)
        XCTAssertTrue(sfcGame.clvCode.hasPrefix("CLV-S-"))

        let eurGame = Game(name: "EUR Game", romPath: "/tmp/test.sfc", consoleType: .snesClassicEUR)
        XCTAssertTrue(eurGame.clvCode.hasPrefix("CLV-P-"))
    }

    func testGameDatabaseLookup() {
        let db = GameDatabase.shared

        let smb = db.lookup(crc32: "3FE272FB")
        XCTAssertNotNil(smb)
        XCTAssertEqual(smb?.name, "Super Mario Bros.")

        let zelda = db.lookup(crc32: "0B742B3A")
        XCTAssertNotNil(zelda)
        XCTAssertEqual(zelda?.name, "The Legend of Zelda")

        let unknown = db.lookup(crc32: "FFFFFFFF")
        XCTAssertNil(unknown)
    }

    func testGameManagerTotalSize() {
        let manager = GameManager()
        let games = [
            Game(name: "Game 1", romPath: "/tmp/1.nes", romSize: 1024),
            Game(name: "Game 2", romPath: "/tmp/2.nes", romSize: 2048),
            Game(name: "Game 3", romPath: "/tmp/3.nes", romSize: 4096),
        ]

        // Total includes block-aligned ROM + desktop + cover art estimates
        let total = manager.calculateTotalSize(games: games)
        XCTAssertGreaterThan(total, 7168) // Must be >= raw ROM sizes
        XCTAssertEqual(manager.calculateTotalSize(games: []), 0)
    }

    func testDeterministicCLVCodes() {
        // Same CRC32 should always produce the same CLV code
        let code1 = Game.generateCLVCode(consoleType: .nesClassic, crc32: 0x3FE272FB)
        let code2 = Game.generateCLVCode(consoleType: .nesClassic, crc32: 0x3FE272FB)
        XCTAssertEqual(code1, code2)
        XCTAssertTrue(code1.hasPrefix("CLV-H-"))
        XCTAssertEqual(code1.count, 11)

        // Different CRC32 should produce different codes
        let code3 = Game.generateCLVCode(consoleType: .nesClassic, crc32: 0x0B742B3A)
        XCTAssertNotEqual(code1, code3)

        // Different console type same CRC should have different prefix
        let code4 = Game.generateCLVCode(consoleType: .snesClassic, crc32: 0x3FE272FB)
        XCTAssertTrue(code4.hasPrefix("CLV-U-"))
    }

    func testFolderManagerSplitModes() {
        let manager = FolderManager.shared
        var games = [
            Game(name: "Alpha", romPath: "/tmp/a.nes", consoleType: .nesClassic, genre: "Action"),
            Game(name: "Beta", romPath: "/tmp/b.sfc", consoleType: .snesClassic, genre: "RPG"),
            Game(name: "Gamma", romPath: "/tmp/c.md", consoleType: .segaMini, genre: "Action"),
        ]

        // Genre split creates one folder per genre
        manager.autoSplit(games: &games, mode: .genre)
        XCTAssertGreaterThanOrEqual(manager.folders.count, 2)

        // Equal split creates pages
        manager.autoSplit(games: &games, mode: .equal, maxPerFolder: 2)
        XCTAssertGreaterThanOrEqual(manager.folders.count, 2)
    }

    func testSelectableCases() {
        let selectable = ConsoleType.selectableCases
        XCTAssertFalse(selectable.contains(.unknown))
        XCTAssertEqual(selectable.count, 8)
    }
}

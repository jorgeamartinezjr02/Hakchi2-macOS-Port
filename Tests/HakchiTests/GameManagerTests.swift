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
        XCTAssertFalse(ROMFile.isSupportedExtension("exe"))
        XCTAssertFalse(ROMFile.isSupportedExtension("txt"))
        XCTAssertFalse(ROMFile.isSupportedExtension(""))
    }

    func testConsoleTypeDetection() {
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "nes"), .nesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "fds"), .nesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "sfc"), .snesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "smc"), .snesClassic)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "md"), .segaMini)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "gen"), .segaMini)
        XCTAssertEqual(ROMFile.detectConsoleType(extension: "xyz"), .unknown)
    }

    func testConsoleTypePaths() {
        XCTAssertTrue(ConsoleType.nesClassic.gamesPath.contains("nes"))
        XCTAssertTrue(ConsoleType.snesClassic.gamesPath.contains("snes"))
        XCTAssertTrue(ConsoleType.segaMini.gamesPath.contains("sega"))
    }

    func testConsoleTypeSupportedExtensions() {
        XCTAssertTrue(ConsoleType.nesClassic.supportedExtensions.contains("nes"))
        XCTAssertTrue(ConsoleType.snesClassic.supportedExtensions.contains("sfc"))
        XCTAssertTrue(ConsoleType.segaMini.supportedExtensions.contains("md"))
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
    }

    func testGameDatabaseLookup() {
        let db = GameDatabase.shared

        // Built-in entries should exist
        let smb = db.lookup(crc32: "3FE272FB")
        XCTAssertNotNil(smb)
        XCTAssertEqual(smb?.name, "Super Mario Bros.")

        let zelda = db.lookup(crc32: "0B742B3A")
        XCTAssertNotNil(zelda)
        XCTAssertEqual(zelda?.name, "The Legend of Zelda")

        // Non-existent CRC should return nil
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

        XCTAssertEqual(manager.calculateTotalSize(games: games), 7168)
        XCTAssertEqual(manager.calculateTotalSize(games: []), 0)
    }
}

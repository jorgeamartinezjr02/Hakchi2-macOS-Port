import XCTest
@testable import Hakchi

final class HmodTests: XCTestCase {
    func testModCategoryValues() {
        XCTAssertEqual(ModCategory.emulator.rawValue, "Emulator")
        XCTAssertEqual(ModCategory.retroarch.rawValue, "RetroArch")
        XCTAssertEqual(ModCategory.ui.rawValue, "UI Enhancement")
        XCTAssertEqual(ModCategory.system.rawValue, "System")
        XCTAssertEqual(ModCategory.other.rawValue, "Other")
    }

    func testModCreation() {
        let mod = Mod(
            name: "RetroArch",
            version: "1.9.0",
            author: "Team Shinkansen",
            description: "Multi-system emulator frontend",
            category: .emulator,
            filePath: "/tmp/retroarch.hmod"
        )

        XCTAssertEqual(mod.name, "RetroArch")
        XCTAssertEqual(mod.version, "1.9.0")
        XCTAssertEqual(mod.category, .emulator)
        XCTAssertFalse(mod.isInstalled)
    }

    func testModRepository() {
        let repo = ModRepository.shared
        let mods = repo.getAvailableMods()

        XCTAssertFalse(mods.isEmpty)
        XCTAssertTrue(mods.contains { $0.name == "RetroArch" })
    }

    func testModRepositorySearch() {
        let repo = ModRepository.shared

        let results = repo.searchMods("retroarch")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy {
            $0.name.lowercased().contains("retroarch") ||
            $0.description.lowercased().contains("retroarch")
        })

        let emptyResults = repo.searchMods("nonexistentmod12345")
        XCTAssertTrue(emptyResults.isEmpty)
    }

    func testModRepositoryCategory() {
        let repo = ModRepository.shared

        let emulators = repo.getModsByCategory("Emulator")
        XCTAssertFalse(emulators.isEmpty)
        XCTAssertTrue(emulators.allSatisfy { $0.category == "Emulator" })
    }

    func testConsoleState() {
        XCTAssertEqual(ConsoleState.disconnected.displayName, "Disconnected")
        XCTAssertEqual(ConsoleState.felMode.displayName, "FEL Mode")
        XCTAssertEqual(ConsoleState.connected.displayName, "Connected")
        XCTAssertEqual(ConsoleState.busy.displayName, "Busy")
    }

    func testBootImageParsing() {
        // Create a minimal valid boot image
        var data = Data(count: 4096)

        // Magic "ANDROID!"
        let magic = "ANDROID!".data(using: .ascii)!
        data.replaceSubrange(0..<8, with: magic)

        // Kernel size = 1024
        data.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32(1024).littleEndian) { Data($0) })
        // Kernel addr
        data.replaceSubrange(12..<16, with: withUnsafeBytes(of: UInt32(0x40008000).littleEndian) { Data($0) })
        // Ramdisk size = 512
        data.replaceSubrange(16..<20, with: withUnsafeBytes(of: UInt32(512).littleEndian) { Data($0) })
        // Ramdisk addr
        data.replaceSubrange(20..<24, with: withUnsafeBytes(of: UInt32(0x41000000).littleEndian) { Data($0) })
        // Page size = 2048
        data.replaceSubrange(36..<40, with: withUnsafeBytes(of: UInt32(2048).littleEndian) { Data($0) })

        let image = BootImage(data: data)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.kernelSize, 1024)
        XCTAssertEqual(image?.kernelAddr, 0x40008000)
        XCTAssertEqual(image?.ramdiskSize, 512)
        XCTAssertEqual(image?.pageSize, 2048)
    }

    func testHakchiError() {
        let error = HakchiError.deviceNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("NES/SNES Classic"))

        let romError = HakchiError.romNotSupported("xyz")
        XCTAssertTrue(romError.errorDescription!.contains("xyz"))
    }

    func testFileUtilsDirectoryPaths() {
        XCTAssertTrue(FileUtils.hakchiDirectory.path.contains("Hakchi"))
        XCTAssertTrue(FileUtils.gamesDirectory.path.contains("games"))
        XCTAssertTrue(FileUtils.modsDirectory.path.contains("mods"))
        XCTAssertTrue(FileUtils.kernelBackupDirectory.path.contains("kernel_backup"))
    }
}

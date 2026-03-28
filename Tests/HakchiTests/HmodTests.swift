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

        let controllers = repo.getModsByCategory("Controller")
        XCTAssertFalse(controllers.isEmpty)

        let system = repo.getModsByCategory("System")
        XCTAssertFalse(system.isEmpty)
    }

    func testModRepositoryAvailableMods() {
        let repo = ModRepository.shared
        let allMods = repo.getAvailableMods()
        XCTAssertFalse(allMods.isEmpty)
    }

    func testConsoleState() {
        XCTAssertEqual(ConsoleState.disconnected.displayName, "Disconnected")
        XCTAssertEqual(ConsoleState.felMode.displayName, "FEL Mode")
        XCTAssertEqual(ConsoleState.connected.displayName, "Connected")
        XCTAssertEqual(ConsoleState.busy.displayName, "Busy")
    }

    func testBootImageParsing() {
        // Create a valid boot image with page size 2048, kernel 1024, ramdisk 512
        // Layout: header page (2048) + kernel page (2048) + ramdisk page (2048) = 6144 bytes
        let pageSize: UInt32 = 2048
        let kernelSize: UInt32 = 1024
        let ramdiskSize: UInt32 = 512
        var data = Data(count: Int(pageSize) * 3)

        // Write header fields as little-endian bytes
        func writeU32(_ value: UInt32, at offset: Int) {
            data[offset] = UInt8(value & 0xFF)
            data[offset+1] = UInt8((value >> 8) & 0xFF)
            data[offset+2] = UInt8((value >> 16) & 0xFF)
            data[offset+3] = UInt8((value >> 24) & 0xFF)
        }

        // Magic "ANDROID!"
        let magic: [UInt8] = Array("ANDROID!".utf8)
        data.replaceSubrange(0..<8, with: magic)
        writeU32(kernelSize, at: 8)
        writeU32(0x40008000, at: 12)
        writeU32(ramdiskSize, at: 16)
        writeU32(0x41000000, at: 20)
        writeU32(pageSize, at: 36)

        let image = BootImage(data: data)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.kernelSize, kernelSize)
        XCTAssertEqual(image?.kernelAddr, 0x40008000)
        XCTAssertEqual(image?.ramdiskSize, ramdiskSize)
        XCTAssertEqual(image?.pageSize, pageSize)
    }

    func testHakchiError() {
        let error = HakchiError.deviceNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("compatible console"))

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

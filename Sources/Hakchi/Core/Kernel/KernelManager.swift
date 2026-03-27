import Foundation

actor KernelManager {
    private let felDevice: FELDevice

    init(felDevice: FELDevice = FELDevice()) {
        self.felDevice = felDevice
    }

    func dumpKernel(progress: ((Double, String) -> Void)? = nil) async throws -> Data {
        HakchiLogger.kernel.info("Starting kernel dump")

        try felDevice.open()
        defer { felDevice.close() }

        let version = try felDevice.getVersion()
        HakchiLogger.kernel.info("Connected to: \(version.description)")

        progress?(0.05, "Reading kernel from flash...")

        let kernelData = try felDevice.readMemoryWithProgress(
            address: FELConstants.kernelOffset,
            length: FELConstants.kernelMaxSize,
            progress: { value, msg in
                progress?(0.05 + value * 0.9, msg)
            }
        )

        progress?(0.95, "Verifying kernel data...")

        guard isValidKernel(kernelData) else {
            throw HakchiError.kernelDumpFailed("Invalid kernel data received")
        }

        progress?(1.0, "Kernel dump complete")
        HakchiLogger.kernel.info("Kernel dump successful: \(kernelData.count) bytes")
        return kernelData
    }

    func dumpKernelToFile(path: URL, progress: ((Double, String) -> Void)? = nil) async throws {
        let data = try await dumpKernel(progress: progress)
        try data.write(to: path)
        HakchiLogger.kernel.info("Kernel saved to: \(path.path)")
    }

    func flashKernel(data: Data, progress: ((Double, String) -> Void)? = nil) async throws {
        HakchiLogger.kernel.info("Starting kernel flash (\(data.count) bytes)")

        guard isValidKernel(data) else {
            throw HakchiError.kernelFlashFailed("Invalid kernel image")
        }

        guard data.count <= FELConstants.kernelMaxSize else {
            throw HakchiError.kernelFlashFailed("Kernel too large: \(data.count) bytes (max: \(FELConstants.kernelMaxSize))")
        }

        try felDevice.open()
        defer { felDevice.close() }

        progress?(0.05, "Verifying device...")
        _ = try felDevice.getVersion()

        progress?(0.1, "Writing kernel to flash...")

        try felDevice.writeMemoryWithProgress(
            address: FELConstants.kernelOffset,
            data: data,
            progress: { value, msg in
                progress?(0.1 + value * 0.85, msg)
            }
        )

        progress?(0.95, "Verifying write...")

        let verify = try felDevice.readMemory(
            address: FELConstants.kernelOffset,
            length: min(1024, UInt32(data.count))
        )

        guard verify.prefix(1024) == data.prefix(1024) else {
            throw HakchiError.kernelFlashFailed("Verification failed - data mismatch")
        }

        progress?(1.0, "Kernel flash complete")
        HakchiLogger.kernel.info("Kernel flash successful")
    }

    func flashKernelFromFile(path: URL, progress: ((Double, String) -> Void)? = nil) async throws {
        let data = try Data(contentsOf: path)
        try await flashKernel(data: data, progress: progress)
    }

    func backupKernel(progress: ((Double, String) -> Void)? = nil) async throws -> URL {
        FileUtils.ensureDirectoriesExist()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "kernel_backup_\(formatter.string(from: Date())).img"
        let backupPath = FileUtils.kernelBackupDirectory.appendingPathComponent(filename)

        try await dumpKernelToFile(path: backupPath, progress: progress)

        HakchiLogger.kernel.info("Kernel backed up to: \(backupPath.path)")
        return backupPath
    }

    func restoreKernel(from backupPath: URL, progress: ((Double, String) -> Void)? = nil) async throws {
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw HakchiError.kernelFlashFailed("Backup file not found: \(backupPath.path)")
        }

        try await flashKernelFromFile(path: backupPath, progress: progress)
        HakchiLogger.kernel.info("Kernel restored from: \(backupPath.path)")
    }

    func listBackups() -> [URL] {
        let fm = FileManager.default
        let path = FileUtils.kernelBackupDirectory
        guard let files = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "img" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
    }

    private func isValidKernel(_ data: Data) -> Bool {
        guard data.count >= 64 else { return false }
        // Check for Android boot image magic
        let magic = String(data: data.prefix(8), encoding: .ascii) ?? ""
        if magic.hasPrefix("ANDROID!") { return true }
        // Check for uImage magic (0x27051956)
        if data[0] == 0x27 && data[1] == 0x05 && data[2] == 0x19 && data[3] == 0x56 { return true }
        // Check for raw kernel (ARM branch instruction)
        if data[0] == 0x00 && data.count > 1024 { return true }
        return false
    }
}

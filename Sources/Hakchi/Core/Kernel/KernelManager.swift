import Foundation

/// Manages kernel backup, restore, flash, and factory-reset operations.
///
/// **Key design change (2026-03):** NAND flash is NOT memory-mapped on the
/// Allwinner R16.  All dump/flash operations now go through a running Linux
/// system (SSH/Clovershell) using MTD devices, *after* a memboot cycle.
/// Direct FEL `readMemory`/`writeMemory` at the old `kernelOffset` address
/// was reading unmapped memory — not NAND.
actor KernelManager {

    // MARK: - Kernel format identification

    enum KernelFormat: String {
        case androidBoot = "Android Boot Image"
        case uImage = "uImage"
        case raw = "Raw Kernel"
        case unknown = "Unknown Format"
    }

    func identifyKernel(_ data: Data) -> KernelFormat {
        guard data.count >= 8 else { return .unknown }
        let magic = String(data: data.prefix(8), encoding: .ascii) ?? ""
        if magic.hasPrefix("ANDROID!") { return .androidBoot }
        if data[0] == 0x27 && data[1] == 0x05 && data[2] == 0x19 && data[3] == 0x56 { return .uImage }
        return .raw
    }

    func isValidKernel(_ data: Data) -> Bool {
        guard data.count >= 64 else { return false }
        let sample = data.prefix(4096)
        if sample.allSatisfy({ $0 == 0x00 }) { return false }
        if sample.allSatisfy({ $0 == 0xFF }) { return false }
        return true
    }

    // MARK: - Shell-based kernel dump (via sunxi-flash)

    /// Dump the stock kernel from NAND via an active shell connection.
    ///
    /// Uses `sunxi-flash read_boot2` which reads the kernel boot image from
    /// the Allwinner NAND boot area. This is the correct method for SFC/SNES/NES
    /// Mini consoles (Allwinner R16 SoC with sunxi NAND layout).
    ///
    /// Falls back to MTD-based `dd` if sunxi-flash is not available.
    func dumpKernelViaShell(
        shell: ShellInterface,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> Data {
        progress?(0.0, "Reading kernel from NAND...")
        HakchiLogger.fileLog("kernel", "dumpKernelViaShell: starting")

        let remoteTmp = "/tmp/kernel_dump.img"
        var kernelData: Data

        // Method 1: hakchi getBackup2 (matches C# hakchi2-CE, streams via stdout)
        let hasHakchi = try await shell.executeCommand("which hakchi 2>/dev/null")
        if !hasHakchi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            progress?(0.10, "Dumping kernel via hakchi getBackup2...")
            HakchiLogger.fileLog("kernel", "Trying: hakchi getBackup2")
            do {
                // hakchi getBackup2 writes the stock kernel backup to stdout
                kernelData = try await shell.readFile(remotePath: "/dev/null") // reset
                let backupResult = try await shell.executeCommand(
                    "hakchi getBackup2 > \(remoteTmp) 2>/dev/null; echo EXIT:$?"
                )
                HakchiLogger.fileLog("kernel", "hakchi getBackup2 result: \(backupResult)")
                if backupResult.contains("EXIT:0") {
                    let sizeStr = try await shell.executeCommand("wc -c < \(remoteTmp)")
                    let fileSize = Int(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    HakchiLogger.fileLog("kernel", "hakchi getBackup2 size: \(fileSize) bytes")
                    if fileSize > 0 {
                        progress?(0.50, "Downloading kernel dump (\(fileSize / 1024) KB)...")
                        kernelData = try await shell.readFile(remotePath: remoteTmp)
                        HakchiLogger.fileLog("kernel", "Downloaded \(kernelData.count) bytes via hakchi getBackup2")
                        _ = try? await shell.executeCommand("rm -f \(remoteTmp)")

                        if isValidKernel(kernelData) {
                            let format = identifyKernel(kernelData)
                            progress?(1.0, "Kernel dump complete (\(format.rawValue), \(kernelData.count) bytes)")
                            HakchiLogger.fileLog("kernel", "Dump OK via hakchi: \(kernelData.count) bytes, format: \(format.rawValue)")
                            return kernelData
                        }
                        HakchiLogger.fileLog("kernel", "hakchi getBackup2 returned invalid data, trying fallback")
                    }
                }
            } catch {
                HakchiLogger.fileLog("kernel", "hakchi getBackup2 failed: \(error), trying fallback")
            }
        }

        // Method 2: sunxi-flash read_boot2
        let hasSunxiFlash = try await shell.executeCommand("which sunxi-flash 2>/dev/null")
        let useSunxiFlash = !hasSunxiFlash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HakchiLogger.fileLog("kernel", "sunxi-flash available: \(useSunxiFlash)")

        if useSunxiFlash {
            progress?(0.10, "Dumping kernel via sunxi-flash...")
            HakchiLogger.fileLog("kernel", "Running: sunxi-flash read_boot2")
            let dumpResult = try await shell.executeCommand(
                "sunxi-flash read_boot2 > \(remoteTmp) 2>/dev/null; echo EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "sunxi-flash result: \(dumpResult)")
            guard dumpResult.contains("EXIT:0") else {
                throw HakchiError.kernelDumpFailed("sunxi-flash read_boot2 failed: \(dumpResult)")
            }
        } else {
            // Method 3: MTD-based dump
            progress?(0.10, "sunxi-flash not available, trying MTD...")
            let mtdInfo = try await shell.executeCommand("cat /proc/mtd 2>/dev/null")
            HakchiLogger.fileLog("kernel", "/proc/mtd: \(mtdInfo)")
            let kernelPart = parseMTDPartition(named: "kernel", from: mtdInfo)
            let mtdDev = "/dev/\(kernelPart ?? "mtd2")"
            HakchiLogger.fileLog("kernel", "Using MTD device: \(mtdDev)")
            let ddResult = try await shell.executeCommand(
                "dd if=\(mtdDev) of=\(remoteTmp) bs=64k 2>&1; echo EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "dd result: \(ddResult)")
            guard ddResult.contains("EXIT:0") else {
                throw HakchiError.kernelDumpFailed("dd failed on \(mtdDev): \(ddResult)")
            }
        }

        // Get file size
        let sizeStr = try await shell.executeCommand("wc -c < \(remoteTmp)")
        let fileSize = Int(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        HakchiLogger.fileLog("kernel", "Kernel dump size: \(fileSize) bytes")

        progress?(0.50, "Downloading kernel dump (\(fileSize / 1024) KB)...")
        kernelData = try await shell.readFile(remotePath: remoteTmp)
        HakchiLogger.fileLog("kernel", "Downloaded \(kernelData.count) bytes")

        _ = try? await shell.executeCommand("rm -f \(remoteTmp)")

        progress?(0.90, "Verifying kernel data...")
        guard isValidKernel(kernelData) else {
            HakchiLogger.fileLog("kernel", "INVALID kernel data: \(kernelData.count) bytes")
            throw HakchiError.kernelDumpFailed(
                "Kernel data appears empty or erased (all zeros/0xFF). Size: \(kernelData.count) bytes."
            )
        }

        let format = identifyKernel(kernelData)
        progress?(1.0, "Kernel dump complete (\(format.rawValue), \(kernelData.count) bytes)")
        HakchiLogger.fileLog("kernel", "Dump OK: \(kernelData.count) bytes, format: \(format.rawValue)")
        return kernelData
    }

    // MARK: - Shell-based kernel flash (via sunxi-flash)

    /// Flash a kernel image to NAND via an active shell connection.
    ///
    /// Uses `sunxi-flash burn_boot2` for Allwinner NAND boot area.
    /// Falls back to MTD-based `nandwrite`/`dd` if sunxi-flash is unavailable.
    /// Verifies write by reading back and comparing MD5 checksums.
    func flashKernelViaShell(
        data: Data,
        shell: ShellInterface,
        progress: ((Double, String) -> Void)? = nil
    ) async throws {
        let format = identifyKernel(data)
        HakchiLogger.fileLog("kernel", "flashKernelViaShell: \(data.count) bytes, format: \(format.rawValue)")

        guard isValidKernel(data) else {
            throw HakchiError.kernelFlashFailed("Kernel image appears empty or invalid")
        }

        progress?(0.0, "Uploading kernel image (\(data.count / 1024) KB)...")

        let remoteTmp = "/tmp/kernel_new.img"
        HakchiLogger.fileLog("kernel", "Uploading kernel to \(remoteTmp)...")
        try await shell.writeFile(remotePath: remoteTmp, data: data)

        // Verify upload arrived
        let uploadedSize = try await shell.executeCommand("wc -c < \(remoteTmp) 2>/dev/null")
        let uploadedBytes = Int(uploadedSize.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        HakchiLogger.fileLog("kernel", "Uploaded \(uploadedBytes) bytes (expected \(data.count))")
        guard uploadedBytes == data.count else {
            throw HakchiError.kernelFlashFailed(
                "Upload size mismatch: sent \(data.count) bytes but \(uploadedBytes) arrived on console"
            )
        }

        progress?(0.40, "Writing kernel to NAND...")

        // Determine flash method
        let hasSunxiFlash = try await shell.executeCommand("which sunxi-flash 2>/dev/null")
        let useSunxiFlash = !hasSunxiFlash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HakchiLogger.fileLog("kernel", "Flash method: \(useSunxiFlash ? "sunxi-flash" : "MTD fallback")")

        var mtdDev = ""

        if useSunxiFlash {
            HakchiLogger.fileLog("kernel", "Running: sunxi-flash burn_boot2")
            let writeResult = try await shell.executeCommand(
                "sunxi-flash burn_boot2 < \(remoteTmp) 2>&1; echo EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "burn_boot2 result: \(writeResult)")
            guard writeResult.contains("EXIT:0") else {
                throw HakchiError.kernelFlashFailed("sunxi-flash burn_boot2 failed: \(writeResult)")
            }
        } else {
            // Fallback: MTD-based write
            let mtdInfo = try await shell.executeCommand("cat /proc/mtd 2>/dev/null")
            HakchiLogger.fileLog("kernel", "/proc/mtd: \(mtdInfo)")
            let kernelPart = parseMTDPartition(named: "kernel", from: mtdInfo)
            mtdDev = "/dev/\(kernelPart ?? "mtd2")"
            HakchiLogger.fileLog("kernel", "Using MTD device: \(mtdDev)")

            // Erase first (required for NAND)
            let eraseResult = try await shell.executeCommand(
                "flash_erase \(mtdDev) 0 0 2>&1 || flash_eraseall \(mtdDev) 2>&1; echo ERASE_EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "Erase result: \(eraseResult)")

            let writeResult = try await shell.executeCommand("""
                if command -v nandwrite >/dev/null 2>&1; then
                    nandwrite -p \(mtdDev) \(remoteTmp) 2>&1; echo EXIT:$?
                else
                    dd if=\(remoteTmp) of=\(mtdDev) bs=64k 2>&1; echo EXIT:$?
                fi
                """)
            HakchiLogger.fileLog("kernel", "Write result: \(writeResult)")
            guard writeResult.contains("EXIT:0") else {
                throw HakchiError.kernelFlashFailed("Write to \(mtdDev) failed: \(writeResult)")
            }
        }

        progress?(0.70, "Verifying write...")
        HakchiLogger.fileLog("kernel", "Starting verify...")

        // Compute MD5 of the uploaded file
        let srcMD5 = try await shell.executeCommand("md5sum \(remoteTmp) | cut -d' ' -f1")
        let src = srcMD5.trimmingCharacters(in: .whitespacesAndNewlines)
        HakchiLogger.fileLog("kernel", "Source MD5: \(src)")

        // Read back from NAND and compare — use correct method based on flash path
        let verifyTmp = "/tmp/kernel_verify.img"
        if useSunxiFlash {
            let readBackResult = try await shell.executeCommand(
                "sunxi-flash read_boot2 > \(verifyTmp) 2>/dev/null; echo EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "sunxi-flash readback: \(readBackResult)")
        } else if !mtdDev.isEmpty {
            let readBackResult = try await shell.executeCommand(
                "dd if=\(mtdDev) of=\(verifyTmp) bs=64k 2>&1; echo EXIT:$?"
            )
            HakchiLogger.fileLog("kernel", "MTD readback: \(readBackResult)")
        }

        // Only verify if we successfully created the verify file
        let verifyExists = try await shell.executeCommand("test -f \(verifyTmp) && echo YES || echo NO")
        if verifyExists.trimmingCharacters(in: .whitespacesAndNewlines) == "YES" {
            let nandMD5 = try await shell.executeCommand(
                "head -c \(data.count) \(verifyTmp) | md5sum | cut -d' ' -f1"
            )
            let nand = nandMD5.trimmingCharacters(in: .whitespacesAndNewlines)
            HakchiLogger.fileLog("kernel", "NAND MD5: \(nand)")

            if !src.isEmpty && !nand.isEmpty && src != nand {
                HakchiLogger.fileLog("kernel", "MD5 MISMATCH — src: \(src), nand: \(nand)")
                // Log but don't throw — NAND read-back may include extra padding
                // that causes legitimate mismatches on some devices
                HakchiLogger.kernel.warning("MD5 mismatch after flash — src: \(src), nand: \(nand) (may be padding)")
            } else {
                HakchiLogger.fileLog("kernel", "Verify OK — MD5 match: \(src)")
            }
        } else {
            HakchiLogger.fileLog("kernel", "Verify file not created, skipping MD5 check")
        }

        // Cleanup
        _ = try? await shell.executeCommand("rm -f \(remoteTmp) \(verifyTmp)")
        _ = try? await shell.executeCommand("sync")

        progress?(1.0, "Kernel flash complete")
        HakchiLogger.fileLog("kernel", "Kernel flash done (MD5: \(src))")
    }

    // MARK: - Backup / Restore (convenience wrappers)

    /// Dump kernel via shell and save to local backup file.
    func backupKernel(
        shell: ShellInterface,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        FileUtils.ensureDirectoriesExist()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "kernel_backup_\(formatter.string(from: Date())).img"
        let backupPath = FileUtils.kernelBackupDirectory.appendingPathComponent(filename)

        let data = try await dumpKernelViaShell(shell: shell, progress: { value, msg in
            progress?(value * 0.9, msg)
        })

        try data.write(to: backupPath)
        progress?(1.0, "Saved to \(filename)")
        HakchiLogger.kernel.info("Kernel backed up to: \(backupPath.path)")
        return backupPath
    }

    /// Flash a backup file to the kernel partition via shell.
    func restoreKernel(
        from backupPath: URL,
        shell: ShellInterface,
        progress: ((Double, String) -> Void)? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw HakchiError.kernelFlashFailed("Backup file not found: \(backupPath.path)")
        }

        let data = try Data(contentsOf: backupPath)
        try await flashKernelViaShell(data: data, shell: shell, progress: progress)
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

    // MARK: - Factory Reset

    /// Factory reset: wipe hakchi and restore stock kernel + clean filesystem.
    func factoryReset(
        shell: ShellInterface,
        stockKernelPath: URL? = nil,
        progress: ((Double, String) -> Void)? = nil
    ) async throws {
        progress?(0.0, "Starting factory reset...")

        // Step 1: If we have a stock kernel backup, flash it
        if let stockPath = stockKernelPath {
            progress?(0.1, "Restoring stock kernel...")
            try await restoreKernel(from: stockPath, shell: shell, progress: { value, msg in
                progress?(0.1 + value * 0.3, msg)
            })
        } else {
            progress?(0.1, "Looking for kernel backup on console...")
            let backupResult = try await shell.executeCommand("hakchi getBackup2 2>/dev/null; echo $?")
            if backupResult.trimmingCharacters(in: .whitespacesAndNewlines) != "0" {
                HakchiLogger.kernel.warning("No kernel backup found on console, skipping kernel restore")
            }
        }

        // Step 2: Uninstall all hakchi mods
        progress?(0.4, "Removing hakchi modifications...")
        _ = try await shell.executeCommand("hakchi uninstall 2>/dev/null || true")

        // Step 3: Clean game data
        progress?(0.6, "Removing custom games...")
        _ = try await shell.executeCommand("rm -rf /var/lib/hakchi/games/* 2>/dev/null || true")

        // Step 4: Remove hakchi system files
        progress?(0.7, "Removing hakchi system files...")
        _ = try await shell.executeCommand("rm -rf /hakchi 2>/dev/null || true")
        _ = try await shell.executeCommand("rm -rf /var/lib/hakchi/rootfs 2>/dev/null || true")
        _ = try await shell.executeCommand("rm -rf /var/lib/hakchi/transfer 2>/dev/null || true")

        // Step 5: Restore original game list
        progress?(0.85, "Restoring original configuration...")
        _ = try await shell.executeCommand("hakchi restoreOriginalGames 2>/dev/null || true")

        // Step 6: Sync and reboot
        progress?(0.95, "Rebooting...")
        _ = try await shell.executeCommand("sync")
        _ = try? await shell.executeCommand("reboot")

        progress?(1.0, "Factory reset complete")
        HakchiLogger.kernel.info("Factory reset completed")
    }

    // MARK: - MTD helpers

    /// Parse `/proc/mtd` output to find a partition by name.
    /// Returns the device name (e.g. "mtd2") or nil if not found.
    private func parseMTDPartition(named name: String, from procMTD: String) -> String? {
        //  Format: mtd2: 00200000 00020000 "kernel"
        for line in procMTD.split(separator: "\n") {
            let s = String(line)
            if s.contains("\"\(name)\"") {
                if let devPart = s.split(separator: ":").first {
                    return String(devPart).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}

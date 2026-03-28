import Foundation

/// Manages memboot operations: loading kernels into RAM via FEL without flashing NAND.
///
/// The correct hakchi2-CE FEL memboot sequence (verified on real hardware):
/// 1. Load FES1 to SRAM at 0x2000 → initialise DRAM
/// 2. Write boot.img to DRAM at 0x47400000
/// 3. Write U-Boot to DRAM at 0x47000000, patch bootcmd to boot from RAM
/// 4. Execute U-Boot → chains to kernel via `boota 47400000`
actor MembootManager {

    /// Boot a custom kernel from RAM without flashing to NAND.
    ///
    /// - Parameters:
    ///   - bootImgData: Raw boot.img (Android Boot Image format).
    ///   - ubootData:   Raw uboot.bin (hakchi2-CE U-Boot bootloader).
    ///   - fes1Data:    Raw fes1.bin (Allwinner FES1 DRAM init binary).
    ///   - device:      An already-opened FELDevice.
    ///   - progress:    Progress callback (0.0–1.0).
    func memboot(
        bootImgData: Data,
        ubootData: Data,
        fes1Data: Data,
        device: FELDevice,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        progress(0.0, "Preparing memboot...")

        // Validate sizes before starting
        guard bootImgData.count <= FELConstants.transferMaxTotal else {
            throw HakchiError.kernelFlashFailed(
                "boot.img too large (\(bootImgData.count) bytes, max \(FELConstants.transferMaxTotal))")
        }
        guard ubootData.count <= FELConstants.ubootMaxSize else {
            throw HakchiError.kernelFlashFailed(
                "uboot.bin too large (\(ubootData.count) bytes, max \(FELConstants.ubootMaxSize))")
        }

        // ── Step 1: Initialise DRAM via FES1 ──────────────────────────────
        progress(0.05, "Initialising DRAM (loading FES1)...")
        try device.initDRAM(fes1Data: fes1Data)
        progress(0.15, "DRAM initialised ✓")

        // ── Step 2: Validate boot image ───────────────────────────────────
        guard let bootImage = BootImage(data: bootImgData) else {
            throw HakchiError.kernelFlashFailed(
                "Invalid boot.img — could not parse Android Boot Image header"
            )
        }
        let kSize = bootImage.kernelData.count
        let rSize = bootImage.ramdiskData.count
        let pSize = bootImage.pageSize
        HakchiLogger.kernel.info("Boot image: kernel=\(kSize)B, ramdisk=\(rSize)B, page=\(pSize)")

        // Pad boot.img to sector boundary (matching C# Fel.sector_size alignment)
        var paddedBootImg = bootImgData
        let sectorSize = Int(FELConstants.sectorSize)
        let bootRemainder = paddedBootImg.count % sectorSize
        if bootRemainder != 0 {
            paddedBootImg.append(Data(count: sectorSize - bootRemainder))
        }

        // ── Step 3: Write boot.img to DRAM ────────────────────────────────
        progress(0.20, "Loading boot.img into DRAM (\(paddedBootImg.count / 1024) KB)...")
        try device.writeMemoryWithProgress(
            address: FELConstants.bootImgAddr,
            data: paddedBootImg,
            progress: { value, msg in
                progress(0.20 + value * 0.30, msg)
            }
        )

        // ── Step 4: Patch U-Boot bootcmd and write to DRAM ────────────────
        var patchedUBoot = ubootData
        patchBootcmd(&patchedUBoot)

        progress(0.55, "Loading U-Boot into DRAM (\(patchedUBoot.count / 1024) KB)...")
        try device.writeMemoryWithProgress(
            address: FELConstants.ubootAddr,
            data: patchedUBoot,
            progress: { value, msg in
                progress(0.55 + value * 0.20, msg)
            }
        )

        // ── Step 5: Execute U-Boot ────────────────────────────────────────
        progress(0.80, "Executing U-Boot...")
        try device.execute(address: FELConstants.ubootAddr)

        progress(1.0, "Memboot started — kernel booting from RAM")
        HakchiLogger.kernel.info("Memboot executed successfully")
    }

    /// Convenience: boot with default resources from HakchiResources.
    func memboot(
        device: FELDevice,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        let resources = HakchiResources.shared
        let bootImgData = try resources.getBootImage()
        let ubootData = try resources.getUBoot()
        let fes1Data = try resources.getFES1()

        try await memboot(
            bootImgData: bootImgData,
            ubootData: ubootData,
            fes1Data: fes1Data,
            device: device,
            progress: progress
        )
    }

    /// Boot with Clovershell enabled for kernel dump/flash operations.
    func membootWithClovershell(
        device: FELDevice,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        let resources = HakchiResources.shared
        var bootImgData = try resources.getBootImage()
        let ubootData = try resources.getUBoot()
        let fes1Data = try resources.getFES1()

        // Patch boot.img cmdline to enable Clovershell
        if var bootImage = BootImage(data: bootImgData) {
            if !bootImage.cmdline.contains("hakchi-clovershell") {
                // Replace hakchi-shell with hakchi-clovershell if present,
                // otherwise append it
                if bootImage.cmdline.contains("hakchi-shell") {
                    bootImage.cmdline = bootImage.cmdline
                        .replacingOccurrences(of: "hakchi-shell", with: "hakchi-clovershell hakchi-memboot")
                } else {
                    bootImage.cmdline += " hakchi-clovershell hakchi-memboot"
                }
                bootImgData = bootImage.toData()
                HakchiLogger.kernel.info("Injected hakchi-clovershell into boot cmdline")
            }
        }

        try await memboot(
            bootImgData: bootImgData,
            ubootData: ubootData,
            fes1Data: fes1Data,
            device: device,
            progress: progress
        )
    }

    // MARK: - Private

    /// Dynamically find "bootcmd=" in U-Boot binary and return the offset of the value
    /// (i.e., the byte right after "bootcmd="). Returns nil if not found.
    private func findBootcmdOffset(in uboot: Data) -> Int? {
        let marker = Array("bootcmd=".utf8)
        let limit = uboot.count - marker.count
        for i in 0..<limit {
            var found = true
            for j in 0..<marker.count {
                if uboot[i + j] != marker[j] {
                    found = false
                    break
                }
            }
            if found {
                return i + marker.count
            }
        }
        return nil
    }

    /// Patch the U-Boot bootcmd to boot from the RAM address where we loaded boot.img.
    ///
    /// Dynamically searches for "bootcmd=" in the binary (matching C# Fel.UBootBin setter).
    /// Replaces the value with "boota 47400000" — U-Boot's `boota` reads bootargs from
    /// the Android boot image header, so we do NOT inject setenv bootargs.
    private func patchBootcmd(_ uboot: inout Data) {
        guard let cmdOffset = findBootcmdOffset(in: uboot) else {
            HakchiLogger.kernel.warning("Could not find 'bootcmd=' in U-Boot binary, skipping patch")
            return
        }

        HakchiLogger.kernel.info("Found bootcmd= at offset 0x\(String(format: "%X", cmdOffset - 8)), value starts at 0x\(String(format: "%X", cmdOffset))")

        // Find end of original bootcmd string (null-terminated in U-Boot env)
        let searchEnd = min(cmdOffset + 512, uboot.count)
        let originalEnd = uboot[cmdOffset..<searchEnd].firstIndex(of: 0) ?? (searchEnd - 1)
        let originalLength = originalEnd - cmdOffset + 1

        // Build replacement value + null terminator
        let newCmd = FELConstants.bootcmdRAM
        var replacementData = Data(newCmd.utf8)
        replacementData.append(0) // null terminator

        // Guard: replacement must fit within original string space
        guard replacementData.count <= originalLength else {
            HakchiLogger.kernel.warning("Replacement bootcmd (\(replacementData.count) bytes) exceeds original (\(originalLength) bytes), skipping patch")
            return
        }

        // Pad with nulls to match original length
        while replacementData.count < originalLength {
            replacementData.append(0)
        }

        uboot.replaceSubrange(cmdOffset..<(cmdOffset + replacementData.count), with: replacementData)
        HakchiLogger.kernel.info("Patched bootcmd value → '\(newCmd)'")
    }
}

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

        // ── Step 3: Write boot.img to DRAM ────────────────────────────────
        progress(0.20, "Loading boot.img into DRAM (\(bootImgData.count / 1024) KB)...")
        try device.writeMemoryWithProgress(
            address: FELConstants.bootImgAddr,
            data: bootImgData,
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

    /// Patch the U-Boot bootcmd to boot from the RAM address where we loaded boot.img.
    ///
    /// The original bootcmd at offset 0x6A543 is:
    ///   `bootcmd=ext4load sunxi_flash 4:0 43800000 hakchi/boot/boot.img; boota 43800000;`
    /// We replace it with the full `setenv bootargs …; boota 47400000` command.
    /// Without explicit `setenv bootargs`, U-Boot loads args from NAND env and the
    /// boot.img cmdline (with hakchi-clovershell) is ignored.
    private func patchBootcmd(_ uboot: inout Data) {
        let offset = FELConstants.bootcmdOffset
        guard uboot.count > offset + 256 else {
            HakchiLogger.kernel.warning("U-Boot too small to patch bootcmd at offset 0x\(String(format: "%X", offset))")
            return
        }

        // Verify "bootcmd=" is at the expected offset
        let marker = "bootcmd="
        let existing = String(data: uboot[offset..<(offset + marker.count)], encoding: .ascii) ?? ""
        guard existing == marker else {
            HakchiLogger.kernel.warning("bootcmd not found at expected offset, skipping patch")
            return
        }

        // Check if already patched with setenv bootargs
        let checkLen = min(offset + 256, uboot.count) - offset
        let currentCmd = String(data: uboot[offset..<(offset + checkLen)], encoding: .ascii)?
            .components(separatedBy: "\0").first ?? ""
        if currentCmd.contains("setenv bootargs") && currentCmd.contains("boota 47400000") {
            HakchiLogger.kernel.info("bootcmd already patched with setenv bootargs, skipping")
            return
        }

        // Build replacement: "bootcmd=setenv bootargs …; boota 47400000" + null terminator
        let replacement = marker + FELConstants.bootcmdRAM
        var replacementData = Data(replacement.utf8)
        replacementData.append(0) // null terminator

        // Find end of original string (null-terminated in U-Boot env)
        let searchEnd = min(offset + 512, uboot.count)
        let originalEnd = uboot[offset..<searchEnd].firstIndex(of: 0) ?? (searchEnd - 1)
        let originalLength = originalEnd - offset + 1 // include null terminator

        // Ensure replacement fits; pad with nulls if shorter than original
        while replacementData.count < originalLength {
            replacementData.append(0)
        }

        uboot.replaceSubrange(offset..<(offset + replacementData.count), with: replacementData)
        HakchiLogger.kernel.info("Patched bootcmd → \(replacement)")
    }
}

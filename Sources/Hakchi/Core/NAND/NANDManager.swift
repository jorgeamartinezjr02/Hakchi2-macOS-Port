import Foundation

/// Information about the console's NAND storage.
struct NANDInfo {
    let totalSize: Int64
    let usedSize: Int64
    let freeSize: Int64
    let blockSize: Int
    let isModified: Bool
    let hakchiInstalled: Bool
    let partitions: [NANDPartition]
}

struct NANDPartition {
    let name: String
    let mountPoint: String
    let size: Int64
    let used: Int64
    let filesystem: String
}

/// Manages NAND operations: dump, flash, partition info, health check.
actor NANDManager {

    /// Read NAND info from a connected console.
    func getNANDInfo(shell: ShellInterface) async throws -> NANDInfo {
        let dfOutput = try await shell.executeCommand("df -B1 2>/dev/null || df -k 2>/dev/null")
        let mtdOutput = try await shell.executeCommand("cat /proc/mtd 2>/dev/null || echo ''")
        let hakchiCheck = try await shell.executeCommand("ls /var/lib/hakchi 2>/dev/null && echo 'YES' || echo 'NO'")

        let partitions = parseDfOutput(dfOutput)
        let totalSize = partitions.reduce(0) { $0 + $1.size }
        let usedSize = partitions.reduce(0) { $0 + $1.used }

        return NANDInfo(
            totalSize: totalSize,
            usedSize: usedSize,
            freeSize: totalSize - usedSize,
            blockSize: 128 * 1024, // 128KB typical for NAND
            isModified: hakchiCheck.contains("YES"),
            hakchiInstalled: hakchiCheck.contains("YES"),
            partitions: partitions
        )
    }

    /// Dump the entire NAND (or specific partition) to a local file.
    func dumpNAND(shell: ShellInterface, partition: String = "nandc", localPath: String, progress: @escaping (Double, String) -> Void) async throws {
        progress(0.0, "Reading NAND partition \(partition)...")

        let mtdDevice = "/dev/\(partition)"
        let remoteTmp = "/tmp/nand_dump.bin"

        // Read NAND to temp file on console
        _ = try await shell.executeCommand("dd if=\(mtdDevice) of=\(remoteTmp) bs=128k 2>/dev/null")
        progress(0.5, "Downloading NAND dump...")

        // Download to local
        try await shell.downloadFile(remotePath: remoteTmp, localPath: localPath, progress: { p in
            progress(0.5 + p * 0.45, "Downloading...")
        })

        // Cleanup
        _ = try await shell.executeCommand("rm -f \(remoteTmp)")

        // Verify with MD5
        let remoteMD5 = try await shell.executeCommand("md5sum \(mtdDevice) 2>/dev/null | cut -d' ' -f1")
        let localData = try Data(contentsOf: URL(fileURLWithPath: localPath))
        let localMD5 = localData.md5String

        progress(1.0, remoteMD5.trimmingCharacters(in: .whitespacesAndNewlines) == localMD5 ? "NAND dump verified" : "NAND dump complete (MD5 mismatch warning)")

        HakchiLogger.kernel.info("NAND dump complete: \(localPath) (\(localData.count) bytes)")
    }

    /// Flash a NAND image to a partition.
    func flashNAND(shell: ShellInterface, partition: String = "nandc", imagePath: String, progress: @escaping (Double, String) -> Void) async throws {
        progress(0.0, "Uploading NAND image...")

        let remoteTmp = "/tmp/nand_flash.bin"
        try await shell.uploadFile(localPath: imagePath, remotePath: remoteTmp, progress: { p in
            progress(p * 0.5, "Uploading...")
        })

        progress(0.5, "Flashing to \(partition)...")
        let mtdDevice = "/dev/\(partition)"
        _ = try await shell.executeCommand("dd if=\(remoteTmp) of=\(mtdDevice) bs=128k 2>/dev/null")

        _ = try await shell.executeCommand("rm -f \(remoteTmp)")
        _ = try await shell.executeCommand("sync")

        progress(1.0, "NAND flash complete")
        HakchiLogger.kernel.info("NAND flash complete to \(partition)")
    }

    /// Format the user data partition.
    func formatUserPartition(shell: ShellInterface) async throws {
        _ = try await shell.executeCommand("umount /var/lib/hakchi 2>/dev/null || true")
        _ = try await shell.executeCommand("mkfs.ext4 /dev/nandd 2>/dev/null || mke2fs /dev/nandd")
        _ = try await shell.executeCommand("mount /dev/nandd /var/lib/hakchi 2>/dev/null || true")
        HakchiLogger.kernel.info("User partition formatted")
    }

    // MARK: - Private

    private func parseDfOutput(_ output: String) -> [NANDPartition] {
        let lines = output.split(separator: "\n").dropFirst() // skip header
        var partitions: [NANDPartition] = []

        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 6 else { continue }
            guard parts[0].hasPrefix("/dev/") else { continue }

            let size = Int64(parts[1]) ?? 0
            let used = Int64(parts[2]) ?? 0
            let mountPoint = parts.last ?? ""

            partitions.append(NANDPartition(
                name: parts[0],
                mountPoint: mountPoint,
                size: size * 1024, // df -k reports in KB
                used: used * 1024,
                filesystem: "ext4"
            ))
        }

        return partitions
    }
}

// MD5 helper
extension Data {
    var md5String: String {
        // Use CommonCrypto for MD5
        var digest = [UInt8](repeating: 0, count: 16)
        _ = withUnsafeBytes { ptr in
            CC_MD5(ptr.baseAddress, CC_LONG(count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// Import CommonCrypto
import CommonCrypto

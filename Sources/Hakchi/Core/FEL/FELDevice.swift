import Foundation
import CLibUSB

final class FELDevice {
    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var endpointIn: UInt8 = 0x82
    private var endpointOut: UInt8 = 0x01
    private var interfaceNumber: Int32 = 0
    private(set) var isOpen = false

    var isDeviceOpen: Bool { isOpen }

    deinit {
        close()
    }

    // MARK: - Connection

    func open() throws {
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else {
            throw HakchiError.usbInitFailed
        }
        context = ctx

        handle = libusb_open_device_with_vid_pid(
            ctx,
            FELConstants.vendorID,
            FELConstants.productID
        )

        guard handle != nil else {
            libusb_exit(ctx)
            context = nil
            throw HakchiError.deviceNotFound
        }

        // Auto-detach kernel driver on macOS for reliable USB access
        libusb_set_auto_detach_kernel_driver(handle, 1)

        guard libusb_claim_interface(handle, interfaceNumber) == 0 else {
            libusb_close(handle)
            libusb_exit(ctx)
            handle = nil
            context = nil
            throw HakchiError.felCommunicationError("Failed to claim USB interface")
        }

        isOpen = true
        HakchiLogger.fel.info("FEL device opened successfully")

        // Validate board ID matches Allwinner R16/A33 (0x00166700)
        do {
            let version = try getVersion()
            if version.socID != 0x00166700 {
                HakchiLogger.fel.warning("Unexpected SoC ID: 0x\(String(format: "%08X", version.socID)) (expected 0x00166700 for R16/A33)")
            }
        } catch {
            HakchiLogger.fel.warning("Could not verify board ID on open: \(error)")
        }
    }

    func close() {
        if let h = handle {
            libusb_release_interface(h, interfaceNumber)
            libusb_close(h)
            handle = nil
        }
        if let ctx = context {
            libusb_exit(ctx)
            context = nil
        }
        isOpen = false
    }

    /// Reconnect to the FEL device (e.g. after FES1 exec causes USB disconnect).
    func reconnect() {
        HakchiLogger.fel.info("Reconnecting to FEL device...")
        // Release current handle without destroying context
        if let h = handle {
            libusb_release_interface(h, interfaceNumber)
            libusb_close(h)
            handle = nil
        }
        isOpen = false

        // Try to re-open for up to 30 seconds
        for _ in 0..<30 {
            handle = libusb_open_device_with_vid_pid(
                context,
                FELConstants.vendorID,
                FELConstants.productID
            )
            if handle != nil { break }
            Thread.sleep(forTimeInterval: 1.0)
        }

        guard handle != nil else {
            HakchiLogger.fel.error("Reconnect failed: device not found")
            return
        }

        libusb_set_auto_detach_kernel_driver(handle, 1)
        if libusb_claim_interface(handle, interfaceNumber) == 0 {
            isOpen = true
            HakchiLogger.fel.info("Reconnected successfully")
        } else {
            HakchiLogger.fel.error("Reconnect: failed to claim interface")
        }
    }

    // MARK: - Low-level USB

    private func bulkSend(_ data: Data, retries: Int = 3) throws {
        guard handle != nil else { throw HakchiError.notConnected }
        var lastError: Int32 = 0
        for attempt in 0..<retries {
            var transferred: Int32 = 0
            let result = data.withUnsafeBytes { ptr in
                libusb_bulk_transfer(
                    handle,
                    endpointOut,
                    UnsafeMutablePointer(mutating: ptr.bindMemory(to: UInt8.self).baseAddress),
                    Int32(data.count),
                    &transferred,
                    FELConstants.usbTimeout
                )
            }
            if result == 0 { return }
            lastError = result
            HakchiLogger.fel.warning("Bulk send attempt \(attempt + 1)/\(retries) failed: \(result)")
            // LIBUSB_ERROR_TIMEOUT = -7: retry after clearing stale state
            if result == -7 {
                libusb_clear_halt(handle, endpointOut)
                libusb_clear_halt(handle, endpointIn)
                Thread.sleep(forTimeInterval: 0.1)
            } else {
                break
            }
        }
        throw HakchiError.felCommunicationError("Bulk send failed: \(lastError)")
    }

    private func bulkReceive(length: Int) throws -> Data {
        guard handle != nil else { throw HakchiError.notConnected }
        var result = Data()
        var remaining = length

        while remaining > 0 {
            var buffer = Data(count: remaining)
            var transferred: Int32 = 0
            let rc = buffer.withUnsafeMutableBytes { ptr in
                libusb_bulk_transfer(
                    handle,
                    endpointIn,
                    ptr.bindMemory(to: UInt8.self).baseAddress,
                    Int32(remaining),
                    &transferred,
                    FELConstants.usbTimeout
                )
            }
            guard rc == 0 else {
                throw HakchiError.felCommunicationError("Bulk receive failed: \(rc)")
            }
            if transferred <= 0 {
                throw HakchiError.felCommunicationError("Bulk receive returned no data (expected \(remaining) more bytes)")
            }
            result.append(buffer.prefix(Int(transferred)))
            remaining -= Int(transferred)
        }

        return result
    }

    // MARK: - FEL Protocol

    private func sendFELRequest(command: UInt32, address: UInt32 = 0, length: UInt32 = 0) throws {
        let usbReq = AWUSBRequest(requestType: FELConstants.usbWrite, length: 16)
        try bulkSend(usbReq.data)

        let felReq = AWFELRequest(command: command, address: address, length: length)
        try bulkSend(felReq.data)

        let status = try bulkReceive(length: 13)
        guard AWUSBResponse(data: status)?.isValid == true else {
            throw HakchiError.felCommunicationError("Invalid status response")
        }
    }

    private func felRead(length: Int) throws -> Data {
        let usbReq = AWUSBRequest(requestType: FELConstants.usbRead, length: UInt32(length))
        try bulkSend(usbReq.data)

        let data = try bulkReceive(length: length)

        let status = try bulkReceive(length: 13)
        guard AWUSBResponse(data: status)?.isValid == true else {
            throw HakchiError.felCommunicationError("Invalid read status")
        }

        return data
    }

    private func felWrite(data: Data) throws {
        let usbReq = AWUSBRequest(requestType: FELConstants.usbWrite, length: UInt32(data.count))
        try bulkSend(usbReq.data)

        // Send data in chunks
        var offset = 0
        while offset < data.count {
            let chunkSize = min(FELConstants.bulkChunkSize, data.count - offset)
            let chunk = data[offset..<(offset + chunkSize)]
            try bulkSend(Data(chunk))
            offset += chunkSize
        }

        let status = try bulkReceive(length: 13)
        guard AWUSBResponse(data: status)?.isValid == true else {
            throw HakchiError.felCommunicationError("Invalid write status")
        }
    }

    // MARK: - Public FEL Commands

    /// FEL status response: [mark:2][tag:2][state:1][pad:3] = 8 bytes.
    /// State != 0 indicates a FEL-level error (e.g., bad address, failed write).
    private func felStatus() throws {
        let data = try felRead(length: 8)
        // Parse state byte at offset 4 (after mark[2] + tag[2])
        if data.count >= 5 && data[4] != 0 {
            throw HakchiError.felCommunicationError("FEL status error: state=\(data[4])")
        }
    }

    func getVersion() throws -> FELVersion {
        try sendFELRequest(command: FELConstants.felVerifyDevice)
        let data = try felRead(length: 32)
        // FEL verify requires reading the 8-byte status (matches C tool's fel_status())
        // Without this, leftover bytes on the bus corrupt the next command.
        try felStatus()
        let version = FELVersion(data: data)
        HakchiLogger.fel.info("FEL version: \(version.description)")
        return version
    }

    func readMemory(address: UInt32, length: UInt32) throws -> Data {
        // Allwinner FEL requires 4-byte aligned transfer lengths
        let alignedLength = (length + 3) & ~UInt32(3)
        var result = Data()
        var remaining = alignedLength
        var currentAddr = address

        while remaining > 0 {
            let chunkSize = min(remaining, FELConstants.transferMaxSize)
            try sendFELRequest(command: FELConstants.felUpload, address: currentAddr, length: chunkSize)
            let chunk = try felRead(length: Int(chunkSize))
            try felStatus()
            result.append(chunk)
            currentAddr += chunkSize
            remaining -= chunkSize
        }

        // Return only the requested length (trim alignment padding)
        return Data(result.prefix(Int(length)))
    }

    func writeMemory(address: UInt32, data: Data) throws {
        // Allwinner FEL requires 4-byte aligned transfer lengths
        var alignedData = data
        let remainder = data.count % 4
        if remainder != 0 {
            alignedData.append(Data(count: 4 - remainder))
        }

        var offset = 0
        var currentAddr = address

        while offset < alignedData.count {
            let chunkSize = min(Int(FELConstants.transferMaxSize), alignedData.count - offset)
            let chunk = Data(alignedData[offset..<(offset + chunkSize)])
            try sendFELRequest(command: FELConstants.felDownload, address: currentAddr, length: UInt32(chunkSize))
            try felWrite(data: chunk)
            try felStatus()
            currentAddr += UInt32(chunkSize)
            offset += chunkSize
        }
    }

    func execute(address: UInt32) throws {
        try sendFELRequest(command: FELConstants.felExec, address: address)
        try felStatus()
        HakchiLogger.fel.info("Executing code at 0x\(String(format: "%08X", address))")
    }

    func readMemoryWithProgress(
        address: UInt32,
        length: UInt32,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> Data {
        let alignedLength = (length + 3) & ~UInt32(3)
        var result = Data()
        var remaining = alignedLength
        var currentAddr = address
        let total = Double(length)

        while remaining > 0 {
            let chunkSize = min(remaining, FELConstants.transferMaxSize)
            try sendFELRequest(command: FELConstants.felUpload, address: currentAddr, length: chunkSize)
            let chunk = try felRead(length: Int(chunkSize))
            try felStatus()
            result.append(chunk)
            currentAddr += chunkSize
            remaining -= chunkSize

            let transferred = min(Double(result.count), total)
            progress?(transferred / total, "Reading \(Int(transferred / 1024))KB / \(Int(total / 1024))KB")
        }

        return Data(result.prefix(Int(length)))
    }

    func writeMemoryWithProgress(
        address: UInt32,
        data: Data,
        progress: ((Double, String) -> Void)? = nil
    ) throws {
        var alignedData = data
        let remainder = data.count % 4
        if remainder != 0 {
            alignedData.append(Data(count: 4 - remainder))
        }

        var offset = 0
        var currentAddr = address
        let total = Double(data.count)

        while offset < alignedData.count {
            let chunkSize = min(Int(FELConstants.transferMaxSize), alignedData.count - offset)
            let chunk = Data(alignedData[offset..<(offset + chunkSize)])
            try sendFELRequest(command: FELConstants.felDownload, address: currentAddr, length: UInt32(chunkSize))
            try felWrite(data: chunk)
            try felStatus()
            currentAddr += UInt32(chunkSize)
            offset += chunkSize

            let written = min(Double(offset), total)
            progress?(written / total, "Writing \(Int(written / 1024))KB / \(Int(total / 1024))KB")
        }
    }

    // MARK: - DRAM Initialization (Allwinner R16/A33 via FES1)

    /// Read a little-endian UInt32 from Data at the given byte offset.
    private static func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    /// Initialize DRAM using the Allwinner FES1 binary.
    ///
    /// Hakchi2-CE uses a separate `fes1.bin` (eGON.BT0 format) for DRAM init,
    /// NOT the first 16KB of uboot.bin (which is NOT a standalone SPL).
    ///
    /// Sequence (verified working with real hardware):
    /// 1. Write FES1 to SRAM at address 0x2000.
    /// 2. Execute FES1 — it initialises the DDR controller.
    /// 3. Wait for DRAM to stabilise.
    /// 4. Verify DRAM is accessible with a write/read test.
    func initDRAM(fes1Data: Data) throws {
        guard fes1Data.count >= 0x20 else {
            throw HakchiError.felCommunicationError("FES1 binary too small (\(fes1Data.count) bytes)")
        }

        let magic = String(data: fes1Data[4..<12], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        guard magic.hasPrefix("eGON") else {
            throw HakchiError.felCommunicationError(
                "Invalid FES1 header — expected eGON magic, got '\(magic)'. "
                + "Make sure fes1.bin is a valid Allwinner FES1 binary."
            )
        }

        HakchiLogger.fel.info("FES1: \(fes1Data.count) bytes, magic: \(magic)")

        // ── 1. Write FES1 to SRAM at 0x2000 ─────────────────────────────
        try writeMemory(address: FELConstants.fes1Addr, data: fes1Data)
        HakchiLogger.fel.info("FES1 written to SRAM at 0x\(String(format: "%04X", FELConstants.fes1Addr))")

        // ── 2. Execute FES1 (initialises DDR controller) ─────────────────
        HakchiLogger.fel.info("Executing FES1 for DRAM initialisation...")
        try execute(address: FELConstants.fes1Addr)

        // ── 3. Wait for DRAM to stabilise ────────────────────────────────
        Thread.sleep(forTimeInterval: 2.0)

        // ── 3b. Verify device is still responsive, reconnect if needed ──
        do {
            _ = try getVersion()
        } catch {
            HakchiLogger.fel.info("Device unresponsive after FES1, reconnecting...")
            reconnect()
            Thread.sleep(forTimeInterval: 2.0)
            _ = try getVersion()
        }

        // ── 4. Verify DRAM is alive ──────────────────────────────────────
        let testAddr = FELConstants.dramBase + 0x100
        let testPattern = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try writeMemory(address: testAddr, data: testPattern)
        let readBack = try readMemory(address: testAddr, length: UInt32(testPattern.count))
        guard readBack == testPattern else {
            throw HakchiError.felCommunicationError(
                "DRAM verification failed after FES1 execution. "
                + "Expected \(testPattern.map { String(format: "%02X", $0) }.joined()) "
                + "but read \(readBack.map { String(format: "%02X", $0) }.joined()). "
                + "The DDR controller may not have initialised correctly."
            )
        }

        HakchiLogger.fel.info("DRAM initialised and verified successfully")
    }

    /// Legacy initDRAM that accepts SPL data (redirects to FES1 flow).
    /// Kept for backward compatibility — callers should migrate to `initDRAM(fes1Data:)`.
    func initDRAM(splData: Data) throws {
        try initDRAM(fes1Data: splData)
    }
}

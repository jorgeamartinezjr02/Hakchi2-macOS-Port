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

        // Detach kernel driver if needed
        if libusb_kernel_driver_active(handle, interfaceNumber) == 1 {
            libusb_detach_kernel_driver(handle, interfaceNumber)
        }

        guard libusb_claim_interface(handle, interfaceNumber) == 0 else {
            libusb_close(handle)
            libusb_exit(ctx)
            handle = nil
            context = nil
            throw HakchiError.felCommunicationError("Failed to claim USB interface")
        }

        isOpen = true
        HakchiLogger.fel.info("FEL device opened successfully")
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

    // MARK: - Low-level USB

    private func bulkSend(_ data: Data) throws {
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
        guard result == 0 else {
            throw HakchiError.felCommunicationError("Bulk send failed: \(result)")
        }
    }

    private func bulkReceive(length: Int) throws -> Data {
        var buffer = Data(count: length)
        var transferred: Int32 = 0
        let result = buffer.withUnsafeMutableBytes { ptr in
            libusb_bulk_transfer(
                handle,
                endpointIn,
                ptr.bindMemory(to: UInt8.self).baseAddress,
                Int32(length),
                &transferred,
                FELConstants.usbTimeout
            )
        }
        guard result == 0 else {
            throw HakchiError.felCommunicationError("Bulk receive failed: \(result)")
        }
        return buffer.prefix(Int(transferred))
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

    func getVersion() throws -> FELVersion {
        try sendFELRequest(command: FELConstants.felVerifyDevice)
        let data = try felRead(length: 32)
        let version = FELVersion(data: data)
        HakchiLogger.fel.info("FEL version: \(version.description)")
        return version
    }

    func readMemory(address: UInt32, length: UInt32) throws -> Data {
        var result = Data()
        var remaining = length
        var currentAddr = address

        while remaining > 0 {
            let chunkSize = min(remaining, FELConstants.transferMaxSize)
            try sendFELRequest(command: FELConstants.felUpload, address: currentAddr, length: chunkSize)
            let chunk = try felRead(length: Int(chunkSize))
            result.append(chunk)
            currentAddr += chunkSize
            remaining -= chunkSize
        }

        return result
    }

    func writeMemory(address: UInt32, data: Data) throws {
        var offset = 0
        var currentAddr = address

        while offset < data.count {
            let chunkSize = min(Int(FELConstants.transferMaxSize), data.count - offset)
            let chunk = Data(data[offset..<(offset + chunkSize)])
            try sendFELRequest(command: FELConstants.felDownload, address: currentAddr, length: UInt32(chunkSize))
            try felWrite(data: chunk)
            currentAddr += UInt32(chunkSize)
            offset += chunkSize
        }
    }

    func execute(address: UInt32) throws {
        try sendFELRequest(command: FELConstants.felExec, address: address)
        HakchiLogger.fel.info("Executing code at 0x\(String(format: "%08X", address))")
    }

    func readMemoryWithProgress(
        address: UInt32,
        length: UInt32,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> Data {
        var result = Data()
        var remaining = length
        var currentAddr = address
        let total = Double(length)

        while remaining > 0 {
            let chunkSize = min(remaining, FELConstants.transferMaxSize)
            try sendFELRequest(command: FELConstants.felUpload, address: currentAddr, length: chunkSize)
            let chunk = try felRead(length: Int(chunkSize))
            result.append(chunk)
            currentAddr += chunkSize
            remaining -= chunkSize

            let transferred = total - Double(remaining)
            progress?(transferred / total, "Reading \(Int(transferred / 1024))KB / \(Int(total / 1024))KB")
        }

        return result
    }

    func writeMemoryWithProgress(
        address: UInt32,
        data: Data,
        progress: ((Double, String) -> Void)? = nil
    ) throws {
        var offset = 0
        var currentAddr = address
        let total = Double(data.count)

        while offset < data.count {
            let chunkSize = min(Int(FELConstants.transferMaxSize), data.count - offset)
            let chunk = Data(data[offset..<(offset + chunkSize)])
            try sendFELRequest(command: FELConstants.felDownload, address: currentAddr, length: UInt32(chunkSize))
            try felWrite(data: chunk)
            currentAddr += UInt32(chunkSize)
            offset += chunkSize

            progress?(Double(offset) / total, "Writing \(offset / 1024)KB / \(Int(total / 1024))KB")
        }
    }

    // MARK: - DRAM Initialization (Allwinner R16/A33 via FES1)

    /// Read a little-endian UInt32 from Data at the given byte offset.
    private static func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
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

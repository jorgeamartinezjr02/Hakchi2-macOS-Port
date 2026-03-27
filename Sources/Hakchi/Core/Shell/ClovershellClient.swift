import Foundation
import CLibUSB

/// Clovershell protocol client for direct USB communication with a running console.
/// This provides command execution and file transfer without needing SSH/network.
final class ClovershellClient {
    private var handle: OpaquePointer?
    private var context: OpaquePointer?
    private var isConnected = false

    // Clovershell USB endpoints
    private let endpointIn: UInt8 = 0x81
    private let endpointOut: UInt8 = 0x01
    private let interfaceNumber: Int32 = 0

    // Clovershell VID/PID (custom firmware)
    static let vendorID: UInt16 = 0x1F3A
    static let productID: UInt16 = 0x0525

    // Command types
    enum Command: UInt8 {
        case shell = 0
        case exec = 1
        case readFile = 2
        case writeFile = 3
        case info = 4
    }

    deinit {
        disconnect()
    }

    func connect() throws {
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else {
            throw HakchiError.usbInitFailed
        }
        context = ctx

        handle = libusb_open_device_with_vid_pid(
            ctx,
            ClovershellClient.vendorID,
            ClovershellClient.productID
        )

        guard handle != nil else {
            libusb_exit(ctx)
            context = nil
            throw HakchiError.deviceNotFound
        }

        if libusb_kernel_driver_active(handle, interfaceNumber) == 1 {
            libusb_detach_kernel_driver(handle, interfaceNumber)
        }

        guard libusb_claim_interface(handle, interfaceNumber) == 0 else {
            libusb_close(handle)
            libusb_exit(ctx)
            handle = nil
            context = nil
            throw HakchiError.felCommunicationError("Failed to claim Clovershell interface")
        }

        isConnected = true
        HakchiLogger.general.info("Clovershell connected")
    }

    func disconnect() {
        if let h = handle {
            libusb_release_interface(h, interfaceNumber)
            libusb_close(h)
            handle = nil
        }
        if let ctx = context {
            libusb_exit(ctx)
            context = nil
        }
        isConnected = false
    }

    func executeCommand(_ command: String) throws -> String {
        guard isConnected, let _ = handle else {
            throw HakchiError.notConnected
        }

        var cmdData = Data([Command.exec.rawValue])
        cmdData.append(Data(command.utf8))
        cmdData.append(0) // null terminator

        try bulkSend(cmdData)
        let response = try bulkReceive(length: 65536)

        return String(data: response, encoding: .utf8) ?? ""
    }

    func readFile(remotePath: String) throws -> Data {
        guard isConnected else { throw HakchiError.notConnected }

        var cmdData = Data([Command.readFile.rawValue])
        cmdData.append(Data(remotePath.utf8))
        cmdData.append(0)

        try bulkSend(cmdData)

        var fileData = Data()
        while true {
            let chunk = try bulkReceive(length: 65536)
            if chunk.isEmpty { break }
            fileData.append(chunk)
        }

        return fileData
    }

    func writeFile(remotePath: String, data: Data) throws {
        guard isConnected else { throw HakchiError.notConnected }

        var cmdData = Data([Command.writeFile.rawValue])
        let sizeBytes = withUnsafeBytes(of: UInt32(data.count).littleEndian) { Data($0) }
        cmdData.append(sizeBytes)
        cmdData.append(Data(remotePath.utf8))
        cmdData.append(0)

        try bulkSend(cmdData)
        try bulkSend(data)

        let ack = try bulkReceive(length: 1)
        guard ack.first == 0 else {
            throw HakchiError.sftpTransferFailed("Clovershell write failed for: \(remotePath)")
        }
    }

    // MARK: - Private

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
            throw HakchiError.felCommunicationError("Clovershell send failed: \(result)")
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
            throw HakchiError.felCommunicationError("Clovershell receive failed: \(result)")
        }
        return buffer.prefix(Int(transferred))
    }
}

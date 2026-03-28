import Foundation
import CLibUSB

/// Clovershell USB protocol client for direct communication with a running hakchi console.
///
/// Protocol reverse-engineered from TeamShinkansen/Hakchi2-CE `ClovershellConnection.cs`.
/// Packet format: 4-byte header (cmd[1], arg[1], length_le16[2]) + payload.
/// All data is exchanged via USB bulk endpoints on a single interface.
///
/// The Clovershell gadget is activated when the kernel boots with `hakchi-clovershell`
/// in the command line. It reconfigures the USB gadget to VID:0x1F3A PID:0xEFE8.
final class ClovershellClient {
    private var handle: OpaquePointer?
    private var context: OpaquePointer?
    private(set) var isConnected = false

    // USB endpoints (discovered from device descriptor)
    private var endpointIn: UInt8 = 0x81
    private var endpointOut: UInt8 = 0x01

    // Clovershell VID/PID (set by f_clovershell() in ramdisk init scripts)
    static let vendorID: UInt16 = 0x1F3A
    static let productID: UInt16 = 0xEFE8

    private let usbTimeout: UInt32 = 10000
    private let bufferSize = 65536

    // Receive buffer for handling multi-packet USB transfers
    private var recvBuf = Data(count: 65536)
    private var recvPos = 0
    private var recvCount = 0

    // MARK: - Clovershell Command Types (from ClovershellConnection.cs)

    enum Command: UInt8 {
        case ping           = 0
        case pong           = 1
        case shellKillAll   = 8
        case execNewReq     = 9
        case execNewResp    = 10
        case execPID        = 11
        case execStdin      = 12
        case execStdout     = 13
        case execStderr     = 14
        case execResult     = 15
        case execKillAll    = 17
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection

    func connect() throws {
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else {
            throw HakchiError.usbInitFailed
        }
        context = ctx

        handle = libusb_open_device_with_vid_pid(ctx, Self.vendorID, Self.productID)
        guard handle != nil else {
            libusb_exit(ctx)
            context = nil
            throw HakchiError.deviceNotFound
        }

        libusb_set_auto_detach_kernel_driver(handle, 1)

        // Claim all available interfaces
        let dev = libusb_get_device(handle)!
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        if libusb_get_config_descriptor(dev, 0, &config) == 0, let cfg = config {
            for i in 0..<Int(cfg.pointee.bNumInterfaces) {
                libusb_claim_interface(handle, Int32(i))
            }

            // Find bulk endpoints
            for i in 0..<Int(cfg.pointee.bNumInterfaces) {
                let iface = cfg.pointee.interface[i].altsetting[0]
                for e in 0..<Int(iface.bNumEndpoints) {
                    let ep = iface.endpoint[e]
                    if (ep.bmAttributes & 0x03) == UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue) {
                        if ep.bEndpointAddress & 0x80 != 0 {
                            endpointIn = ep.bEndpointAddress
                        } else {
                            endpointOut = ep.bEndpointAddress
                        }
                    }
                }
            }
            libusb_free_config_descriptor(config)
        }

        // Initialize connection (matches C# ClovershellConnection)
        // Step 1: Kill all existing sessions
        var killShell = Data([Command.shellKillAll.rawValue, 0, 0, 0])
        var killExec = Data([Command.execKillAll.rawValue, 0, 0, 0])
        var dummy: Int32 = 0
        killShell.withUnsafeMutableBytes { ptr in
            libusb_bulk_transfer(handle, endpointOut, ptr.baseAddress?.assumingMemoryBound(to: UInt8.self), 4, &dummy, 1000)
        }
        killExec.withUnsafeMutableBytes { ptr in
            libusb_bulk_transfer(handle, endpointOut, ptr.baseAddress?.assumingMemoryBound(to: UInt8.self), 4, &dummy, 1000)
        }

        // Step 2: Drain pending data
        var drainBuf = Data(count: bufferSize)
        for _ in 0..<20 {
            var got: Int32 = 0
            let rc = drainBuf.withUnsafeMutableBytes { ptr in
                libusb_bulk_transfer(handle, endpointIn, ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                                     Int32(bufferSize), &got, 100)
            }
            if rc == LIBUSB_ERROR_TIMEOUT.rawValue && got == 0 { break }
        }

        recvPos = 0
        recvCount = 0
        isConnected = true
        let epOut = self.endpointOut
        let epIn = self.endpointIn
        HakchiLogger.general.info("Clovershell connected (EP OUT=0x\(String(format: "%02X", epOut)), IN=0x\(String(format: "%02X", epIn)))")
    }

    func disconnect() {
        if let h = handle {
            let dev = libusb_get_device(h)!
            var config: UnsafeMutablePointer<libusb_config_descriptor>?
            if libusb_get_config_descriptor(dev, 0, &config) == 0, let cfg = config {
                for i in (0..<Int(cfg.pointee.bNumInterfaces)).reversed() {
                    libusb_release_interface(h, Int32(i))
                }
                libusb_free_config_descriptor(config)
            }
            libusb_close(h)
            handle = nil
        }
        if let ctx = context {
            libusb_exit(ctx)
            context = nil
        }
        isConnected = false
    }

    // MARK: - Command Execution

    /// Execute a command and return its stdout output as a string.
    func executeCommand(_ command: String) throws -> String {
        let data = try executeRaw(command)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Execute a command and return raw stdout bytes.
    func executeRaw(_ command: String) throws -> Data {
        guard isConnected else { throw HakchiError.notConnected }

        // Send exec request
        try sendPacket(.execNewReq, arg: 0, payload: Data(command.utf8))

        // Read responses
        var sessionID: UInt8 = 0
        var stdoutData = Data()
        var exitCode: Int = -1
        var stdoutDone = false

        while true {
            let (cmd, arg, payload) = try recvPacket(timeout: usbTimeout)

            switch cmd {
            case .execNewResp:
                sessionID = arg
                // Close stdin immediately (no input)
                try sendPacket(.execStdin, arg: sessionID, payload: Data())

            case .execStdout:
                if payload.isEmpty {
                    stdoutDone = true
                    if exitCode >= 0 { return stdoutData }
                } else {
                    stdoutData.append(payload)
                }

            case .execStderr:
                break // Ignore stderr for executeCommand

            case .execResult:
                exitCode = payload.isEmpty ? 0 : Int(payload[0])
                if stdoutDone { return stdoutData }

            case .pong, .execPID:
                break

            default:
                break
            }
        }
    }

    /// Execute a command and return (stdout, stderr, exitCode).
    func executeWithDetails(_ command: String) throws -> (stdout: Data, stderr: Data, exitCode: Int) {
        guard isConnected else { throw HakchiError.notConnected }

        try sendPacket(.execNewReq, arg: 0, payload: Data(command.utf8))

        var sessionID: UInt8 = 0
        var stdoutData = Data()
        var stderrData = Data()
        var exitCode: Int = -1
        var stdoutDone = false

        while true {
            let (cmd, arg, payload) = try recvPacket(timeout: usbTimeout)

            switch cmd {
            case .execNewResp:
                sessionID = arg
                try sendPacket(.execStdin, arg: sessionID, payload: Data())

            case .execStdout:
                if payload.isEmpty {
                    stdoutDone = true
                    if exitCode >= 0 { return (stdoutData, stderrData, exitCode) }
                } else {
                    stdoutData.append(payload)
                }

            case .execStderr:
                if !payload.isEmpty { stderrData.append(payload) }

            case .execResult:
                exitCode = payload.isEmpty ? 0 : Int(payload[0])
                if stdoutDone { return (stdoutData, stderrData, exitCode) }

            case .pong, .execPID:
                break

            default:
                break
            }
        }
    }

    // MARK: - File Operations (via shell commands)

    func readFile(remotePath: String) throws -> Data {
        return try executeRaw("cat '\(remotePath)'")
    }

    func writeFile(remotePath: String, data: Data) throws {
        // Write via base64 encoding through shell
        let base64 = data.base64EncodedString()
        let result = try executeCommand("echo '\(base64)' | base64 -d > '\(remotePath)'; echo $?")
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else {
            throw HakchiError.sftpTransferFailed("Failed to write \(remotePath)")
        }
    }

    /// Send a ping and wait for pong to verify the connection is alive.
    func ping() throws -> Bool {
        guard isConnected else { return false }
        try sendPacket(.ping, arg: 0, payload: Data())
        let (cmd, _, _) = try recvPacket(timeout: 3000)
        return cmd == .pong
    }

    // MARK: - Low-level Protocol

    /// Send a Clovershell packet (4-byte header + payload as one USB transfer).
    private func sendPacket(_ cmd: Command, arg: UInt8, payload: Data) throws {
        let len = UInt16(payload.count)
        var pkt = Data(capacity: 4 + Int(len))
        pkt.append(cmd.rawValue)
        pkt.append(arg)
        pkt.append(UInt8(len & 0xFF))
        pkt.append(UInt8(len >> 8))
        if !payload.isEmpty { pkt.append(payload) }

        var transferred: Int32 = 0
        let rc = pkt.withUnsafeBytes { ptr in
            libusb_bulk_transfer(
                handle, endpointOut,
                UnsafeMutablePointer(mutating: ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)),
                Int32(pkt.count), &transferred, 1000
            )
        }
        guard rc == 0 else {
            throw HakchiError.felCommunicationError("Clovershell send failed: \(rc)")
        }
    }

    /// Receive the next packet from the USB stream.
    /// Handles multi-packet USB transfers (multiple Clovershell packets per bulk read).
    private func recvPacket(timeout: UInt32) throws -> (cmd: Command, arg: UInt8, payload: Data) {
        // Fill buffer if needed
        if recvPos >= recvCount {
            recvPos = 0
            recvCount = 0
            var got: Int32 = 0
            let rc = recvBuf.withUnsafeMutableBytes { ptr in
                libusb_bulk_transfer(
                    handle, endpointIn,
                    ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    Int32(bufferSize), &got, timeout
                )
            }
            if rc == LIBUSB_ERROR_TIMEOUT.rawValue {
                // On timeout, send ping as keep-alive
                try sendPacket(.ping, arg: 0, payload: Data())
                // Retry
                let rc2 = recvBuf.withUnsafeMutableBytes { ptr in
                    libusb_bulk_transfer(
                        handle, endpointIn,
                        ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        Int32(bufferSize), &got, timeout
                    )
                }
                guard rc2 == 0 && got > 0 else {
                    throw HakchiError.felCommunicationError("Clovershell receive timeout")
                }
            } else if rc != 0 {
                throw HakchiError.felCommunicationError("Clovershell receive failed: \(rc)")
            }
            recvCount = Int(got)
        }

        // Parse header
        let avail = recvCount - recvPos
        guard avail >= 4 else {
            throw HakchiError.felCommunicationError("Incomplete Clovershell packet header")
        }

        let cmdByte = recvBuf[recvPos]
        let arg = recvBuf[recvPos + 1]
        let len = Int(recvBuf[recvPos + 2]) | (Int(recvBuf[recvPos + 3]) << 8)
        recvPos += 4

        guard let cmd = Command(rawValue: cmdByte) else {
            // Skip unknown commands
            recvPos += min(len, recvCount - recvPos)
            return try recvPacket(timeout: timeout)
        }

        // Read payload
        var payload = Data()
        if len > 0 {
            let available = recvCount - recvPos
            if available >= len {
                payload = Data(recvBuf[recvPos..<(recvPos + len)])
                recvPos += len
            } else {
                // Payload split across transfers
                if available > 0 {
                    payload.append(recvBuf[recvPos..<recvCount])
                }
                recvPos = recvCount
                var remaining = len - available
                while remaining > 0 {
                    var got: Int32 = 0
                    let rc = recvBuf.withUnsafeMutableBytes { ptr in
                        libusb_bulk_transfer(
                            handle, endpointIn,
                            ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            Int32(min(remaining, bufferSize)), &got, timeout
                        )
                    }
                    guard rc == 0 && got > 0 else {
                        throw HakchiError.felCommunicationError("Clovershell receive failed during payload")
                    }
                    let take = min(Int(got), remaining)
                    payload.append(recvBuf[0..<take])
                    remaining -= take
                    // If we got more than needed, keep the rest in the buffer
                    if Int(got) > take {
                        recvPos = take
                        recvCount = Int(got)
                    } else {
                        recvPos = 0
                        recvCount = 0
                    }
                }
            }
        }

        return (cmd, arg, payload)
    }
}

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

    // Thread safety: serialize all USB writes
    private let writeLock = NSLock()

    // MARK: - Clovershell Command Types (from ClovershellConnection.cs)

    enum Command: UInt8 {
        case ping                  = 0
        case pong                  = 1
        case shellNewReq           = 2
        case shellNewResp          = 3
        case shellIn               = 4
        case shellOut              = 5
        case shellClosed           = 6
        case shellKill             = 7
        case shellKillAll          = 8
        case execNewReq            = 9
        case execNewResp           = 10
        case execPID               = 11
        case execStdin             = 12
        case execStdout            = 13
        case execStderr            = 14
        case execResult            = 15
        case execKill              = 16
        case execKillAll           = 17
        case execStdinFlowStat     = 18
        case execStdinFlowStatReq  = 19
    }

    // Stdin flow control constants (matching C# ExecConnection)
    private static let stdinChunkSize = 8192          // 8KB chunks
    private static let stdinHighWatermark = 32768     // Pause when queue > 32KB
    private static let stdinLowWatermark = 16384      // Resume when queue < 16KB

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
        guard let dev = libusb_get_device(handle) else {
            libusb_close(handle)
            handle = nil
            libusb_exit(ctx)
            context = nil
            throw HakchiError.felCommunicationError("Failed to get USB device reference")
        }
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
        isConnected = false
        if let h = handle {
            guard let dev = libusb_get_device(h) else {
                libusb_close(h)
                handle = nil
                if let ctx = context { libusb_exit(ctx); context = nil }
                return
            }
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
    }

    // MARK: - Command Execution

    /// Execute a command and return its stdout output as a string (trimmed, matching C# ExecuteSimple).
    func executeCommand(_ command: String) throws -> String {
        let data = try executeRaw(command)
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
                guard !payload.isEmpty else {
                    throw HakchiError.felCommunicationError("Empty execResult payload — protocol error")
                }
                exitCode = Int(payload[0])
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
        var stderrDone = false

        while true {
            let (cmd, arg, payload) = try recvPacket(timeout: usbTimeout)

            switch cmd {
            case .execNewResp:
                sessionID = arg
                try sendPacket(.execStdin, arg: sessionID, payload: Data())

            case .execStdout:
                if payload.isEmpty {
                    stdoutDone = true
                    if exitCode >= 0 && stderrDone { return (stdoutData, stderrData, exitCode) }
                } else {
                    stdoutData.append(payload)
                }

            case .execStderr:
                if payload.isEmpty {
                    stderrDone = true
                    if exitCode >= 0 && stdoutDone { return (stdoutData, stderrData, exitCode) }
                } else {
                    stderrData.append(payload)
                }

            case .execResult:
                guard !payload.isEmpty else {
                    throw HakchiError.felCommunicationError("Empty execResult payload — protocol error")
                }
                exitCode = Int(payload[0])
                if stdoutDone && stderrDone { return (stdoutData, stderrData, exitCode) }

            case .pong, .execPID:
                break

            default:
                break
            }
        }
    }

    // MARK: - File Operations (via shell commands)

    func readFile(remotePath: String) throws -> Data {
        let safePath = remotePath.replacingOccurrences(of: "'", with: "'\\''")
        let result = try executeWithDetails("cat '\(safePath)'")
        if result.exitCode != 0 {
            let errMsg = String(data: result.stderr, encoding: .utf8) ?? "unknown error"
            throw HakchiError.sftpTransferFailed("Failed to read \(remotePath): \(errMsg)")
        }
        return result.stdout
    }

    func writeFile(remotePath: String, data: Data) throws {
        // Stream data through stdin using `cat > file` with proper flow control.
        guard isConnected else { throw HakchiError.notConnected }

        let safePath = remotePath.replacingOccurrences(of: "'", with: "'\\''")
        HakchiLogger.fileLog("clovershell", "writeFile: \(data.count) bytes -> \(remotePath)")
        try sendPacket(.execNewReq, arg: 0, payload: Data("cat > '\(safePath)'".utf8))

        // Phase 1: Wait for session assignment
        var sessionID: UInt8 = 0
        let (cmd, arg, _) = try recvPacket(timeout: usbTimeout)
        guard cmd == .execNewResp else {
            throw HakchiError.sftpTransferFailed("Unexpected response starting write to \(remotePath)")
        }
        sessionID = arg

        // Phase 2: Wait for execPID — confirms the `cat` process is running
        var gotPID = false
        for _ in 0..<10 {
            do {
                let pkt = try recvPacket(timeout: 2000)
                if pkt.cmd == .execPID {
                    gotPID = true
                    break
                }
            } catch {
                break
            }
        }
        if !gotPID {
            Thread.sleep(forTimeInterval: 0.1)
            HakchiLogger.fileLog("clovershell", "writeFile: execPID not received, using 100ms delay")
        }

        // Phase 3: Send file data with stdin flow control (matching C# ExecConnection.stdinLoop)
        let chunkSize = Self.stdinChunkSize
        var offset = 0

        while offset < data.count {
            // Query device stdin queue status before sending
            let queueSize = try queryStdinFlowStatus(sessionID: sessionID)
            if queueSize > Self.stdinHighWatermark {
                // Back off until queue drains below low watermark
                var currentQueue = queueSize
                while currentQueue > Self.stdinLowWatermark {
                    Thread.sleep(forTimeInterval: 0.01) // 10ms poll
                    currentQueue = try queryStdinFlowStatus(sessionID: sessionID)
                }
            }

            let end = min(offset + chunkSize, data.count)
            try sendPacket(.execStdin, arg: sessionID, payload: Data(data[offset..<end]), timeout: 3000)
            offset = end
        }

        HakchiLogger.fileLog("clovershell", "writeFile: sent \(data.count) bytes in \(data.count / chunkSize + 1) chunks")

        // Phase 4: Close stdin (empty payload = EOF)
        try sendPacket(.execStdin, arg: sessionID, payload: Data())

        // Phase 5: Drain responses until execResult
        while true {
            let (respCmd, _, _) = try recvPacket(timeout: usbTimeout)
            if respCmd == .execResult { break }
        }

        HakchiLogger.fileLog("clovershell", "writeFile: complete")
    }

    /// Query the device's stdin queue size for flow control.
    /// Sends CMD_EXEC_STDIN_FLOW_STAT_REQ and reads CMD_EXEC_STDIN_FLOW_STAT response.
    /// Returns the current stdin queue size in bytes.
    private func queryStdinFlowStatus(sessionID: UInt8) throws -> Int {
        try sendPacket(.execStdinFlowStatReq, arg: sessionID, payload: Data())

        // Read packets until we get the flow stat response
        // (other packets like stdout/stderr may arrive first)
        for _ in 0..<50 {
            let (cmd, _, payload) = try recvPacket(timeout: 2000)
            if cmd == .execStdinFlowStat && payload.count >= 4 {
                // First 4 bytes: stdinQueue (LE UInt32)
                let queueSize = Int(payload[0]) | (Int(payload[1]) << 8) |
                               (Int(payload[2]) << 16) | (Int(payload[3]) << 24)
                return queueSize
            }
            // If we get something else, keep looking
        }
        // If we can't get flow status, return 0 (allow sending)
        return 0
    }

    /// Kill a specific exec session.
    func killExec(sessionID: UInt8) throws {
        try sendPacket(.execKill, arg: sessionID, payload: Data())
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
    /// Thread-safe: uses writeLock to serialize USB writes.
    private func sendPacket(_ cmd: Command, arg: UInt8, payload: Data, timeout: UInt32 = 1000) throws {
        guard payload.count <= Int(UInt16.max) else {
            throw HakchiError.felCommunicationError(
                "Clovershell payload too large (\(payload.count) bytes, max \(UInt16.max))")
        }

        writeLock.lock()
        defer { writeLock.unlock() }

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
                Int32(pkt.count), &transferred, timeout
            )
        }
        guard rc == 0 else {
            throw HakchiError.felCommunicationError("Clovershell send failed: \(rc)")
        }
    }

    /// Receive the next packet from the USB stream.
    /// Uses a loop (not recursion) to skip unknown commands safely.
    private func recvPacket(timeout: UInt32) throws -> (cmd: Command, arg: UInt8, payload: Data) {
        while true {
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
                    throw HakchiError.felCommunicationError("Clovershell receive timeout")
                } else if rc != 0 {
                    throw HakchiError.felCommunicationError("Clovershell receive failed: \(rc)")
                }
                recvCount = Int(got)
            }

            // Parse header
            let avail = recvCount - recvPos
            guard avail >= 4 else {
                // Not enough data for a header — force a new read
                recvPos = recvCount
                continue
            }

            let cmdByte = recvBuf[recvPos]
            let arg = recvBuf[recvPos + 1]
            let len = Int(recvBuf[recvPos + 2]) | (Int(recvBuf[recvPos + 3]) << 8)
            recvPos += 4

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
                                Int32(bufferSize), &got, timeout
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

            // Try to parse command — skip unknown commands via loop (not recursion)
            if let cmd = Command(rawValue: cmdByte) {
                return (cmd, arg, payload)
            }
            // Unknown command: loop back and read next packet
        }
    }
}

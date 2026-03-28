import Foundation

// MARK: - USB Constants

enum FELConstants {
    static let vendorID: UInt16 = 0x1F3A
    static let productID: UInt16 = 0xEFE8

    static let usbTimeout: UInt32 = 2000 // 2 seconds (C# uses 1s; 2s gives macOS USB stack margin)
    static let bulkChunkSize: Int = 65536  // 64KB

    // AWUSBRequest signatures
    static let requestSignature: [UInt8] = [0x41, 0x57, 0x55, 0x43] // "AWUC"
    static let responseSignature: [UInt8] = [0x41, 0x57, 0x55, 0x53] // "AWUS"

    // USB request types
    static let usbRead: UInt16 = 0x11
    static let usbWrite: UInt16 = 0x12

    // FEL command types
    static let felVerifyDevice: UInt32 = 0x001
    static let felSwitchRole: UInt32 = 0x002
    static let felIsReady: UInt32 = 0x003
    static let felGetCmdSetVer: UInt32 = 0x004
    static let felDisconnect: UInt32 = 0x010
    static let felDownload: UInt32 = 0x101  // Write to device
    static let felExec: UInt32 = 0x102      // Execute code
    static let felUpload: UInt32 = 0x103    // Read from device

    // Memory addresses (verified against hakchi2-CE and working fel-boot.c)
    static let fes1Addr: UInt32 = 0x2000       // FES1 DRAM init binary loads here
    static let dramBase: UInt32 = 0x40000000
    static let splLoadAddr: UInt32 = 0x0000     // Legacy SPL address (unused with FES1)
    static let ubootAddr: UInt32 = 0x47000000   // U-Boot loads here in DRAM
    static let bootImgAddr: UInt32 = 0x47400000 // boot.img loads here in DRAM
    static let scratchAddr: UInt32 = 0x40400000
    static let kernelAddr: UInt32 = 0x40008000
    static let transferMaxSize: UInt32 = 0x10000

    // Size limits (matching C# Fel.cs)
    static let sectorSize: UInt32 = 0x20000       // 128KB — kernel padding alignment
    static let kernelMaxSize: UInt32 = 0x400000   // 4MB — max kernel image
    static let transferMaxTotal: UInt32 = 0x2000000 // 32MB — max boot.img total
    static let ubootMaxSize: UInt32 = 0x200000    // 2MB — max U-Boot binary

    // U-Boot bootcmd patching — offset is found dynamically by searching for "bootcmd="
    // The replacement command simply boots the image in RAM; U-Boot's `boota` reads
    // bootargs from the Android boot image header at 0x47400000, so we do NOT inject
    // setenv bootargs (that would override the boot.img cmdline and break clovershell).
    static let bootcmdRAM: String = "boota 47400000"

    // DRAM initialization — Allwinner R16/A33 (sun8iw5p1) SoC
    static let socR16: UInt32 = 0x1667

    /// SRAM swap buffers: FEL handler state that SPL overwrites.
    /// We save buf1 contents, copy buf2→buf1 before SPL, then restore after.
    static let swapBuffers: [(buf1: UInt32, buf2: UInt32, size: UInt32)] = [
        (buf1: 0x0001800, buf2: 0x44000, size: 0x0800),
        (buf1: 0x0005C00, buf2: 0x44800, size: 0x8000),
    ]

    /// Address in SRAM-C where we write the return-to-FEL thunk after SPL execution.
    static let thunkAddr: UInt32  = 0x0004_6E00
    /// BROM FEL handler entry point — the thunk branches here.
    static let felReturnAddr: UInt32 = 0xFFFF_0020
}

// MARK: - AWUSBRequest (32 bytes — matches sunxi-tools aw_usb_request)

struct AWUSBRequest {
    var requestType: UInt16
    var length: UInt32

    /// Serialize to the 32-byte wire format:
    ///   signature[8] "AWUC\0\0\0\0" + length[4] + unknown1[4] + request[2] + length2[4] + pad[10]
    var data: Data {
        var d = Data(count: 32)
        // signature: "AWUC" + 4 null bytes (8 bytes total)
        d[0] = 0x41; d[1] = 0x57; d[2] = 0x55; d[3] = 0x43 // "AWUC"
        // d[4..7] = 0 (already zeroed)
        // length (little-endian UInt32 at offset 8)
        d[8]  = UInt8(length & 0xFF)
        d[9]  = UInt8((length >> 8) & 0xFF)
        d[10] = UInt8((length >> 16) & 0xFF)
        d[11] = UInt8((length >> 24) & 0xFF)
        // reserved1[2]=0, reserved2=0, cmd_len=0x0C (12 bytes of FEL payload)
        d[12] = 0x00; d[13] = 0x00; d[14] = 0x00; d[15] = 0x0C
        // request type (little-endian UInt16 at offset 16)
        d[16] = UInt8(requestType & 0xFF)
        d[17] = UInt8((requestType >> 8) & 0xFF)
        // length2 = same as length (little-endian UInt32 at offset 18)
        d[18] = UInt8(length & 0xFF)
        d[19] = UInt8((length >> 8) & 0xFF)
        d[20] = UInt8((length >> 16) & 0xFF)
        d[21] = UInt8((length >> 24) & 0xFF)
        // pad[10] at offset 22..31 (already zeroed)
        return d
    }
}

// MARK: - AWFELRequest

struct AWFELRequest {
    var command: UInt16   // FEL command (UInt16 LE — matches C# AWFELStandardRequest.Cmd)
    var tag: UInt16 = 0   // Tag field (UInt16 LE — matches C# AWFELStandardRequest.Tag)
    var address: UInt32 = 0
    var length: UInt32 = 0
    var flags: UInt32 = 0

    /// Convenience init from UInt32 command constant (truncates to UInt16).
    init(command: UInt32, address: UInt32 = 0, length: UInt32 = 0) {
        self.command = UInt16(command & 0xFFFF)
        self.address = address
        self.length = length
    }

    var data: Data {
        var d = Data(count: 16)
        let cmd = command.littleEndian
        let t = tag.littleEndian
        let addr = address.littleEndian
        let len = length.littleEndian
        d[0] = UInt8(cmd & 0xFF); d[1] = UInt8(cmd >> 8)
        d[2] = UInt8(t & 0xFF); d[3] = UInt8(t >> 8)
        d[4] = UInt8(addr & 0xFF); d[5] = UInt8((addr >> 8) & 0xFF)
        d[6] = UInt8((addr >> 16) & 0xFF); d[7] = UInt8((addr >> 24) & 0xFF)
        d[8] = UInt8(len & 0xFF); d[9] = UInt8((len >> 8) & 0xFF)
        d[10] = UInt8((len >> 16) & 0xFF); d[11] = UInt8((len >> 24) & 0xFF)
        let f = flags.littleEndian
        d[12] = UInt8(f & 0xFF); d[13] = UInt8((f >> 8) & 0xFF)
        d[14] = UInt8((f >> 16) & 0xFF); d[15] = UInt8((f >> 24) & 0xFF)
        return d
    }
}

// MARK: - AWUSBResponse

struct AWUSBResponse {
    let signature: [UInt8] // "AWUS"
    let tag: UInt32         // bytes 4-7 (UInt32 LE, matches C# AWUSBResponse.Tag)
    let residue: UInt32     // bytes 8-11 (UInt32 LE)
    let csw_status: UInt8   // byte 12

    init?(data: Data) {
        guard data.count >= 13 else { return nil }
        signature = Array(data[0..<4])
        tag = UInt32(data[4]) | (UInt32(data[5]) << 8) | (UInt32(data[6]) << 16) | (UInt32(data[7]) << 24)
        residue = UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24)
        csw_status = data[12]
    }

    var isValid: Bool {
        signature == FELConstants.responseSignature && csw_status == 0
    }
}

// MARK: - FEL Version Info

struct FELVersion {
    let signature: String
    let socID: UInt32
    let firmwareVersion: UInt32
    let protocolVersion: UInt16
    let dataFlag: UInt8
    let dataLength: UInt8
    let board: String

    static let expectedSignature = "AWUSBFEX"

    init(data: Data) {
        guard data.count >= 32 else {
            signature = ""
            socID = 0
            firmwareVersion = 0
            protocolVersion = 0
            dataFlag = 0
            dataLength = 0
            board = ""
            return
        }

        let sig = String(data: data[0..<8], encoding: .ascii) ?? ""
        signature = sig
        socID = UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24)
        firmwareVersion = UInt32(data[12]) | (UInt32(data[13]) << 8) | (UInt32(data[14]) << 16) | (UInt32(data[15]) << 24)
        protocolVersion = UInt16(data[16]) | (UInt16(data[17]) << 8)
        dataFlag = data[18]
        dataLength = data[19]
        board = String(data: data[20..<min(32, data.count)], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        // Validate the "AWUSBFEX" signature to catch garbage data
        if sig != FELVersion.expectedSignature {
            HakchiLogger.fel.warning("FEL version signature mismatch: expected '\(FELVersion.expectedSignature)', got '\(sig)'")
        }
    }

    var description: String {
        "SoC: \(String(format: "0x%08X", socID)), FW: \(firmwareVersion), Protocol: \(protocolVersion), Board: \(board)"
    }
}

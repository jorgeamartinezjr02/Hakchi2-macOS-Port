import Foundation

// MARK: - USB Constants

enum FELConstants {
    static let vendorID: UInt16 = 0x1F3A
    static let productID: UInt16 = 0xEFE8

    static let usbTimeout: UInt32 = 10000 // 10 seconds
    static let bulkChunkSize: Int = 65536  // 64KB

    // AWUSBRequest signatures
    static let requestSignature: [UInt8] = [0x41, 0x57, 0x55, 0x43] // "AWUC"
    static let responseSignature: [UInt8] = [0x41, 0x57, 0x55, 0x53] // "AWUS"

    // USB request types
    static let usbRead: UInt16 = 0x11
    static let usbWrite: UInt16 = 0x12

    // FEL command types
    static let felVerifyDevice: UInt32 = 0x001
    static let felDownload: UInt32 = 0x101  // Write to device
    static let felExec: UInt32 = 0x102      // Execute code
    static let felUpload: UInt32 = 0x103    // Read from device

    // Memory addresses
    static let felExecAddr: UInt32 = 0x2000
    static let dramBase: UInt32 = 0x40000000
    static let splLoadAddr: UInt32 = 0x0000
    static let ubootAddr: UInt32 = 0x4A000000
    static let scratchAddr: UInt32 = 0x40400000
    static let kernelAddr: UInt32 = 0x40008000
    static let transferMaxSize: UInt32 = 0x10000

    // Kernel constants
    static let kernelOffset: UInt32 = 0x00600000
    static let kernelMaxSize: UInt32 = 0x00200000 // 2MB
}

// MARK: - AWUSBRequest

struct AWUSBRequest {
    let signature: [UInt8] = FELConstants.requestSignature
    var requestType: UInt16
    var length: UInt32
    let unknown1: UInt32 = 0x0C00_0000
    let pad: [UInt8] = Array(repeating: 0, count: 4)

    var data: Data {
        var d = Data()
        d.append(contentsOf: signature)
        d.append(contentsOf: withUnsafeBytes(of: requestType.littleEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: length.littleEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: unknown1.littleEndian) { Array($0) })
        d.append(contentsOf: pad)
        return d
    }
}

// MARK: - AWFELRequest

struct AWFELRequest {
    var command: UInt32
    var address: UInt32
    var length: UInt32
    let pad: UInt32 = 0

    var data: Data {
        var d = Data()
        d.append(contentsOf: withUnsafeBytes(of: command.littleEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: address.littleEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: length.littleEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: pad.littleEndian) { Array($0) })
        return d
    }
}

// MARK: - AWUSBResponse

struct AWUSBResponse {
    let signature: [UInt8] // "AWUS"
    let tag: UInt16
    let residue: UInt32
    let csw_status: UInt8

    init?(data: Data) {
        guard data.count >= 13 else { return nil }
        signature = Array(data[0..<4])
        tag = data[4..<6].withUnsafeBytes { $0.load(as: UInt16.self) }
        residue = data[6..<10].withUnsafeBytes { $0.load(as: UInt32.self) }
        csw_status = data[10]
    }

    var isValid: Bool {
        signature == FELConstants.responseSignature
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

        signature = String(data: data[0..<8], encoding: .ascii) ?? ""
        socID = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        firmwareVersion = data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        protocolVersion = data[16..<18].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        dataFlag = data[18]
        dataLength = data[19]
        board = String(data: data[20..<min(32, data.count)], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
    }

    var description: String {
        "SoC: \(String(format: "0x%08X", socID)), FW: \(firmwareVersion), Protocol: \(protocolVersion), Board: \(board)"
    }
}

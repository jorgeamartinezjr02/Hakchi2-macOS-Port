import XCTest
@testable import Hakchi

final class FELProtocolTests: XCTestCase {
    func testAWUSBRequestSerialization() {
        let request = AWUSBRequest(requestType: FELConstants.usbWrite, length: 16)
        let data = request.data

        // Should be 32 bytes
        XCTAssertEqual(data.count, 32)

        // Check signature "AWUC"
        XCTAssertEqual(Array(data[0..<4]), [0x41, 0x57, 0x55, 0x43])

        // Check length at offset 8 (little-endian UInt32)
        let length = UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24)
        XCTAssertEqual(length, 16)

        // Check cmd_len byte at offset 15
        XCTAssertEqual(data[15], 0x0C)

        // Check request type at offset 16 (little-endian UInt16)
        let reqType = UInt16(data[16]) | (UInt16(data[17]) << 8)
        XCTAssertEqual(reqType, FELConstants.usbWrite)
    }

    func testAWFELRequestSerialization() {
        let request = AWFELRequest(
            command: FELConstants.felVerifyDevice,
            address: 0x40000000,
            length: 0x10000
        )
        let data = request.data

        XCTAssertEqual(data.count, 16)

        // Command is UInt16 LE at offset 0-1
        let cmd = UInt16(data[0]) | (UInt16(data[1]) << 8)
        XCTAssertEqual(UInt32(cmd), FELConstants.felVerifyDevice)

        // Tag is UInt16 LE at offset 2-3 (default 0)
        let tag = UInt16(data[2]) | (UInt16(data[3]) << 8)
        XCTAssertEqual(tag, 0)

        // Address is UInt32 LE at offset 4-7
        let addr = UInt32(data[4]) | (UInt32(data[5]) << 8) | (UInt32(data[6]) << 16) | (UInt32(data[7]) << 24)
        XCTAssertEqual(addr, 0x40000000)

        // Length is UInt32 LE at offset 8-11
        let len = UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24)
        XCTAssertEqual(len, 0x10000)
    }

    func testAWUSBResponseParsing() {
        var data = Data()
        data.append(contentsOf: [0x41, 0x57, 0x55, 0x53]) // "AWUS" signature (bytes 0-3)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // tag UInt32 LE (bytes 4-7)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // residue UInt32 LE (bytes 8-11)
        data.append(0x00) // csw_status (byte 12)

        let response = AWUSBResponse(data: data)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.isValid)
        XCTAssertEqual(response!.csw_status, 0)

        // Test error status detection
        var errorData = data
        errorData[12] = 0x01 // non-zero csw_status
        let errorResponse = AWUSBResponse(data: errorData)
        XCTAssertNotNil(errorResponse)
        XCTAssertFalse(errorResponse!.isValid)
    }

    func testInvalidResponseRejected() {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // wrong signature
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        let response = AWUSBResponse(data: data)
        XCTAssertNotNil(response)
        XCTAssertFalse(response!.isValid)
    }

    func testFELVersionParsing() {
        var data = Data(count: 32)
        // Signature
        let sig: [UInt8] = Array("AWUSBFEX".utf8)
        data.replaceSubrange(0..<8, with: sig)
        // SoC ID (little-endian)
        let socID: UInt32 = 0x1681
        data[8] = UInt8(socID & 0xFF)
        data[9] = UInt8((socID >> 8) & 0xFF)
        data[10] = UInt8((socID >> 16) & 0xFF)
        data[11] = UInt8((socID >> 24) & 0xFF)

        let version = FELVersion(data: data)
        XCTAssertEqual(version.signature, "AWUSBFEX")
        XCTAssertEqual(version.socID, 0x1681)
    }

    func testFELConstants() {
        XCTAssertEqual(FELConstants.vendorID, 0x1F3A)
        XCTAssertEqual(FELConstants.productID, 0xEFE8)
        XCTAssertEqual(FELConstants.felVerifyDevice, 0x001)
        XCTAssertEqual(FELConstants.felDownload, 0x101)
        XCTAssertEqual(FELConstants.felExec, 0x102)
        XCTAssertEqual(FELConstants.felUpload, 0x103)
    }
}

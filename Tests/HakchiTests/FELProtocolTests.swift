import XCTest
@testable import Hakchi

final class FELProtocolTests: XCTestCase {
    func testAWUSBRequestSerialization() {
        let request = AWUSBRequest(requestType: FELConstants.usbWrite, length: 16)
        let data = request.data

        // Should be 16 bytes (4 sig + 2 type + 4 len + 4 unknown + 2 pad)
        XCTAssertEqual(data.count, 16)

        // Check signature "AWUC"
        XCTAssertEqual(Array(data[0..<4]), [0x41, 0x57, 0x55, 0x43])

        // Check request type (little-endian) - safe byte reading
        let reqType = UInt16(data[4]) | (UInt16(data[5]) << 8)
        XCTAssertEqual(reqType, FELConstants.usbWrite)

        // Check length - safe byte reading
        let length = UInt32(data[6]) | (UInt32(data[7]) << 8) | (UInt32(data[8]) << 16) | (UInt32(data[9]) << 24)
        XCTAssertEqual(length, 16)
    }

    func testAWFELRequestSerialization() {
        let request = AWFELRequest(
            command: FELConstants.felVerifyDevice,
            address: 0x40000000,
            length: 0x10000
        )
        let data = request.data

        XCTAssertEqual(data.count, 16)

        // Safe byte reading for little-endian values
        let cmd = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        XCTAssertEqual(cmd, FELConstants.felVerifyDevice)

        let addr = UInt32(data[4]) | (UInt32(data[5]) << 8) | (UInt32(data[6]) << 16) | (UInt32(data[7]) << 24)
        XCTAssertEqual(addr, 0x40000000)

        let len = UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24)
        XCTAssertEqual(len, 0x10000)
    }

    func testAWUSBResponseParsing() {
        var data = Data()
        data.append(contentsOf: [0x41, 0x57, 0x55, 0x53]) // "AWUS"
        data.append(contentsOf: [0x00, 0x00]) // tag
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // residue
        data.append(0x00) // csw_status
        data.append(contentsOf: [0x00, 0x00]) // padding

        let response = AWUSBResponse(data: data)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.isValid)
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

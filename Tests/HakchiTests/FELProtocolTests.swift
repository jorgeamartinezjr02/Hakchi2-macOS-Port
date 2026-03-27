import XCTest
@testable import Hakchi

final class FELProtocolTests: XCTestCase {
    func testAWUSBRequestSerialization() {
        let request = AWUSBRequest(requestType: FELConstants.usbWrite, length: 16)
        let data = request.data

        // Should be 16 bytes
        XCTAssertEqual(data.count, 16)

        // Check signature "AWUC"
        XCTAssertEqual(Array(data[0..<4]), [0x41, 0x57, 0x55, 0x43])

        // Check request type (little-endian)
        let reqType = data[4..<6].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(reqType, FELConstants.usbWrite)

        // Check length
        let length = data[6..<10].withUnsafeBytes { $0.load(as: UInt32.self) }
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

        let cmd = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(cmd, FELConstants.felVerifyDevice)

        let addr = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(addr, 0x40000000)

        let len = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
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
        let sig = "AWUSBFEX".data(using: .ascii)!
        data.replaceSubrange(0..<8, with: sig)
        // SoC ID
        data.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32(0x1681).littleEndian) { Data($0) })

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

import Foundation

struct CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func calculate(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }

    static func calculate(fileAt url: URL) throws -> UInt32 {
        let data = try Data(contentsOf: url)
        return calculate(data: data)
    }

    static func hexString(for value: UInt32) -> String {
        String(format: "%08X", value)
    }

    static func hexString(data: Data) -> String {
        hexString(for: calculate(data: data))
    }

    static func hexString(fileAt url: URL) throws -> String {
        hexString(for: try calculate(fileAt: url))
    }
}

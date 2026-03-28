import Foundation

struct BootImage {
    static let magic = "ANDROID!"

    var kernelSize: UInt32
    var kernelAddr: UInt32
    var ramdiskSize: UInt32
    var ramdiskAddr: UInt32
    var secondSize: UInt32
    var secondAddr: UInt32
    var tagsAddr: UInt32
    var pageSize: UInt32
    var name: String
    var cmdline: String

    var kernelData: Data
    var ramdiskData: Data

    private static func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset+1]) << 8) |
        (UInt32(data[offset+2]) << 16) |
        (UInt32(data[offset+3]) << 24)
    }

    init?(data: Data) {
        guard data.count >= 40 else { return nil }
        let header = String(data: data[0..<8], encoding: .ascii) ?? ""
        guard header == BootImage.magic else { return nil }

        kernelSize = Self.readU32LE(data, offset: 8)
        kernelAddr = Self.readU32LE(data, offset: 12)
        ramdiskSize = Self.readU32LE(data, offset: 16)
        ramdiskAddr = Self.readU32LE(data, offset: 20)
        secondSize = Self.readU32LE(data, offset: 24)
        secondAddr = Self.readU32LE(data, offset: 28)
        tagsAddr = Self.readU32LE(data, offset: 32)
        pageSize = Self.readU32LE(data, offset: 36)

        guard pageSize > 0 else { return nil }

        name = String(data: data[40..<56], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        cmdline = String(data: data[64..<576], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        let page = Int(pageSize)
        let kernelPages = (Int(kernelSize) + page - 1) / page
        let kernelStart = page
        let kernelEnd = kernelStart + kernelPages * page

        let ramdiskPages = (Int(ramdiskSize) + page - 1) / page
        let ramdiskStart = kernelEnd
        let ramdiskEnd = ramdiskStart + ramdiskPages * page

        guard data.count >= ramdiskEnd else { return nil }

        kernelData = data[kernelStart..<(kernelStart + Int(kernelSize))]
        ramdiskData = data[ramdiskStart..<(ramdiskStart + Int(ramdiskSize))]
    }

    private static func writeU32LE(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    func toData() -> Data {
        let page = Int(pageSize)
        var result = Data()

        // Header page
        var header = Data(count: page)
        header[0..<8] = Data(BootImage.magic.utf8)
        header.replaceSubrange(8..<12, with: Self.writeU32LE(kernelSize))
        header.replaceSubrange(12..<16, with: Self.writeU32LE(kernelAddr))
        header.replaceSubrange(16..<20, with: Self.writeU32LE(ramdiskSize))
        header.replaceSubrange(20..<24, with: Self.writeU32LE(ramdiskAddr))
        header.replaceSubrange(24..<28, with: Self.writeU32LE(secondSize))
        header.replaceSubrange(28..<32, with: Self.writeU32LE(secondAddr))
        header.replaceSubrange(32..<36, with: Self.writeU32LE(tagsAddr))
        header.replaceSubrange(36..<40, with: Self.writeU32LE(pageSize))

        let nameData = Data(name.utf8.prefix(16))
        header.replaceSubrange(40..<(40 + nameData.count), with: nameData)

        let cmdlineData = Data(cmdline.utf8.prefix(512))
        header.replaceSubrange(64..<(64 + cmdlineData.count), with: cmdlineData)

        result.append(header)

        // Kernel pages
        var kernelPadded = kernelData
        let kernelPadding = (page - (Int(kernelSize) % page)) % page
        kernelPadded.append(Data(count: kernelPadding))
        result.append(kernelPadded)

        // Ramdisk pages
        var ramdiskPadded = ramdiskData
        let ramdiskPadding = (page - (Int(ramdiskSize) % page)) % page
        ramdiskPadded.append(Data(count: ramdiskPadding))
        result.append(ramdiskPadded)

        return result
    }
}

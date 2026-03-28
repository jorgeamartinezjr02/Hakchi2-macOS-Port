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
    var dtSize: UInt32       // Device tree size (offset 40 in some builds, 1632 in v1 header)
    var name: String
    var cmdline: String

    var kernelData: Data
    var ramdiskData: Data
    var secondData: Data     // Second-stage bootloader data (usually empty)

    // Raw data beyond ramdisk+second (preserves dt blob and any trailing data)
    private var trailingData: Data

    private static func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset+1]) << 8) |
        (UInt32(data[offset+2]) << 16) |
        (UInt32(data[offset+3]) << 24)
    }

    init?(data: Data) {
        // Minimum: header (1 page, at least 576 bytes for cmdline) + some kernel data
        guard data.count >= 576 else { return nil }
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

        // dt_size at offset 40 (some Android boot image variants use bytes 40-43)
        dtSize = Self.readU32LE(data, offset: 40)
        // If dtSize looks unreasonable (> 16MB or overlaps with name field ASCII), it's the name field
        if dtSize > 0x1000000 {
            dtSize = 0
        }

        guard pageSize > 0 else { return nil }

        // Name is at offset 44 if dtSize is present, or 40 if not — but standard layout
        // has name[16] at 48 and cmdline[512] at 64. We use the standard offsets.
        name = String(data: data[48..<min(64, data.count)], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        cmdline = String(data: data[64..<min(576, data.count)], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        let page = Int(pageSize)

        // Calculate page-aligned offsets for each section
        let kernelPages = (Int(kernelSize) + page - 1) / page
        let kernelStart = page  // First page is header
        let kernelEnd = kernelStart + kernelPages * page

        let ramdiskPages = (Int(ramdiskSize) + page - 1) / page
        let ramdiskStart = kernelEnd
        let ramdiskEnd = ramdiskStart + ramdiskPages * page

        let secondPages = (Int(secondSize) + page - 1) / page
        let secondStart = ramdiskEnd
        let secondEnd = secondStart + secondPages * page

        guard data.count >= ramdiskStart + Int(ramdiskSize) else { return nil }

        kernelData = data[kernelStart..<(kernelStart + Int(kernelSize))]
        ramdiskData = data[ramdiskStart..<(ramdiskStart + Int(ramdiskSize))]

        if secondSize > 0 && data.count >= secondStart + Int(secondSize) {
            secondData = data[secondStart..<(secondStart + Int(secondSize))]
        } else {
            secondData = Data()
        }

        // Preserve everything after second section (dt blob, etc.)
        if data.count > secondEnd {
            trailingData = data[secondEnd...]
        } else {
            trailingData = Data()
        }
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
        header.replaceSubrange(40..<44, with: Self.writeU32LE(dtSize))

        let nameData = Data(name.utf8.prefix(16))
        header.replaceSubrange(48..<(48 + nameData.count), with: nameData)

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

        // Second bootloader pages (if present)
        if secondSize > 0 {
            var secondPadded = secondData
            let secondPadding = (page - (Int(secondSize) % page)) % page
            secondPadded.append(Data(count: secondPadding))
            result.append(secondPadded)
        }

        // Trailing data (dt blob, etc.)
        if !trailingData.isEmpty {
            result.append(trailingData)
        }

        return result
    }
}

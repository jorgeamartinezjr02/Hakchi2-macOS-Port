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

    init?(data: Data) {
        guard data.count >= 1648 else { return nil }
        let header = String(data: data[0..<8], encoding: .ascii) ?? ""
        guard header == BootImage.magic else { return nil }

        kernelSize = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        kernelAddr = data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        ramdiskSize = data[16..<20].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        ramdiskAddr = data[20..<24].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        secondSize = data[24..<28].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        secondAddr = data[28..<32].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        tagsAddr = data[32..<36].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        pageSize = data[36..<40].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

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

    func toData() -> Data {
        let page = Int(pageSize)
        var result = Data()

        // Header page
        var header = Data(count: page)
        header[0..<8] = Data(BootImage.magic.utf8)
        header.replaceSubrange(8..<12, with: withUnsafeBytes(of: kernelSize.littleEndian) { Data($0) })
        header.replaceSubrange(12..<16, with: withUnsafeBytes(of: kernelAddr.littleEndian) { Data($0) })
        header.replaceSubrange(16..<20, with: withUnsafeBytes(of: ramdiskSize.littleEndian) { Data($0) })
        header.replaceSubrange(20..<24, with: withUnsafeBytes(of: ramdiskAddr.littleEndian) { Data($0) })
        header.replaceSubrange(24..<28, with: withUnsafeBytes(of: secondSize.littleEndian) { Data($0) })
        header.replaceSubrange(28..<32, with: withUnsafeBytes(of: secondAddr.littleEndian) { Data($0) })
        header.replaceSubrange(32..<36, with: withUnsafeBytes(of: tagsAddr.littleEndian) { Data($0) })
        header.replaceSubrange(36..<40, with: withUnsafeBytes(of: pageSize.littleEndian) { Data($0) })

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

import Foundation
import AppKit

/// Capture screenshots from a connected console by reading the framebuffer.
final class ScreenshotCapture {

    /// Capture a screenshot from the console's framebuffer.
    static func capture(shell: ShellInterface) async throws -> NSImage {
        // Read framebuffer info
        let fbInfo = try await shell.executeCommand("cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo '1280,720'")
        let parts = fbInfo.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        let width = Int(parts.first ?? "1280") ?? 1280
        let height = Int(parts.last ?? "720") ?? 720

        // Read framebuffer data
        let remotePath = "/dev/fb0"
        let localPath = FileManager.default.temporaryDirectory.appendingPathComponent("hakchi_screenshot_\(UUID().uuidString).raw").path

        try await shell.downloadFile(remotePath: remotePath, localPath: localPath, progress: nil)

        defer { try? FileManager.default.removeItem(atPath: localPath) }

        let rawData = try Data(contentsOf: URL(fileURLWithPath: localPath))

        // Convert raw BGRA/RGB565 framebuffer to NSImage
        guard let image = createImage(from: rawData, width: width, height: height) else {
            throw HakchiError.invalidData("Failed to create image from framebuffer data")
        }

        return image
    }

    /// Save a screenshot to disk.
    static func saveScreenshot(_ image: NSImage, to directory: URL? = nil) throws -> URL {
        let dir = directory ?? FileUtils.hakchiDirectory.appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "screenshot_\(ISO8601DateFormatter().string(from: Date())).png"
            .replacingOccurrences(of: ":", with: "-")
        let path = dir.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw HakchiError.invalidData("Failed to encode screenshot as PNG")
        }

        try pngData.write(to: path)
        HakchiLogger.general.info("Screenshot saved to \(path.path)")
        return path
    }

    // MARK: - Private

    private static func createImage(from data: Data, width: Int, height: Int) -> NSImage? {
        let bytesPerPixel: Int
        let bitsPerComponent: Int
        let bitmapInfo: CGBitmapInfo

        // Detect format from data size
        let expectedRGBA = width * height * 4
        let expectedRGB565 = width * height * 2

        if data.count >= expectedRGBA {
            bytesPerPixel = 4
            bitsPerComponent = 8
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        } else if data.count >= expectedRGB565 {
            // Convert RGB565 to RGBA
            var rgbaData = Data(count: expectedRGBA)
            for i in 0..<(width * height) {
                let offset = i * 2
                guard offset + 1 < data.count else { break }
                let pixel = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                let r = UInt8(((pixel >> 11) & 0x1F) * 255 / 31)
                let g = UInt8(((pixel >> 5) & 0x3F) * 255 / 63)
                let b = UInt8((pixel & 0x1F) * 255 / 31)
                let rgbaOffset = i * 4
                rgbaData[rgbaOffset] = r
                rgbaData[rgbaOffset + 1] = g
                rgbaData[rgbaOffset + 2] = b
                rgbaData[rgbaOffset + 3] = 255
            }
            return createRGBAImage(from: rgbaData, width: width, height: height)
        } else {
            return nil
        }

        return data.withUnsafeBytes { ptr -> NSImage? in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
    }

    private static func createRGBAImage(from data: Data, width: Int, height: Int) -> NSImage? {
        return data.withUnsafeBytes { ptr -> NSImage? in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
    }
}

import Foundation
import AppKit

/// Manages box art / cover art downloading, caching, and thumbnail generation.
final class BoxArtManager {
    static let shared = BoxArtManager()

    static let coverArtDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("covers", isDirectory: true)
    }()

    static let thumbnailDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }()

    private init() {
        ensureDirectories()
    }

    // MARK: - Public API

    /// Get the cover art path for a game (returns nil if not cached).
    func coverArtPath(for game: Game) -> String? {
        let path = Self.coverArtDirectory.appendingPathComponent("\(game.romCRC32).png").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Get the thumbnail path for a game (returns nil if not cached).
    func thumbnailPath(for game: Game) -> String? {
        let path = Self.thumbnailDirectory.appendingPathComponent("\(game.romCRC32)_thumb.png").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Download and cache cover art from a URL.
    func downloadCoverArt(for game: Game, from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try saveCoverArt(data: data, for: game)
    }

    /// Save cover art data and generate thumbnail.
    func saveCoverArt(data: Data, for game: Game) throws -> String {
        ensureDirectories()

        let coverPath = Self.coverArtDirectory.appendingPathComponent("\(game.romCRC32).png")
        try data.write(to: coverPath)

        // Generate thumbnail
        generateThumbnail(from: coverPath, for: game)

        HakchiLogger.games.info("Saved cover art for \(game.name)")
        return coverPath.path
    }

    /// Save cover art from a local file.
    func setCoverArt(from localURL: URL, for game: Game) throws -> String {
        let data = try Data(contentsOf: localURL)
        return try saveCoverArt(data: data, for: game)
    }

    /// Remove cover art for a game.
    func removeCoverArt(for game: Game) {
        let coverPath = Self.coverArtDirectory.appendingPathComponent("\(game.romCRC32).png")
        let thumbPath = Self.thumbnailDirectory.appendingPathComponent("\(game.romCRC32)_thumb.png")
        try? FileManager.default.removeItem(at: coverPath)
        try? FileManager.default.removeItem(at: thumbPath)
    }

    /// Generate console-format thumbnail (40x58 for NES/SNES Classic).
    func generateThumbnail(from imagePath: URL, for game: Game) {
        guard let image = NSImage(contentsOf: imagePath) else { return }

        let thumbSize: NSSize
        if game.consoleType.isSega {
            thumbSize = NSSize(width: 40, height: 58)
        } else {
            thumbSize = NSSize(width: 40, height: 58)
        }

        guard let thumbnail = resizeImage(image, to: thumbSize) else { return }

        let thumbPath = Self.thumbnailDirectory.appendingPathComponent("\(game.romCRC32)_thumb.png")
        savePNG(thumbnail, to: thumbPath)
    }

    /// Generate a PNG for console upload (228x204 or system-specific).
    func generateConsolePNG(for game: Game) -> Data? {
        let coverPath = Self.coverArtDirectory.appendingPathComponent("\(game.romCRC32).png")
        guard let image = NSImage(contentsOf: coverPath) else { return nil }

        let targetSize = NSSize(width: 228, height: 204)
        guard let resized = resizeImage(image, to: targetSize) else { return nil }

        return pngData(from: resized)
    }

    // MARK: - Private

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [Self.coverArtDirectory, Self.thumbnailDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage? {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func savePNG(_ image: NSImage, to url: URL) {
        guard let data = pngData(from: image) else { return }
        try? data.write(to: url)
    }
}

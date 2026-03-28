import Foundation

/// Manages hakchi boot resources (boot.img, uboot.bin, base hmods).
/// Bundled resources from Resources/boot/ are used first; downloads are a fallback.
final class HakchiResources {
    static let shared = HakchiResources()

    static let resourcesDirectory: URL = {
        FileUtils.hakchiDirectory.appendingPathComponent("resources", isDirectory: true)
    }()

    static let bootImgPath: URL = {
        resourcesDirectory.appendingPathComponent("boot.img")
    }()

    static let ubootPath: URL = {
        resourcesDirectory.appendingPathComponent("uboot.bin")
    }()

    static let fes1Path: URL = {
        resourcesDirectory.appendingPathComponent("fes1.bin")
    }()

    static let baseHmodsPath: URL = {
        resourcesDirectory.appendingPathComponent("basehmods", isDirectory: true)
    }()

    // hakchi release info
    private let githubAPIURL = "https://api.github.com/repos/TeamShinkansen/Hakchi2-CE/releases/latest"
    private let session = URLSession.shared

    private init() {
        ensureDirectories()
        copyBundledResourcesIfNeeded()
    }

    /// Whether the required boot resources are available locally.
    var isReady: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: Self.bootImgPath.path)
            && fm.fileExists(atPath: Self.ubootPath.path)
            && fm.fileExists(atPath: Self.fes1Path.path)
    }

    /// Copy bundled boot resources from the app bundle to the working directory.
    private func copyBundledResourcesIfNeeded() {
        let fm = FileManager.default
        let bundle = Bundle.main
        let resources: [(resourceName: String, ext: String, dest: URL)] = [
            ("boot", "img", Self.bootImgPath),
            ("uboot", "bin", Self.ubootPath),
            ("fes1", "bin", Self.fes1Path),
        ]
        for (name, ext, dest) in resources {
            guard !fm.fileExists(atPath: dest.path) else { continue }
            if let src = bundle.url(forResource: name, withExtension: ext, subdirectory: "boot") {
                try? fm.copyItem(at: src, to: dest)
                HakchiLogger.kernel.info("Copied bundled \(name).\(ext) to working directory")
            } else if let src = bundle.url(forResource: "\(name).\(ext)", withExtension: nil) {
                try? fm.copyItem(at: src, to: dest)
                HakchiLogger.kernel.info("Copied bundled \(name).\(ext) to working directory")
            }
        }
    }

    /// Ensure boot resources are available, copying from bundle or downloading as fallback.
    func ensureResources(progress: @escaping (Double, String) -> Void) async throws {
        // Re-try copy in case init ran before bundle was ready
        copyBundledResourcesIfNeeded()

        if isReady {
            progress(1.0, "Resources ready")
            return
        }

        // Fallback: download from latest GitHub release
        progress(0.0, "Fetching latest release info...")

        let portableURL = try await fetchPortableZipURL()

        progress(0.05, "Downloading hakchi release (~75MB)...")

        let zipLocalPath = Self.resourcesDirectory.appendingPathComponent("hakchi-portable.zip")
        try await downloadFile(from: portableURL, to: zipLocalPath, progress: { p in
            progress(0.05 + p * 0.75, "Downloading... \(Int(p * 100))%")
        })

        progress(0.80, "Extracting hakchi.hmod...")
        try extractHmodFromZip(zipPath: zipLocalPath)
        try? FileManager.default.removeItem(at: zipLocalPath)

        progress(1.0, "Resources ready")
        HakchiLogger.kernel.info("Hakchi resources downloaded and extracted")
    }

    /// Fetch the URL of the portable zip from the latest GitHub release.
    private func fetchPortableZipURL() async throws -> String {
        guard let apiURL = URL(string: githubAPIURL) else {
            throw HakchiError.invalidData("Invalid GitHub API URL")
        }
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw HakchiError.invalidData("Could not parse GitHub release info")
        }
        for asset in assets {
            if let name = asset["name"] as? String,
               let url = asset["browser_download_url"] as? String,
               name.contains("portable") && name.hasSuffix(".zip") {
                return url
            }
        }
        throw HakchiError.invalidData("Could not find portable.zip in latest release assets")
    }

    /// Get the boot.img data for memboot.
    func getBootImage() throws -> Data {
        guard FileManager.default.fileExists(atPath: Self.bootImgPath.path) else {
            throw HakchiError.kernelFlashFailed("boot.img not found. Run Install to download resources.")
        }
        return try Data(contentsOf: Self.bootImgPath)
    }

    /// Get the u-boot binary for FEL boot.
    func getUBoot() throws -> Data {
        guard FileManager.default.fileExists(atPath: Self.ubootPath.path) else {
            throw HakchiError.kernelFlashFailed("uboot.bin not found. Run Install to download resources.")
        }
        return try Data(contentsOf: Self.ubootPath)
    }

    /// Get the FES1 binary for DRAM initialization.
    func getFES1() throws -> Data {
        guard FileManager.default.fileExists(atPath: Self.fes1Path.path) else {
            throw HakchiError.kernelFlashFailed("fes1.bin not found. Run Install to download resources.")
        }
        return try Data(contentsOf: Self.fes1Path)
    }

    /// Allow user to provide their own boot.img.
    func importBootImage(from url: URL) throws {
        ensureDirectories()
        let dest = Self.bootImgPath
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        HakchiLogger.kernel.info("Custom boot.img imported from \(url.path)")
    }

    // MARK: - Private

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [Self.resourcesDirectory, Self.baseHmodsPath] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func downloadFile(from urlString: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard let url = URL(string: urlString) else {
            throw HakchiError.invalidData("Invalid download URL")
        }

        let (asyncBytes, response) = try await session.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HakchiError.invalidData("Download failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let totalBytes = Int(httpResponse.expectedContentLength)
        var receivedBytes = 0
        var buffer = Data()
        buffer.reserveCapacity(min(totalBytes, 80 * 1024 * 1024))

        for try await byte in asyncBytes {
            buffer.append(byte)
            receivedBytes += 1
            if totalBytes > 0 && receivedBytes % 65536 == 0 {
                progress(Double(receivedBytes) / Double(totalBytes))
            }
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try buffer.write(to: localURL)
        progress(1.0)
    }

    /// Extract hakchi.hmod from the portable ZIP (nested: zip → basehmods.tar → hakchi.hmod → boot.img)
    private func extractHmodFromZip(zipPath: URL) throws {
        let workDir = Self.resourcesDirectory.appendingPathComponent("zip_extract")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Step 1: Extract basehmods.tar from the zip
        let basehmodsTar = workDir.appendingPathComponent("basehmods.tar")
        let unzipResult = try runProcess("/usr/bin/unzip", args: [
            "-o", zipPath.path, "basehmods.tar", "-d", workDir.path
        ])
        guard FileManager.default.fileExists(atPath: basehmodsTar.path) else {
            throw HakchiError.invalidData("basehmods.tar not found in portable zip. \(unzipResult)")
        }

        // Step 2: Extract hakchi.hmod from basehmods.tar
        let hmodPath = workDir.appendingPathComponent("hakchi.hmod")
        _ = try runProcess("/usr/bin/tar", args: [
            "-xf", basehmodsTar.path, "-C", workDir.path, "./hakchi.hmod"
        ])
        guard FileManager.default.fileExists(atPath: hmodPath.path) else {
            throw HakchiError.invalidData("hakchi.hmod not found in basehmods.tar")
        }

        // Step 3: Extract boot resources from hakchi.hmod (which is a tar.gz)
        try extractBootResources(from: hmodPath)
    }

    private func extractBootResources(from hmodPath: URL) throws {
        let extractDir = Self.resourcesDirectory.appendingPathComponent("hmod_extract")
        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: extractDir)
        }

        // hakchi.hmod is a tar.gz archive
        try FileUtils.extractTarGz(at: hmodPath, to: extractDir)

        // Look for boot.img and uboot.bin inside extracted contents
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                let name = fileURL.lastPathComponent
                if name == "boot.img" && !fm.fileExists(atPath: Self.bootImgPath.path) {
                    try fm.copyItem(at: fileURL, to: Self.bootImgPath)
                } else if name == "uboot.bin" && !fm.fileExists(atPath: Self.ubootPath.path) {
                    try fm.copyItem(at: fileURL, to: Self.ubootPath)
                }
            }
        }

        if !fm.fileExists(atPath: Self.bootImgPath.path) {
            HakchiLogger.kernel.warning("boot.img not found in hakchi.hmod archive")
        }
    }

    @discardableResult
    private func runProcess(_ executable: String, args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
    }
}

import Foundation

/// Centralized app settings that reads from @AppStorage / UserDefaults.
/// Other components read from here instead of hardcoding values.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Console

    var defaultConsoleType: ConsoleType {
        let raw = defaults.string(forKey: "defaultConsoleType") ?? "SNES Classic (USA)"
        return ConsoleType(rawValue: raw) ?? .snesUSA
    }

    var autoDetectConsole: Bool {
        defaults.object(forKey: "autoDetectConsole") as? Bool ?? true
    }

    // MARK: - Connection

    var sshHost: String {
        defaults.string(forKey: "sshHost") ?? "169.254.1.1"
    }

    var sshPort: Int {
        let port = defaults.integer(forKey: "sshPort")
        return port > 0 ? port : 22
    }

    // MARK: - Safety

    var backupKernelBeforeFlash: Bool {
        defaults.object(forKey: "backupKernelBeforeFlash") as? Bool ?? true
    }

    // MARK: - Interface

    var showAdvancedOptions: Bool {
        defaults.object(forKey: "showAdvancedOptions") as? Bool ?? false
    }

    // MARK: - Portable mode

    var isPortableMode: Bool {
        let executableDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let portableMarker = executableDir.appendingPathComponent("portable.ini")
        return FileManager.default.fileExists(atPath: portableMarker.path)
    }

    var dataDirectory: URL {
        if isPortableMode {
            return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hakchi_data")
        }
        return FileUtils.hakchiDirectory
    }
}

import Foundation

/// Supported languages for the app.
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case korean = "ko"
    case arabic = "ar"
    case swedish = "sv"
    case japanese = "ja"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .swedish: return "Svenska"
        case .japanese: return "日本語"
        }
    }
}

/// Localization string keys used throughout the app.
/// Using String(localized:) for SwiftUI integration.
enum L10n {
    // Connection
    static var connected: String { String(localized: "Connected") }
    static var disconnected: String { String(localized: "Disconnected") }
    static var felMode: String { String(localized: "FEL Mode") }
    static var busy: String { String(localized: "Busy") }

    // Actions
    static var syncGames: String { String(localized: "Sync Games") }
    static var addGames: String { String(localized: "Add Games") }
    static var dumpKernel: String { String(localized: "Dump Kernel") }
    static var flashKernel: String { String(localized: "Flash Kernel") }
    static var restoreKernel: String { String(localized: "Restore Kernel") }
    static var rebootConsole: String { String(localized: "Reboot Console") }

    // Game Detail
    static var romDetails: String { String(localized: "ROM Details") }
    static var editGameInfo: String { String(localized: "Edit Game Info") }
    static var saveChanges: String { String(localized: "Save Changes") }
    static var revert: String { String(localized: "Revert") }
    static var scrapeMetadata: String { String(localized: "Scrape Metadata") }
    static var setCoverArt: String { String(localized: "Set Cover Art") }

    // Folders
    static var folderManager: String { String(localized: "Folder Manager") }
    static var autoSplit: String { String(localized: "Auto-Split") }
    static var resetFolders: String { String(localized: "Reset Folders") }

    // Mods
    static var modManager: String { String(localized: "Mod Manager") }
    static var installed: String { String(localized: "Installed") }
    static var available: String { String(localized: "Available") }

    // Settings
    static var general: String { String(localized: "General") }
    static var connection: String { String(localized: "Connection") }
    static var console: String { String(localized: "Console") }

    // Errors
    static var error: String { String(localized: "Error") }
    static var syncFailed: String { String(localized: "Sync Failed") }

    // Progress
    static var uploading: String { String(localized: "Uploading") }
    static var downloading: String { String(localized: "Downloading") }
    static var complete: String { String(localized: "Complete") }
}

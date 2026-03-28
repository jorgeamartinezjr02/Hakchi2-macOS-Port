import Foundation

enum HakchiError: LocalizedError {
    case notConnected
    case usbInitFailed
    case deviceNotFound
    case felCommunicationError(String)
    case kernelDumpFailed(String)
    case kernelFlashFailed(String)
    case sshConnectionFailed(String)
    case sftpTransferFailed(String)
    case romNotSupported(String)
    case romTooLarge(String, Int64)
    case gameNotFound(String)
    case modInstallFailed(String)
    case modParseFailed(String)
    case extractionFailed(String)
    case compressionFailed(String)
    case storageFull
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Console is not connected"
        case .usbInitFailed:
            return "Failed to initialize USB subsystem"
        case .deviceNotFound:
            return "No compatible console found. Connect your NES/SNES Classic, Famicom/Super Famicom Mini, or Genesis/Mega Drive Mini and enter FEL mode."
        case .felCommunicationError(let msg):
            return "FEL communication error: \(msg)"
        case .kernelDumpFailed(let msg):
            return "Kernel dump failed: \(msg)"
        case .kernelFlashFailed(let msg):
            return "Kernel flash failed: \(msg)"
        case .sshConnectionFailed(let msg):
            return "SSH connection failed: \(msg)"
        case .sftpTransferFailed(let msg):
            return "File transfer failed: \(msg)"
        case .romNotSupported(let ext):
            return "ROM format not supported: \(ext)"
        case .romTooLarge(let name, let size):
            return "ROM '\(name)' is too large (\(size / 1024 / 1024)MB)"
        case .gameNotFound(let name):
            return "Game not found: \(name)"
        case .modInstallFailed(let msg):
            return "Mod installation failed: \(msg)"
        case .modParseFailed(let msg):
            return "Failed to parse mod: \(msg)"
        case .extractionFailed(let file):
            return "Failed to extract: \(file)"
        case .compressionFailed(let file):
            return "Failed to compress: \(file)"
        case .storageFull:
            return "Console storage is full"
        case .invalidData(let msg):
            return "Invalid data: \(msg)"
        }
    }
}

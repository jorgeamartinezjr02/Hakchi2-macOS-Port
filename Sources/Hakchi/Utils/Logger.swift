import Foundation
import os

enum HakchiLogger {
    private static let subsystem = "com.hakchi.macos"

    static let general = os.Logger(subsystem: subsystem, category: "general")
    static let usb = os.Logger(subsystem: subsystem, category: "usb")
    static let fel = os.Logger(subsystem: subsystem, category: "fel")
    static let ssh = os.Logger(subsystem: subsystem, category: "ssh")
    static let games = os.Logger(subsystem: subsystem, category: "games")
    static let mods = os.Logger(subsystem: subsystem, category: "mods")
    static let kernel = os.Logger(subsystem: subsystem, category: "kernel")

    // MARK: - File logging

    private static let logFile: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("hakchi2/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hakchi_debug.log")
    }()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    /// Write a line to ~/hakchi2/logs/hakchi_debug.log
    static func fileLog(_ category: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fh = try? FileHandle(forWritingTo: logFile) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    /// Clear the log file (call at start of each operation)
    static func clearLog() {
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
    }
}

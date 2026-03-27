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
}

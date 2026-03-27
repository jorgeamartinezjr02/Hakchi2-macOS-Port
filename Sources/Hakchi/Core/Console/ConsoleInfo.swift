import Foundation

struct ConsoleInfo {
    var consoleType: ConsoleType
    var firmwareVersion: String
    var serialNumber: String
    var hakchiVersion: String
    var totalStorage: Int64
    var usedStorage: Int64
    var macAddress: String

    var freeStorage: Int64 {
        totalStorage - usedStorage
    }

    var storageUsagePercent: Double {
        guard totalStorage > 0 else { return 0 }
        return Double(usedStorage) / Double(totalStorage) * 100
    }

    init(
        consoleType: ConsoleType = .unknown,
        firmwareVersion: String = "",
        serialNumber: String = "",
        hakchiVersion: String = "",
        totalStorage: Int64 = 0,
        usedStorage: Int64 = 0,
        macAddress: String = ""
    ) {
        self.consoleType = consoleType
        self.firmwareVersion = firmwareVersion
        self.serialNumber = serialNumber
        self.hakchiVersion = hakchiVersion
        self.totalStorage = totalStorage
        self.usedStorage = usedStorage
        self.macAddress = macAddress
    }
}

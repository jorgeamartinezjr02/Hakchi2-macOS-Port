import Foundation

enum ConsoleState: String, Equatable {
    case disconnected
    case felMode
    case connected
    case busy

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .felMode: return "FEL Mode"
        case .connected: return "Connected"
        case .busy: return "Busy"
        }
    }

    var statusColor: String {
        switch self {
        case .disconnected: return "red"
        case .felMode: return "orange"
        case .connected: return "green"
        case .busy: return "yellow"
        }
    }
}

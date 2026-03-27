import Foundation

struct SyncOperation: Identifiable {
    let id = UUID()
    let type: SyncOperationType
    let game: Game
    var status: SyncStatus = .pending
    var progress: Double = 0

    enum SyncOperationType {
        case upload
        case delete
        case update
    }

    enum SyncStatus {
        case pending
        case inProgress
        case completed
        case failed(String)
    }
}

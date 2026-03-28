import Foundation

/// A task that can be queued and executed.
struct HakchiTask: Identifiable {
    let id: UUID
    let name: String
    let action: () async throws -> Void
    var status: TaskStatus = .pending
    var progress: Double = 0
    var message: String = ""

    enum TaskStatus: String {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    init(id: UUID = UUID(), name: String, action: @escaping () async throws -> Void) {
        self.id = id
        self.name = name
        self.action = action
    }
}

/// Manages a queue of tasks that execute serially or in parallel.
@MainActor
final class TaskQueue: ObservableObject {
    static let shared = TaskQueue()

    @Published var tasks: [HakchiTask] = []
    @Published var isRunning = false
    @Published var currentTaskName = ""

    private var currentTask: Task<Void, Never>?

    private init() {}

    /// Add a task to the queue and start execution if not already running.
    func enqueue(name: String, action: @escaping () async throws -> Void) {
        let task = HakchiTask(name: name, action: action)
        tasks.append(task)
        if !isRunning {
            runNext()
        }
    }

    /// Cancel all pending tasks.
    func cancelAll() {
        currentTask?.cancel()
        tasks.removeAll { $0.status == .pending }
        isRunning = false
        currentTaskName = ""
    }

    /// Remove completed/failed tasks from the list.
    func clearFinished() {
        tasks.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    private func runNext() {
        guard let index = tasks.firstIndex(where: { $0.status == .pending }) else {
            isRunning = false
            currentTaskName = ""
            return
        }

        isRunning = true
        tasks[index].status = .running
        currentTaskName = tasks[index].name
        let taskID = tasks[index].id

        currentTask = Task {
            do {
                try await tasks.first(where: { $0.id == taskID })?.action()
                if let idx = tasks.firstIndex(where: { $0.id == taskID }) {
                    tasks[idx].status = .completed
                    tasks[idx].progress = 1.0
                }
            } catch {
                if let idx = tasks.firstIndex(where: { $0.id == taskID }) {
                    tasks[idx].status = .failed
                    tasks[idx].message = error.localizedDescription
                }
            }

            runNext()
        }
    }
}

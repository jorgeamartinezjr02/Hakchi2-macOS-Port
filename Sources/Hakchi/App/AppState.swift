import SwiftUI
import Combine

enum KernelAction {
    case dump
    case flash
    case restore
    case factoryReset
}

@MainActor
final class AppState: ObservableObject {
    // Connection
    @Published var consoleState: ConsoleState = .disconnected
    @Published var consoleType: ConsoleType = .unknown
    @Published var consoleInfo: ConsoleInfo?

    // Games
    @Published var games: [Game] = []
    @Published var selectedGame: Game?
    @Published var selectedGameIDs: Set<UUID> = []

    // Mods
    @Published var installedMods: [Mod] = []
    @Published var availableMods: [Mod] = []

    // Dialogs
    @Published var showKernelDialog = false
    @Published var showModManager = false
    @Published var showFolderManager = false
    @Published var showProgress = false
    @Published var kernelAction: KernelAction = .dump

    // Progress
    @Published var progressTitle = ""
    @Published var progressValue: Double = 0
    @Published var progressMessage = ""

    // Storage
    @Published var usedStorage: Int64 = 0
    @Published var totalStorage: Int64 = 256 * 1024 * 1024 // 256MB NAND

    // Services
    let usbMonitor = USBDeviceMonitor()
    let gameManager = GameManager()
    let modInstaller = ModInstaller()

    var isConnected: Bool {
        consoleState == .connected || consoleState == .felMode
    }

    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?

    let settings = AppSettings.shared

    init() {
        consoleType = settings.defaultConsoleType
        setupUSBMonitoring()
        loadGames()
    }

    private func setupUSBMonitoring() {
        usbMonitor.$deviceState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.consoleState = state
            }
            .store(in: &cancellables)

        usbMonitor.$detectedConsoleType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] type in
                guard let self = self else { return }
                if self.settings.autoDetectConsole && type != .unknown {
                    self.consoleType = type
                }
            }
            .store(in: &cancellables)

        usbMonitor.startMonitoring()
    }

    private func loadGames() {
        games = gameManager.loadSavedGames()
    }

    func addGames(urls: [URL]) {
        for url in urls {
            let newGames = gameManager.addGames(from: url)
            games.append(contentsOf: newGames)
        }
        if !urls.isEmpty {
            gameManager.saveGames(games)
        }
    }

    func removeSelectedGames() {
        games.removeAll { selectedGameIDs.contains($0.id) }
        selectedGameIDs.removeAll()
        selectedGame = nil
        gameManager.saveGames(games)
    }

    func updateGame(_ updated: Game) {
        if let index = games.firstIndex(where: { $0.id == updated.id }) {
            games[index] = updated
            if selectedGame?.id == updated.id {
                selectedGame = updated
            }
            gameManager.saveGames(games)
        }
    }

    func syncGames() {
        // Cancel any in-flight sync before starting a new one
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            guard let self = self, self.isConnected else { return }
            self.showProgress = true
            self.progressTitle = "Syncing Games"
            self.progressValue = 0

            let selectedGames = self.games.filter { self.selectedGameIDs.contains($0.id) }
            let gamesToSync = selectedGames.isEmpty ? self.games : selectedGames

            do {
                let shell = try await self.createShell()
                defer { shell.disconnect() }
                try await self.gameManager.syncToConsole(
                    games: gamesToSync,
                    consoleType: self.consoleType,
                    shell: shell,
                    progress: { [weak self] value, message in
                        Task { @MainActor in
                            self?.progressValue = value
                            self?.progressMessage = message
                        }
                    }
                )
            } catch {
                if !Task.isCancelled {
                    self.progressMessage = "Error: \(error.localizedDescription)"
                }
            }

            self.showProgress = false
        }
    }

    func rebootConsole() async {
        guard isConnected else { return }
        do {
            let shell = try await createShell()
            defer { shell.disconnect() }
            _ = try await shell.executeCommand("reboot")
        } catch {
            progressMessage = "Reboot failed: \(error.localizedDescription)"
        }
    }

    /// Create a ShellInterface using the best available connection method.
    /// Verifies the connection is functional before returning.
    func createShell() async throws -> ShellInterface {
        // Try Clovershell first (USB direct), fall back to SSH
        if let clovershell = try? ClovershellShell() {
            // Verify it's actually a Clovershell device (not FEL mode)
            do {
                let test = try await clovershell.executeCommand("echo OK")
                if test.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                    return clovershell
                }
            } catch {
                // Connection failed — not a real Clovershell device
            }
            clovershell.disconnect()
        }
        let host = UserDefaults.standard.string(forKey: "sshHost") ?? "169.254.1.1"
        let port = UserDefaults.standard.integer(forKey: "sshPort")
        return try await SSHShell(host: host, port: port > 0 ? port : 22)
    }
}

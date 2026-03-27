import SwiftUI
import Combine

enum KernelAction {
    case dump
    case flash
    case restore
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

    init() {
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
                self?.consoleType = type
            }
            .store(in: &cancellables)

        usbMonitor.startMonitoring()
    }

    private func loadGames() {
        games = gameManager.loadSavedGames()
    }

    func addGames(urls: [URL]) {
        for url in urls {
            if let game = gameManager.addGame(from: url) {
                games.append(game)
            }
        }
    }

    func removeSelectedGames() {
        games.removeAll { selectedGameIDs.contains($0.id) }
        selectedGameIDs.removeAll()
        selectedGame = nil
        gameManager.saveGames(games)
    }

    func syncGames() async {
        guard isConnected else { return }
        showProgress = true
        progressTitle = "Syncing Games"
        progressValue = 0

        let selectedGames = games.filter { selectedGameIDs.contains($0.id) }
        let gamesToSync = selectedGames.isEmpty ? games : selectedGames

        do {
            try await gameManager.syncToConsole(
                games: gamesToSync,
                consoleType: consoleType,
                progress: { [weak self] value, message in
                    Task { @MainActor in
                        self?.progressValue = value
                        self?.progressMessage = message
                    }
                }
            )
        } catch {
            progressMessage = "Error: \(error.localizedDescription)"
        }

        showProgress = false
    }

    func rebootConsole() async {
        guard isConnected else { return }
        do {
            let shell = SSHClient()
            try await shell.connect(host: "169.254.1.1")
            try await shell.execute("reboot")
            shell.disconnect()
        } catch {
            progressMessage = "Reboot failed: \(error.localizedDescription)"
        }
    }
}

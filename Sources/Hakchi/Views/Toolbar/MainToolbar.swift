import SwiftUI

struct MainToolbar: ToolbarContent {
    @EnvironmentObject var appState: AppState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.syncGames() }
            } label: {
                Label("Sync Games", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!appState.isConnected)
            .help("Sync games to console")

            Button {
                appState.showKernelDialog = true
                appState.kernelAction = .dump
            } label: {
                Label("Kernel", systemImage: "cpu")
            }
            .disabled(!appState.isConnected)
            .help("Kernel operations")

            Button {
                appState.showModManager = true
            } label: {
                Label("Mods", systemImage: "puzzlepiece.extension")
            }
            .disabled(!appState.isConnected)
            .help("Manage mods")
        }

        ToolbarItem(placement: .status) {
            ConnectionStatusView(state: appState.consoleState)
        }
    }
}

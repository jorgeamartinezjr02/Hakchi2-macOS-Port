import SwiftUI

@main
struct HakchiApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Kernel") {
                Button("Install / Repair Hakchi...") {
                    appState.showKernelDialog = true
                    appState.kernelAction = .flash
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Backup Kernel...") {
                    appState.showKernelDialog = true
                    appState.kernelAction = .dump
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Uninstall (Restore Original)...") {
                    appState.showKernelDialog = true
                    appState.kernelAction = .restore
                }

                Divider()

                Button("Factory Reset...") {
                    appState.showKernelDialog = true
                    appState.kernelAction = .factoryReset
                }

                Divider()

                Button("Reboot Console") {
                    Task { await appState.rebootConsole() }
                }
                .disabled(!appState.isConnected)
            }

            CommandMenu("Mods") {
                Button("Mod Manager...") {
                    appState.showModManager = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!appState.isConnected)
            }

            CommandMenu("Console") {
                Button("Sync Games") {
                    Task { await appState.syncGames() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!appState.isConnected)

                Divider()

                Button("Folder Manager...") {
                    appState.showFolderManager = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }
}

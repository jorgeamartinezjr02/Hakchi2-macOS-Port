import SwiftUI

struct ConsoleSidebar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Console Status
            HStack {
                ConnectionStatusView(state: appState.consoleState)
                Spacer()
                Text(appState.consoleType.shortName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.2)))
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Console Type Picker
            Picker("Console", selection: Binding(
                get: { appState.consoleType },
                set: { appState.consoleType = $0 }
            )) {
                ForEach(ConsoleType.allCases, id: \.self) { type in
                    if type != .unknown {
                        Text(type.rawValue).tag(type)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Storage Bar
            if appState.isConnected {
                StorageBar(
                    used: appState.usedStorage,
                    total: appState.totalStorage
                )
                .padding(.horizontal)
            }

            // Quick Actions
            HStack(spacing: 8) {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [
                        .init(filenameExtension: "nes")!,
                        .init(filenameExtension: "sfc")!,
                        .init(filenameExtension: "smc")!,
                        .init(filenameExtension: "md")!,
                        .init(filenameExtension: "fds")!,
                        .init(filenameExtension: "fig")!,
                    ].compactMap { $0 }
                    panel.message = "Select ROM files to add"

                    if panel.runModal() == .OK {
                        appState.addGames(urls: panel.urls)
                    }
                } label: {
                    Label("Add Games", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await appState.syncGames() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isConnected)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }
}

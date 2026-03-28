import SwiftUI
import UniformTypeIdentifiers

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
            VStack(spacing: 4) {
                // System family picker
                Picker("Family", selection: Binding(
                    get: { appState.consoleType.systemFamily },
                    set: { family in
                        switch family {
                        case "NES": appState.consoleType = .nesUSA
                        case "SNES": appState.consoleType = .snesUSA
                        case "Sega": appState.consoleType = .genesisUSA
                        default: break
                        }
                    }
                )) {
                    Text("NES").tag("NES")
                    Text("SNES").tag("SNES")
                    Text("Sega").tag("Sega")
                }
                .pickerStyle(.segmented)

                // Regional variant picker
                Picker("Region", selection: Binding(
                    get: { appState.consoleType },
                    set: { appState.consoleType = $0 }
                )) {
                    ForEach(regionalVariants, id: \.self) { type in
                        Text(type.shortName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
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
                        "nes", "sfc", "smc", "md", "fds", "fig",
                        "unf", "unif", "swc", "smd", "gen", "bin",
                        "zip", "7z", "rar", "gz", "tgz", "clvg"
                    ].compactMap { UTType(filenameExtension: $0) }
                    panel.message = "Select ROM files or archives to add"

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

    private var regionalVariants: [ConsoleType] {
        let family = appState.consoleType.systemFamily
        switch family {
        case "NES": return [.nesUSA, .nesEU, .famicomMini]
        case "SNES": return [.snesUSA, .snesEU, .superFamicomMini]
        case "Sega": return [.genesisUSA, .megaDriveEU, .megaDriveJP]
        default: return [.nesUSA]
        }
    }
}

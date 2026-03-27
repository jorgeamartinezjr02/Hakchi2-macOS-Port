import SwiftUI

struct ModManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isInstalling = false
    @State private var installProgress: Double = 0
    @State private var installMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mod Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("Installed").tag(0)
                Text("Available").tag(1)
                Text("Local Files").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search mods...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.1)))
            .padding()

            Divider()

            // Content
            switch selectedTab {
            case 0:
                installedModsView
            case 1:
                availableModsView
            case 2:
                localModsView
            default:
                EmptyView()
            }

            // Install Progress
            if isInstalling {
                Divider()
                VStack(spacing: 4) {
                    ProgressView(value: installProgress)
                    Text(installMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }

    private var installedModsView: some View {
        Group {
            if appState.installedMods.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No mods installed")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredMods(appState.installedMods)) { mod in
                        ModRowView(mod: mod, showInstall: false) {
                            Task { await uninstallMod(mod) }
                        }
                    }
                }
            }
        }
    }

    private var availableModsView: some View {
        let entries = ModRepository.shared.getAvailableMods()
        return List {
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .fontWeight(.medium)
                        Text(entry.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text(entry.category)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.secondary.opacity(0.15)))
                            Text("v\(entry.version)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var localModsView: some View {
        VStack {
            let localMods = appState.modInstaller.scanLocalMods()
            if localMods.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No local .hmod files found")
                        .foregroundColor(.secondary)
                    Button("Open Mods Folder") {
                        NSWorkspace.shared.open(FileUtils.modsDirectory)
                    }
                    Text("Place .hmod files in the mods folder to install them")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(localMods) { mod in
                        ModRowView(mod: mod, showInstall: true) {
                            Task { await installMod(mod) }
                        }
                    }
                }
            }

            // Import button
            HStack {
                Spacer()
                Button("Import .hmod File...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "hmod")!].compactMap { $0 }
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        for url in panel.urls {
                            let dest = FileUtils.modsDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: dest)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func filteredMods(_ mods: [Mod]) -> [Mod] {
        guard !searchText.isEmpty else { return mods }
        return mods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func installMod(_ mod: Mod) async {
        isInstalling = true
        let ssh = SSHClient()
        do {
            try await ssh.connect()
            try await appState.modInstaller.installMod(mod, ssh: ssh) { value, msg in
                Task { @MainActor in
                    installProgress = value
                    installMessage = msg
                }
            }
            var installed = mod
            installed = Mod(
                id: installed.id, name: installed.name, version: installed.version,
                author: installed.author, description: installed.description,
                category: installed.category, filePath: installed.filePath,
                isInstalled: true, fileSize: installed.fileSize
            )
            appState.installedMods.append(installed)
        } catch {
            installMessage = "Error: \(error.localizedDescription)"
        }
        ssh.disconnect()
        isInstalling = false
    }

    private func uninstallMod(_ mod: Mod) async {
        isInstalling = true
        let ssh = SSHClient()
        do {
            try await ssh.connect()
            try await appState.modInstaller.uninstallMod(mod, ssh: ssh) { value, msg in
                Task { @MainActor in
                    installProgress = value
                    installMessage = msg
                }
            }
            appState.installedMods.removeAll { $0.id == mod.id }
        } catch {
            installMessage = "Error: \(error.localizedDescription)"
        }
        ssh.disconnect()
        isInstalling = false
    }
}

struct ModRowView: View {
    let mod: Mod
    let showInstall: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mod.name)
                    .fontWeight(.medium)
                if !mod.description.isEmpty {
                    Text(mod.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(mod.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.secondary.opacity(0.15)))
                    Text("v\(mod.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !mod.author.isEmpty {
                        Text("by \(mod.author)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(showInstall ? "Install" : "Uninstall") {
                action()
            }
            .buttonStyle(.bordered)
            .tint(showInstall ? .accentColor : .red)
        }
        .padding(.vertical, 4)
    }
}

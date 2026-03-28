import SwiftUI

struct FolderManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFolderID: UUID?
    @State private var newFolderName = ""
    @State private var maxGamesPerFolder = 30
    @State private var splitMode: FolderManager.SplitMode = .alphabetic

    private let folderManager = FolderManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Folder Manager")
                    .font(.headline)

                Spacer()

                // Auto-split controls
                Picker("Split", selection: $splitMode) {
                    ForEach(FolderManager.SplitMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 140)

                Stepper("Max \(maxGamesPerFolder)", value: $maxGamesPerFolder, in: 5...100, step: 5)
                    .frame(width: 140)

                Button("Auto-Split") {
                    folderManager.autoSplit(
                        games: &appState.games,
                        mode: splitMode,
                        maxPerFolder: maxGamesPerFolder
                    )
                    appState.gameManager.saveGames(appState.games)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Content
            HSplitView {
                // Folder tree (left)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Folders")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: addFolder) {
                            Image(systemName: "folder.badge.plus")
                        }
                        .buttonStyle(.borderless)

                        Button(action: deleteSelectedFolder) {
                            Image(systemName: "folder.badge.minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedFolderID == nil)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    List(selection: $selectedFolderID) {
                        // Root (all games)
                        Label("All Games", systemImage: "folder")
                            .tag(FolderNode.root.id)

                        ForEach(folderManager.childFolders(of: nil)) { folder in
                            Label(folder.name, systemImage: "folder.fill")
                                .tag(folder.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 180)

                // Games in selected folder (right)
                VStack(alignment: .leading) {
                    Text("Games in \(selectedFolderName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    List {
                        ForEach(gamesInSelectedFolder) { game in
                            HStack {
                                Text(game.name)
                                Spacer()
                                Text(game.consoleType.shortName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)

                    HStack {
                        Text("\(gamesInSelectedFolder.count) games")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(minWidth: 300)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Reset Folders") {
                    folderManager.folders.removeAll()
                    folderManager.saveFolders()
                    for i in appState.games.indices {
                        appState.games[i].folder = "/"
                    }
                    appState.gameManager.saveGames(appState.games)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
    }

    // MARK: - Computed

    private var selectedFolderName: String {
        if selectedFolderID == FolderNode.root.id || selectedFolderID == nil {
            return "All Games"
        }
        return folderManager.folders.first { $0.id == selectedFolderID }?.name ?? "Unknown"
    }

    private var gamesInSelectedFolder: [Game] {
        if selectedFolderID == FolderNode.root.id || selectedFolderID == nil {
            return appState.games.sorted { $0.sortName < $1.sortName }
        }
        let folderIDStr = selectedFolderID?.uuidString ?? ""
        return appState.games.filter { $0.folder == folderIDStr }.sorted { $0.sortName < $1.sortName }
    }

    // MARK: - Actions

    private func addFolder() {
        let name = "New Folder \(folderManager.folders.count + 1)"
        let folder = folderManager.createFolder(name: name)
        selectedFolderID = folder.id
    }

    private func deleteSelectedFolder() {
        guard let id = selectedFolderID, id != FolderNode.root.id else { return }
        // Move games back to root
        for i in appState.games.indices where appState.games[i].folder == id.uuidString {
            appState.games[i].folder = "/"
        }
        folderManager.deleteFolder(id)
        appState.gameManager.saveGames(appState.games)
        selectedFolderID = nil
    }
}

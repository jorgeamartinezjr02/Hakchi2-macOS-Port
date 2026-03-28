import SwiftUI

struct GameListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name
    @State private var filterSystem: String = "All"

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case system = "System"
        case size = "Size"
        case region = "Region"
        case core = "Core"
    }

    var availableSystems: [String] {
        let systems = Set(appState.games.compactMap { $0.system ?? $0.consoleType.systemFamily })
        return ["All"] + systems.sorted()
    }

    var filteredGames: [Game] {
        var games = appState.games

        if !searchText.isEmpty {
            games = games.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.publisher.localizedCaseInsensitiveContains(searchText) ||
                $0.romCRC32.localizedCaseInsensitiveContains(searchText)
            }
        }

        if filterSystem != "All" {
            games = games.filter {
                ($0.system ?? $0.consoleType.systemFamily) == filterSystem
            }
        }

        switch sortOrder {
        case .name:
            games.sort { $0.sortName.lowercased() < $1.sortName.lowercased() }
        case .system:
            games.sort { ($0.system ?? $0.consoleType.systemFamily) < ($1.system ?? $1.consoleType.systemFamily) }
        case .size:
            games.sort { $0.romSize > $1.romSize }
        case .region:
            games.sort { $0.region < $1.region }
        case .core:
            games.sort { ($0.assignedCore ?? "") < ($1.assignedCore ?? "") }
        }

        return games
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and Sort
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search games...", text: $searchText)
                    .textFieldStyle(.plain)

                // System filter
                Menu {
                    ForEach(availableSystems, id: \.self) { sys in
                        Button {
                            filterSystem = sys
                        } label: {
                            HStack {
                                Text(sys)
                                if filterSystem == sys {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Sort order
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Game List
            List(selection: $appState.selectedGameIDs) {
                ForEach(filteredGames) { game in
                    GameRowView(game: game)
                        .tag(game.id)
                        .onTapGesture {
                            appState.selectedGame = game
                        }
                }
                .onDelete { indices in
                    let gamesToDelete = indices.map { filteredGames[$0] }
                    for game in gamesToDelete {
                        appState.games.removeAll { $0.id == game.id }
                    }
                    appState.gameManager.saveGames(appState.games)
                }
            }
            .listStyle(.inset)

            Divider()

            // Footer
            HStack {
                Text("\(filteredGames.count) games")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                let totalSize = appState.gameManager.calculateTotalSize(games: appState.games)
                Text(formatSize(totalSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct GameRowView: View {
    let game: Game

    var body: some View {
        HStack(spacing: 10) {
            // Console type icon
            Image(systemName: consoleIcon)
                .foregroundColor(consoleColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !game.publisher.isEmpty {
                        Text(game.publisher)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatSize(game.romSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var consoleIcon: String {
        let ct = game.consoleType
        if ct.isNES { return "gamecontroller" }
        if ct.isSNES { return "gamecontroller.fill" }
        if ct.isSega { return "arcade.stick" }
        return "questionmark.circle"
    }

    private var consoleColor: Color {
        let ct = game.consoleType
        if ct.isNES { return .red }
        if ct.isSNES { return .purple }
        if ct.isSega { return .blue }
        return .gray
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

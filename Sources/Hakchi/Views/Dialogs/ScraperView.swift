import SwiftUI

struct ScraperView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let game: Game

    @State private var searchQuery = ""
    @State private var results: [ScraperResult] = []
    @State private var isSearching = false
    @State private var selectedResult: ScraperResult?
    @State private var errorMessage = ""
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                TextField("Search game name...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }

                Button("Search") { search() }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchQuery.isEmpty || isSearching)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // Results list
            List(results, selection: $selectedResult) { result in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.name)
                            .font(.headline)
                        HStack {
                            if !result.platform.isEmpty {
                                Text(result.platform)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.blue.opacity(0.15)))
                            }
                            if !result.releaseDate.isEmpty {
                                Text(result.releaseDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if result.boxArtFrontURL != nil {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedResult = result
                }
                .listRowBackground(selectedResult?.id == result.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .listStyle(.inset)

            Divider()

            // Selected result preview
            if let selected = selectedResult {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.name).font(.headline)
                        if !selected.publisher.isEmpty {
                            Text("Publisher: \(selected.publisher)").font(.caption)
                        }
                        if !selected.releaseDate.isEmpty {
                            Text("Release: \(selected.releaseDate)").font(.caption)
                        }
                        Text("Players: \(selected.players)").font(.caption)
                        if selected.boxArtFrontURL != nil {
                            Label("Cover art available", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }

                Spacer()

                Button("Apply Metadata") {
                    applyResult()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedResult == nil || isApplying)

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
        }
        .frame(width: 550, height: 500)
        .onAppear {
            searchQuery = game.name
            search()
        }
    }

    private func search() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        errorMessage = ""
        results = []

        Task {
            do {
                let system = game.system ?? game.consoleType.systemFamily
                let searchResults = try await TheGamesDBClient.shared.searchGames(
                    name: searchQuery,
                    platform: system
                )
                await MainActor.run {
                    results = searchResults
                    isSearching = false
                    if results.isEmpty {
                        errorMessage = "No results found"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func applyResult() {
        guard let result = selectedResult else { return }
        isApplying = true

        Task {
            var updated = game
            updated.name = result.name
            updated.sortName = result.name
            updated.publisher = result.publisher
            updated.releaseDate = String(result.releaseDate.prefix(4))
            updated.players = result.players
            if !result.genres.isEmpty {
                updated.genre = result.genres.first ?? ""
            }

            // Download box art if available
            if let artURL = result.boxArtFrontURL {
                do {
                    let data = try await TheGamesDBClient.shared.downloadBoxArt(url: artURL)
                    let path = try BoxArtManager.shared.saveCoverArt(data: data, for: game)
                    updated.coverArtPath = path
                } catch {
                    HakchiLogger.games.error("Failed to download box art: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                appState.updateGame(updated)
                isApplying = false
                dismiss()
            }
        }
    }
}

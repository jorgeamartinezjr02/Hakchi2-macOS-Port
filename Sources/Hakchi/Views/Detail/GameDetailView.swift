import SwiftUI

struct GameDetailView: View {
    let game: Game
    @State private var editedName: String = ""
    @State private var editedPublisher: String = ""
    @State private var editedPlayers: Int = 1
    @State private var editedReleaseDate: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack(alignment: .top, spacing: 20) {
                    // Cover art placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.1))
                            .frame(width: 160, height: 220)

                        if let coverPath = game.coverArtPath,
                           let image = NSImage(contentsOfFile: coverPath) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 160, height: 220)
                                .cornerRadius(8)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No Cover Art")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .shadow(radius: 4)

                    // Game Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text(game.name)
                            .font(.title)
                            .fontWeight(.bold)

                        if !game.publisher.isEmpty {
                            Label(game.publisher, systemImage: "building.2")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if !game.releaseDate.isEmpty {
                            Label(game.releaseDate, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Label("\(game.players) Player\(game.players > 1 ? "s" : "")",
                              systemImage: "person.\(min(game.players, 3))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                            Text(game.consoleType.rawValue)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.secondary.opacity(0.15)))
                    }

                    Spacer()
                }
                .padding()

                Divider()

                // ROM Details
                GroupBox("ROM Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "File", value: URL(fileURLWithPath: game.romPath).lastPathComponent)
                        DetailRow(label: "Size", value: formatSize(game.romSize))
                        DetailRow(label: "CRC32", value: game.romCRC32)
                        DetailRow(label: "Path", value: game.romPath)
                    }
                    .padding(8)
                }
                .padding(.horizontal)

                // Edit Section
                GroupBox("Edit Game Info") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Name:")
                                .frame(width: 80, alignment: .trailing)
                            TextField("Game name", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Publisher:")
                                .frame(width: 80, alignment: .trailing)
                            TextField("Publisher", text: $editedPublisher)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Year:")
                                .frame(width: 80, alignment: .trailing)
                            TextField("Release year", text: $editedReleaseDate)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Players:")
                                .frame(width: 80, alignment: .trailing)
                            Stepper("\(editedPlayers)", value: $editedPlayers, in: 1...4)
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .onAppear {
            editedName = game.name
            editedPublisher = game.publisher
            editedPlayers = game.players
            editedReleaseDate = game.releaseDate
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

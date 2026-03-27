import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Hakchi for macOS")
                .font(.title)
                .fontWeight(.bold)

            Text("NES/SNES Classic Mini Manager")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            if appState.games.isEmpty {
                VStack(spacing: 12) {
                    Text("Get Started")
                        .font(.headline)

                    DragDropArea()
                        .frame(width: 400, height: 150)

                    Text("Or use File > Add Games to browse for ROMs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Select a game from the sidebar to view details")
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Connection hint
            if !appState.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Connect your NES/SNES Classic via USB to get started")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.1)))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

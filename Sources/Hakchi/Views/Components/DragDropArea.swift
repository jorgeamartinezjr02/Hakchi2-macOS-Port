import SwiftUI

struct DragDropArea: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : .clear)
                )

            VStack(spacing: 12) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text("Drop ROM files here")
                    .font(.headline)
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text(".nes, .sfc, .smc, .md, .fds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }

                if ROMFile.isSupportedExtension(url.pathExtension) {
                    DispatchQueue.main.async {
                        appState.addGames(urls: [url])
                    }
                }
            }
        }
        return true
    }
}

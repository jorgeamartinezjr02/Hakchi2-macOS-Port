import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ConsoleSidebar()
                Divider()
                GameListView()
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            if let game = appState.selectedGame {
                GameDetailView(game: game)
            } else {
                EmptyStateView()
            }
        }
        .toolbar {
            MainToolbar()
        }
        .sheet(isPresented: $appState.showKernelDialog) {
            KernelDialog(action: appState.kernelAction)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showModManager) {
            ModManagerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showFolderManager) {
            FolderManagerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showProgress) {
            ProgressDialog(
                title: appState.progressTitle,
                progress: appState.progressValue,
                message: appState.progressMessage
            )
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }

                if ROMFile.isSupportedExtension(url.pathExtension) || ArchiveExtractor.isArchive(url) {
                    DispatchQueue.main.async {
                        appState.addGames(urls: [url])
                    }
                }
            }
        }
        return true
    }
}

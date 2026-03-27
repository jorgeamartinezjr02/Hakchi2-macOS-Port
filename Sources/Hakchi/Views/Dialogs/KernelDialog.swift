import SwiftUI

struct KernelDialog: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let action: KernelAction
    @State private var isRunning = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var isComplete = false
    @State private var selectedBackup: URL?

    var body: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: actionIcon)
                    .font(.title2)
                Text(actionTitle)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(actionDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            if action == .restore {
                // Backup selection
                let backups = KernelManager(felDevice: FELDevice()).listBackups()
                if backups.isEmpty {
                    Text("No kernel backups found")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Select backup:", selection: $selectedBackup) {
                        Text("Choose...").tag(nil as URL?)
                        ForEach(backups, id: \.self) { url in
                            Text(url.lastPathComponent).tag(url as URL?)
                        }
                    }
                }
            }

            // Progress
            if isRunning {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            if isComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Operation completed successfully!")
                }
            }

            // Warning
            if action == .flash {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Flashing a custom kernel is irreversible without a backup. Make sure to dump your kernel first!")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.1)))
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if action == .flash {
                    Button("Choose Kernel File...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "img")!].compactMap { $0 }
                        panel.message = "Select kernel image to flash"
                        if panel.runModal() == .OK, let url = panel.url {
                            Task { await performFlash(url) }
                        }
                    }
                    .disabled(isRunning)
                } else if action == .restore {
                    Button("Restore") {
                        guard let backup = selectedBackup else { return }
                        Task { await performRestore(backup) }
                    }
                    .disabled(isRunning || selectedBackup == nil)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Dump Kernel") {
                        Task { await performDump() }
                    }
                    .disabled(isRunning)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var actionTitle: String {
        switch action {
        case .dump: return "Dump Kernel"
        case .flash: return "Flash Custom Kernel"
        case .restore: return "Restore Original Kernel"
        }
    }

    private var actionIcon: String {
        switch action {
        case .dump: return "arrow.down.circle"
        case .flash: return "arrow.up.circle"
        case .restore: return "arrow.counterclockwise.circle"
        }
    }

    private var actionDescription: String {
        switch action {
        case .dump: return "Save the console's current kernel to a file for backup."
        case .flash: return "Flash a custom kernel to enable hakchi on your console."
        case .restore: return "Restore a previously backed up original kernel."
        }
    }

    private func performDump() async {
        isRunning = true
        errorMessage = nil

        let kernelMgr = KernelManager()
        do {
            let backupURL = try await kernelMgr.backupKernel { value, msg in
                Task { @MainActor in
                    progress = value
                    statusMessage = msg
                }
            }
            isComplete = true
            statusMessage = "Saved to: \(backupURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func performFlash(_ url: URL) async {
        isRunning = true
        errorMessage = nil

        let kernelMgr = KernelManager()
        do {
            try await kernelMgr.flashKernelFromFile(path: url) { value, msg in
                Task { @MainActor in
                    progress = value
                    statusMessage = msg
                }
            }
            isComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func performRestore(_ backupURL: URL) async {
        isRunning = true
        errorMessage = nil

        let kernelMgr = KernelManager()
        do {
            try await kernelMgr.restoreKernel(from: backupURL) { value, msg in
                Task { @MainActor in
                    progress = value
                    statusMessage = msg
                }
            }
            isComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}

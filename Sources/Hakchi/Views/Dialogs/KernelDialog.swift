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
    @State private var backups: [URL] = []
    @State private var steps: [InstallStep] = []
    @State private var confirmFactoryReset = false

    struct InstallStep: Identifiable {
        let id = UUID()
        let name: String
        var status: StepStatus = .pending

        enum StepStatus {
            case pending, running, completed, failed
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: actionIcon)
                    .font(.title2)
                    .foregroundColor(actionColor)
                Text(actionTitle)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(actionDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()

            if action == .restore {
                restoreSection
            } else if action == .flash {
                installSection
            } else if action == .factoryReset {
                factoryResetSection
            } else {
                dumpSection
            }

            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.05)))
            }

            if isComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Operation completed successfully!")
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                actionButton
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            if action == .restore {
                let mgr = KernelManager()
                backups = await mgr.listBackups()
            }
        }
    }

    // MARK: - Install/Repair Section (automatic flow)

    @ViewBuilder
    private var installSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    switch step.status {
                    case .pending:
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    case .running:
                        ProgressView()
                            .controlSize(.small)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }

                    Text(step.name)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(step.status == .pending ? .secondary : .primary)
                }
            }

            if isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.top, 4)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Dump Section

    @ViewBuilder
    private var dumpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isRunning && !isComplete {
                // Show step list for dump too (it requires memboot + SSH)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        switch step.status {
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        case .running:
                            ProgressView()
                                .controlSize(.small)
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(step.name)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(step.status == .pending ? .secondary : .primary)
                    }
                }

                Text("This will boot a temporary kernel to read the stock kernel from NAND.\nYour console will NOT be modified. Hold Reset while plugging USB.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isRunning {
                // Show step list during execution
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        switch step.status {
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        case .running:
                            ProgressView()
                                .controlSize(.small)
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(step.name)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(step.status == .pending ? .secondary : .primary)
                    }
                }

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.top, 4)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Factory Reset Section

    @ViewBuilder
    private var factoryResetSection: some View {
        VStack(spacing: 12) {
            if !isRunning && !isComplete {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This will completely remove hakchi and ALL custom data:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        VStack(alignment: .leading, spacing: 2) {
                            Label("All custom games will be deleted", systemImage: "trash")
                            Label("All mods will be uninstalled", systemImage: "puzzlepiece.extension")
                            Label("All save states will be lost", systemImage: "memorychip")
                            Label("Stock kernel will be restored", systemImage: "arrow.counterclockwise")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.05)))

                if !confirmFactoryReset {
                    Toggle("I understand this cannot be undone", isOn: $confirmFactoryReset)
                        .toggleStyle(.checkbox)
                }
            }

            if isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Restore Section

    @ViewBuilder
    private var restoreSection: some View {
        VStack(spacing: 12) {
            if backups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                    Text("No kernel backups found")
                        .foregroundColor(.secondary)
                    Text("Connect your console in FEL mode and dump the kernel first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Select backup:", selection: $selectedBackup) {
                    Text("Choose a backup...").tag(nil as URL?)
                    ForEach(backups, id: \.self) { url in
                        Text(url.lastPathComponent).tag(url as URL?)
                    }
                }
            }

            if isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch action {
        case .flash:
            Button(isRunning ? "Installing..." : "Install / Repair") {
                Task { await performInstall() }
            }
            .disabled(isRunning || isComplete)
            .buttonStyle(.borderedProminent)

        case .restore:
            Button("Restore Original") {
                guard let backup = selectedBackup else { return }
                Task { await performRestore(backup) }
            }
            .disabled(isRunning || selectedBackup == nil || isComplete)
            .buttonStyle(.borderedProminent)

        case .dump:
            Button("Dump Kernel") {
                Task { await performDump() }
            }
            .disabled(isRunning || isComplete)
            .buttonStyle(.borderedProminent)

        case .factoryReset:
            Button("Factory Reset") {
                Task { await performFactoryReset() }
            }
            .disabled(isRunning || isComplete || !confirmFactoryReset)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    // MARK: - Computed

    private var actionTitle: String {
        switch action {
        case .dump: return "Backup Kernel"
        case .flash: return "Install / Repair Hakchi"
        case .restore: return "Uninstall (Restore Original)"
        case .factoryReset: return "Factory Reset"
        }
    }

    private var actionIcon: String {
        switch action {
        case .dump: return "arrow.down.circle"
        case .flash: return "bolt.circle.fill"
        case .restore: return "arrow.counterclockwise.circle"
        case .factoryReset: return "trash.circle.fill"
        }
    }

    private var actionColor: Color {
        switch action {
        case .dump: return .blue
        case .flash: return .green
        case .restore: return .orange
        case .factoryReset: return .red
        }
    }

    private var actionDescription: String {
        switch action {
        case .dump: return "Save your console's stock kernel as a backup.\nConnect your console in FEL mode (hold Reset while plugging USB)."
        case .flash: return "Automatically install hakchi on your console.\nConnect your console in FEL mode (hold Reset while plugging USB)."
        case .restore: return "Remove hakchi and restore the original stock kernel."
        case .factoryReset: return "Completely remove hakchi, all games, mods, saves, and restore factory state."
        }
    }

    // MARK: - Automated Install Flow
    //
    // Corrected flow (2026-03):
    //   1. Download/verify resources (boot.img + uboot.bin)
    //   2. Wait for FEL device
    //   3. Init DRAM + Memboot custom kernel
    //   4. Wait for shell (SSH) connection
    //   5. Backup stock kernel via SSH + MTD
    //   6. Install hakchi system files via SSH

    private func performInstall() async {
        isRunning = true
        errorMessage = nil
        HakchiLogger.clearLog()
        HakchiLogger.fileLog("install", "=== Install/Repair started ===")
        steps = [
            InstallStep(name: "Download hakchi resources"),
            InstallStep(name: "Wait for console in FEL mode"),
            InstallStep(name: "Memboot custom kernel (DRAM init + boot)"),
            InstallStep(name: "Wait for shell connection"),
            InstallStep(name: "Backup stock kernel (from NAND)"),
            InstallStep(name: "Install hakchi system files"),
        ]

        do {
            // Step 1: Ensure resources are downloaded
            updateStep(0, status: .running)
            try await HakchiResources.shared.ensureResources { value, msg in
                Task { @MainActor in
                    progress = value * 0.10
                    statusMessage = msg
                }
            }
            updateStep(0, status: .completed)

            // Step 2: Wait for FEL device
            updateStep(1, status: .running)
            statusMessage = "Waiting for FEL device... Hold Reset while plugging USB."
            let device = FELDevice()
            var attempts = 0
            while attempts < 60 {
                do {
                    try device.open()
                    break
                } catch {
                    attempts += 1
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            guard device.isDeviceOpen else {
                throw HakchiError.deviceNotFound
            }
            let version = try device.getVersion()
            let consoleType = ConsoleType.from(felVersion: version)
            statusMessage = "Found: \(consoleType.rawValue) (SoC: 0x\(String(format: "%04X", version.socID)))"
            updateStep(1, status: .completed)

            // Step 3: Memboot (DRAM init + load kernel to RAM + execute)
            updateStep(2, status: .running)
            let membootMgr = MembootManager()
            try await membootMgr.membootWithClovershell(
                device: device,
                progress: { value, msg in
                    Task { @MainActor in
                        progress = 0.10 + value * 0.25
                        statusMessage = msg
                    }
                }
            )
            device.close() // USB device identity changes after kernel boots
            updateStep(2, status: .completed)

            // Step 4: Wait for shell connection (Clovershell USB, then SSH fallback)
            updateStep(3, status: .running)
            statusMessage = "Waiting for console to boot..."
            HakchiLogger.fileLog("shell", "Waiting 15s for kernel boot + clovershell daemon...")
            try await Task.sleep(nanoseconds: 15_000_000_000) // 15s for kernel boot + clovershell

            var shell: ShellInterface?

            // Try Clovershell first (USB direct — preferred for memboot with hakchi-clovershell)
            statusMessage = "Connecting via Clovershell USB..."
            HakchiLogger.fileLog("shell", "Attempting Clovershell connection...")
            for attempt in 0..<15 {
                do {
                    let cloverShell = try ClovershellShell()
                    // Quick test
                    let test = try await cloverShell.executeCommand("echo OK")
                    if test.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                        shell = cloverShell
                        HakchiLogger.fileLog("shell", "Clovershell connected on attempt \(attempt + 1)")
                        break
                    }
                    cloverShell.disconnect()
                } catch {
                    HakchiLogger.fileLog("shell", "Clovershell attempt \(attempt + 1)/15 failed: \(error)")
                    if attempt == 7 {
                        statusMessage = "Still waiting for Clovershell..."
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            // Fallback to SSH if Clovershell didn't work
            if shell == nil {
                statusMessage = "Trying SSH fallback..."
                HakchiLogger.fileLog("shell", "Clovershell failed, trying SSH fallback...")
                for attempt in 0..<15 {
                    do {
                        let sshShell = try await SSHShell(
                            host: AppSettings.shared.sshHost,
                            port: AppSettings.shared.sshPort
                        )
                        shell = sshShell
                        HakchiLogger.fileLog("shell", "SSH connected on attempt \(attempt + 1)")
                        break
                    } catch {
                        HakchiLogger.fileLog("shell", "SSH attempt \(attempt + 1)/15 failed: \(error)")
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }

            guard let connectedShell = shell else {
                HakchiLogger.fileLog("shell", "FAILED: No shell connection after all attempts")
                throw HakchiError.sshConnectionFailed(
                    "Console did not come online after memboot. "
                    + "Check USB cable and that DRAM was initialised correctly."
                )
            }
            statusMessage = "Shell connected"
            HakchiLogger.fileLog("shell", "Shell connected successfully")
            updateStep(3, status: .completed)

            // Step 5: Backup stock kernel from NAND via SSH
            updateStep(4, status: .running)
            let kernelMgr = KernelManager()
            let backupURL = try await kernelMgr.backupKernel(shell: connectedShell) { value, msg in
                Task { @MainActor in
                    progress = 0.35 + value * 0.20
                    statusMessage = msg
                }
            }
            statusMessage = "Backed up to \(backupURL.lastPathComponent)"
            updateStep(4, status: .completed)

            // Step 6: Install hakchi system files
            updateStep(5, status: .running)
            statusMessage = "Installing hakchi..."

            // Create hakchi config
            _ = try await connectedShell.executeCommand("mkdir -p /hakchi/config")
            _ = try await connectedShell.executeCommand("echo 'cf_install=y' > /hakchi/config/config")
            _ = try await connectedShell.executeCommand("echo 'cf_update=y' >> /hakchi/config/config")

            // Transfer and install base hmods
            _ = try await connectedShell.executeCommand("mkdir -p /hakchi/transfer")

            let localMods = FileUtils.modsDirectory
            if FileManager.default.fileExists(atPath: localMods.path) {
                let files = (try? FileManager.default.contentsOfDirectory(at: localMods, includingPropertiesForKeys: nil)) ?? []
                for file in files where file.pathExtension == "hmod" {
                    statusMessage = "Uploading \(file.lastPathComponent)..."
                    try await connectedShell.uploadFile(
                        localPath: file.path,
                        remotePath: "/hakchi/transfer/\(file.lastPathComponent)",
                        progress: nil
                    )
                }
            }

            // Execute boot/install
            statusMessage = "Running hakchi installer..."
            _ = try await connectedShell.executeCommand("hakchi packs_install /hakchi/transfer/ 2>/dev/null || true")
            _ = try await connectedShell.executeCommand("rm -rf /hakchi/transfer")

            // Sync and reboot
            _ = try await connectedShell.executeCommand("sync")
            progress = 0.95
            statusMessage = "Installation complete! Rebooting..."
            _ = try? await connectedShell.executeCommand("reboot")
            connectedShell.disconnect()

            updateStep(5, status: .completed)
            progress = 1.0
            isComplete = true
            statusMessage = "Hakchi installed successfully!"

            await MainActor.run {
                appState.consoleState = .disconnected
            }

        } catch {
            errorMessage = error.localizedDescription
            if let idx = steps.firstIndex(where: { $0.status == .running }) {
                steps[idx].status = .failed
            }
        }

        isRunning = false
    }

    // MARK: - Dump kernel
    //
    // Corrected: Dump now requires memboot + SSH because NAND isn't
    // accessible via FEL memory read.  The console is NOT modified.

    private func performDump() async {
        isRunning = true
        errorMessage = nil
        steps = [
            InstallStep(name: "Prepare resources"),
            InstallStep(name: "Wait for console in FEL mode"),
            InstallStep(name: "Memboot temporary kernel"),
            InstallStep(name: "Wait for shell connection"),
            InstallStep(name: "Dump kernel from NAND"),
        ]

        do {
            // Step 1: Resources
            updateStep(0, status: .running)
            try await HakchiResources.shared.ensureResources { value, msg in
                Task { @MainActor in
                    progress = value * 0.05
                    statusMessage = msg
                }
            }
            updateStep(0, status: .completed)

            // Step 2: Wait for FEL
            updateStep(1, status: .running)
            statusMessage = "Waiting for FEL device... Hold Reset while plugging USB."
            let device = FELDevice()
            var attempts = 0
            while attempts < 60 {
                do {
                    try device.open()
                    break
                } catch {
                    attempts += 1
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            guard device.isDeviceOpen else {
                throw HakchiError.deviceNotFound
            }
            let version = try device.getVersion()
            statusMessage = "Found console (SoC: 0x\(String(format: "%04X", version.socID)))"
            updateStep(1, status: .completed)

            // Step 3: Memboot
            updateStep(2, status: .running)
            let membootMgr = MembootManager()
            try await membootMgr.membootWithClovershell(
                device: device,
                progress: { value, msg in
                    Task { @MainActor in
                        progress = 0.05 + value * 0.25
                        statusMessage = msg
                    }
                }
            )
            device.close()
            updateStep(2, status: .completed)

            // Step 4: Wait for shell (Clovershell USB, then SSH fallback)
            updateStep(3, status: .running)
            statusMessage = "Waiting for console to boot..."
            try await Task.sleep(nanoseconds: 15_000_000_000)

            var shell: ShellInterface?
            statusMessage = "Connecting via Clovershell USB..."
            for attempt in 0..<15 {
                do {
                    let cloverShell = try ClovershellShell()
                    let test = try await cloverShell.executeCommand("echo OK")
                    if test.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                        shell = cloverShell
                        break
                    }
                    cloverShell.disconnect()
                } catch {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            if shell == nil {
                statusMessage = "Trying SSH fallback..."
                for _ in 0..<15 {
                    do {
                        shell = try await SSHShell(
                            host: AppSettings.shared.sshHost,
                            port: AppSettings.shared.sshPort
                        )
                        break
                    } catch {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }
            guard let connectedShell = shell else {
                throw HakchiError.sshConnectionFailed(
                    "Console did not come online after memboot"
                )
            }
            updateStep(3, status: .completed)

            // Step 5: Dump kernel from NAND
            updateStep(4, status: .running)
            let kernelMgr = KernelManager()
            let backupURL = try await kernelMgr.backupKernel(shell: connectedShell) { value, msg in
                Task { @MainActor in
                    progress = 0.30 + value * 0.65
                    statusMessage = msg
                }
            }

            // Reboot back to stock (no changes were made)
            _ = try? await connectedShell.executeCommand("reboot")
            connectedShell.disconnect()

            updateStep(4, status: .completed)
            isComplete = true
            progress = 1.0
            statusMessage = "Saved to: \(backupURL.lastPathComponent)"

        } catch {
            errorMessage = error.localizedDescription
            if let idx = steps.firstIndex(where: { $0.status == .running }) {
                steps[idx].status = .failed
            }
        }

        isRunning = false
    }

    // MARK: - Restore kernel
    //
    // Restore also needs memboot + SSH to write to NAND.

    private func performRestore(_ backupURL: URL) async {
        isRunning = true
        errorMessage = nil
        steps = [
            InstallStep(name: "Prepare resources"),
            InstallStep(name: "Wait for console in FEL mode"),
            InstallStep(name: "Memboot temporary kernel"),
            InstallStep(name: "Wait for shell connection"),
            InstallStep(name: "Flash stock kernel to NAND"),
        ]

        do {
            // Step 1: Resources
            updateStep(0, status: .running)
            try await HakchiResources.shared.ensureResources { _, _ in }
            updateStep(0, status: .completed)

            // Step 2: Wait for FEL
            updateStep(1, status: .running)
            statusMessage = "Waiting for FEL device..."
            let device = FELDevice()
            var attempts = 0
            while attempts < 60 {
                do { try device.open(); break }
                catch { attempts += 1; try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
            guard device.isDeviceOpen else { throw HakchiError.deviceNotFound }
            _ = try device.getVersion()
            updateStep(1, status: .completed)

            // Step 3: Memboot
            updateStep(2, status: .running)
            let membootMgr = MembootManager()
            try await membootMgr.membootWithClovershell(
                device: device,
                progress: { value, msg in
                    Task { @MainActor in progress = 0.10 + value * 0.20; statusMessage = msg }
                }
            )
            device.close()
            updateStep(2, status: .completed)

            // Step 4: Wait for shell (Clovershell USB, then SSH fallback)
            updateStep(3, status: .running)
            statusMessage = "Waiting for console to boot..."
            try await Task.sleep(nanoseconds: 15_000_000_000)
            var shell: ShellInterface?
            statusMessage = "Connecting via Clovershell USB..."
            for attempt in 0..<15 {
                do {
                    let cloverShell = try ClovershellShell()
                    let test = try await cloverShell.executeCommand("echo OK")
                    if test.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                        shell = cloverShell; break
                    }
                    cloverShell.disconnect()
                } catch { try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
            if shell == nil {
                statusMessage = "Trying SSH fallback..."
                for _ in 0..<15 {
                    do { shell = try await SSHShell(host: AppSettings.shared.sshHost, port: AppSettings.shared.sshPort); break }
                    catch { try await Task.sleep(nanoseconds: 2_000_000_000) }
                }
            }
            guard let connectedShell = shell else {
                throw HakchiError.sshConnectionFailed("Console did not come online")
            }
            updateStep(3, status: .completed)

            // Step 5: Flash kernel
            updateStep(4, status: .running)
            let kernelMgr = KernelManager()
            try await kernelMgr.restoreKernel(from: backupURL, shell: connectedShell) { value, msg in
                Task { @MainActor in progress = 0.30 + value * 0.65; statusMessage = msg }
            }

            _ = try? await connectedShell.executeCommand("reboot")
            connectedShell.disconnect()

            updateStep(4, status: .completed)
            isComplete = true
            progress = 1.0
            statusMessage = "Stock kernel restored. Console rebooting."

        } catch {
            errorMessage = error.localizedDescription
            if let idx = steps.firstIndex(where: { $0.status == .running }) { steps[idx].status = .failed }
        }

        isRunning = false
    }

    // MARK: - Factory Reset

    private func performFactoryReset() async {
        isRunning = true
        errorMessage = nil

        do {
            statusMessage = "Connecting to console..."
            let shell = try await appState.createShell()
            defer { shell.disconnect() }

            let kernelMgr = KernelManager()
            let backupList = await kernelMgr.listBackups()

            try await kernelMgr.factoryReset(
                shell: shell,
                stockKernelPath: backupList.first,
                progress: { value, msg in
                    Task { @MainActor in
                        progress = value
                        statusMessage = msg
                    }
                }
            )

            isComplete = true
            statusMessage = "Factory reset complete. Console will reboot to stock firmware."

            await MainActor.run {
                appState.consoleState = .disconnected
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    // MARK: - Helpers

    private func updateStep(_ index: Int, status: InstallStep.StepStatus) {
        guard index < steps.count else { return }
        Task { @MainActor in
            steps[index].status = status
        }
    }
}

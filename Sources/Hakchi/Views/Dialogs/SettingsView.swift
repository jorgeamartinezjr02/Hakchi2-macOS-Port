import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("defaultConsoleType") private var defaultConsoleType = "SNES Classic"
    @AppStorage("autoDetectConsole") private var autoDetectConsole = true
    @AppStorage("backupKernelBeforeFlash") private var backupKernelBeforeFlash = true
    @AppStorage("showAdvancedOptions") private var showAdvancedOptions = false
    @AppStorage("sshHost") private var sshHost = "169.254.1.1"
    @AppStorage("sshPort") private var sshPort = 22

    var body: some View {
        TabView {
            // General Settings
            Form {
                Section("Console") {
                    Picker("Default Console Type", selection: $defaultConsoleType) {
                        Text("NES Classic").tag("NES Classic")
                        Text("SNES Classic").tag("SNES Classic")
                        Text("Sega Mini").tag("Sega Mini")
                    }

                    Toggle("Auto-detect connected console", isOn: $autoDetectConsole)
                }

                Section("Safety") {
                    Toggle("Backup kernel before flashing", isOn: $backupKernelBeforeFlash)
                }

                Section("Interface") {
                    Toggle("Show advanced options", isOn: $showAdvancedOptions)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            // Connection Settings
            Form {
                Section("SSH Connection") {
                    TextField("Host", text: $sshHost)
                    TextField("Port", value: $sshPort, format: .number)
                }

                Section("USB") {
                    LabeledContent("USB polling interval") {
                        Text("2 seconds")
                    }

                    LabeledContent("libusb") {
                        if isLibUSBAvailable() {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            VStack(alignment: .leading) {
                                Label("Not found", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Install with: brew install libusb")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Data") {
                    LabeledContent("Games directory") {
                        HStack {
                            Text(FileUtils.gamesDirectory.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open") {
                                NSWorkspace.shared.open(FileUtils.gamesDirectory)
                            }
                        }
                    }

                    LabeledContent("Mods directory") {
                        HStack {
                            Text(FileUtils.modsDirectory.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open") {
                                NSWorkspace.shared.open(FileUtils.modsDirectory)
                            }
                        }
                    }

                    LabeledContent("Kernel backups") {
                        HStack {
                            Text(FileUtils.kernelBackupDirectory.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open") {
                                NSWorkspace.shared.open(FileUtils.kernelBackupDirectory)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Connection", systemImage: "network")
            }
        }
        .frame(width: 500, height: 400)
    }

    private func isLibUSBAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["brew"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

import Foundation

final class ModInstaller {
    private let modsBasePath = "/var/lib/hakchi/transfer"
    private let installedModsPath = "/var/lib/hakchi/rootfs/etc/mods"

    /// Shell-escape a string for safe single-quoted interpolation.
    private func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func installMod(_ mod: Mod, ssh: SSHClient, progress: ((Double, String) -> Void)? = nil) async throws {
        HakchiLogger.mods.info("Installing mod: \(mod.name)")

        let safeName = shellEscape(mod.name)
        let sftp = SFTPClient(sshClient: ssh)

        progress?(0.1, "Preparing \(mod.name)...")

        // Ensure transfer directory exists
        try await ssh.execute("mkdir -p '\(shellEscape(modsBasePath))'")

        // Upload hmod file
        let remoteHmodPath = "\(modsBasePath)/\(safeName).hmod"
        progress?(0.2, "Uploading \(mod.name)...")

        try await sftp.upload(
            localPath: mod.filePath,
            remotePath: remoteHmodPath,
            progress: { value in
                progress?(0.2 + value * 0.5, "Uploading \(mod.name)... \(Int(value * 100))%")
            }
        )

        // Extract and run install script on console
        progress?(0.7, "Installing \(mod.name) on console...")

        let installCmd = """
        cd '\(shellEscape(modsBasePath))' && \
        mkdir -p '\(safeName)' && \
        tar xzf '\(safeName).hmod' -C '\(safeName)' 2>/dev/null; \
        cd '\(safeName)'/* 2>/dev/null || cd '\(safeName)'; \
        if [ -f install ]; then chmod +x install && ./install; fi && \
        echo '\(safeName)' >> '\(shellEscape(installedModsPath))/installed' && \
        rm -rf '\(shellEscape(modsBasePath))/\(safeName)' '\(shellEscape(modsBasePath))/\(safeName).hmod'
        """

        let result = try await ssh.execute(installCmd)
        HakchiLogger.mods.info("Install output: \(result)")

        progress?(1.0, "\(mod.name) installed successfully")
    }

    func uninstallMod(_ mod: Mod, ssh: SSHClient, progress: ((Double, String) -> Void)? = nil) async throws {
        HakchiLogger.mods.info("Uninstalling mod: \(mod.name)")

        let safeName = shellEscape(mod.name)
        progress?(0.1, "Removing \(mod.name)...")

        let uninstallCmd = """
        if [ -f '\(shellEscape(modsBasePath))/\(safeName)/uninstall' ]; then \
            cd '\(shellEscape(modsBasePath))/\(safeName)' && chmod +x uninstall && ./uninstall; \
        fi && \
        sed -i '/\(safeName)/d' '\(shellEscape(installedModsPath))/installed' 2>/dev/null; \
        rm -rf '\(shellEscape(modsBasePath))/\(safeName)'
        """

        try await ssh.execute(uninstallCmd)

        progress?(1.0, "\(mod.name) uninstalled")
        HakchiLogger.mods.info("Uninstalled mod: \(mod.name)")
    }

    func listInstalledMods(ssh: SSHClient) async throws -> [String] {
        let result = try await ssh.execute("cat '\(shellEscape(installedModsPath))/installed' 2>/dev/null || echo ''")
        return result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func scanLocalMods() -> [Mod] {
        FileUtils.ensureDirectoriesExist()
        let modsDir = FileUtils.modsDirectory

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modsDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files.compactMap { url -> Mod? in
            guard url.pathExtension == "hmod" ||
                  url.lastPathComponent.contains(".hmod") else { return nil }

            do {
                let hmod = try HmodPackage(url: url)
                return hmod.toMod()
            } catch {
                HakchiLogger.mods.error("Failed to parse hmod: \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }
}

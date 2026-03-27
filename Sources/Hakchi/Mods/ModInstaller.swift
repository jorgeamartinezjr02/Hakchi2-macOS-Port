import Foundation

final class ModInstaller {
    private let modsBasePath = "/var/lib/hakchi/transfer"
    private let installedModsPath = "/var/lib/hakchi/rootfs/etc/mods"

    func installMod(_ mod: Mod, ssh: SSHClient, progress: ((Double, String) -> Void)? = nil) async throws {
        HakchiLogger.mods.info("Installing mod: \(mod.name)")

        let sftp = SFTPClient(sshClient: ssh)

        progress?(0.1, "Preparing \(mod.name)...")

        // Ensure transfer directory exists
        try await ssh.execute("mkdir -p \(modsBasePath)")

        // Upload hmod file
        let remoteHmodPath = "\(modsBasePath)/\(mod.name).hmod"
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
        cd \(modsBasePath) && \
        mkdir -p \(mod.name) && \
        tar xzf \(mod.name).hmod -C \(mod.name) 2>/dev/null; \
        cd \(mod.name)/* 2>/dev/null || cd \(mod.name); \
        if [ -f install ]; then chmod +x install && ./install; fi && \
        echo '\(mod.name)' >> \(installedModsPath)/installed && \
        rm -rf \(modsBasePath)/\(mod.name) \(modsBasePath)/\(mod.name).hmod
        """

        let result = try await ssh.execute(installCmd)
        HakchiLogger.mods.info("Install output: \(result)")

        progress?(1.0, "\(mod.name) installed successfully")
    }

    func uninstallMod(_ mod: Mod, ssh: SSHClient, progress: ((Double, String) -> Void)? = nil) async throws {
        HakchiLogger.mods.info("Uninstalling mod: \(mod.name)")

        progress?(0.1, "Removing \(mod.name)...")

        let uninstallCmd = """
        if [ -f \(modsBasePath)/\(mod.name)/uninstall ]; then \
            cd \(modsBasePath)/\(mod.name) && chmod +x uninstall && ./uninstall; \
        fi && \
        sed -i '/\(mod.name)/d' \(installedModsPath)/installed 2>/dev/null; \
        rm -rf \(modsBasePath)/\(mod.name)
        """

        try await ssh.execute(uninstallCmd)

        progress?(1.0, "\(mod.name) uninstalled")
        HakchiLogger.mods.info("Uninstalled mod: \(mod.name)")
    }

    func listInstalledMods(ssh: SSHClient) async throws -> [String] {
        let result = try await ssh.execute("cat \(installedModsPath)/installed 2>/dev/null || echo ''")
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

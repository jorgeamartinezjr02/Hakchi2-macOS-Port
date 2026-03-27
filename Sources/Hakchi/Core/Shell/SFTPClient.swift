import Foundation
import CLibSSH2

final class SFTPClient {
    private let sshClient: SSHClient
    private var sftpSession: OpaquePointer?

    init(sshClient: SSHClient) {
        self.sshClient = sshClient
    }

    private func openSFTP() throws -> OpaquePointer {
        if let existing = sftpSession { return existing }

        guard let session = sshClient.getSession() else {
            throw HakchiError.notConnected
        }

        guard let sftp = libssh2_sftp_init(session) else {
            throw HakchiError.sftpTransferFailed("Failed to initialize SFTP session")
        }

        sftpSession = sftp
        return sftp
    }

    func closeSFTP() {
        if let sftp = sftpSession {
            libssh2_sftp_shutdown(sftp)
            sftpSession = nil
        }
    }

    func upload(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try uploadSync(localPath: localPath, remotePath: remotePath, progress: progress)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func uploadSync(localPath: String, remotePath: String, progress: ((Double) -> Void)? = nil) throws {
        let sftp = try openSFTP()

        let fileData = try Data(contentsOf: URL(fileURLWithPath: localPath))
        let totalSize = Double(fileData.count)

        guard let handle = libssh2_sftp_open(
            sftp,
            remotePath,
            UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
            Int(LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH)
        ) else {
            throw HakchiError.sftpTransferFailed("Failed to open remote file: \(remotePath)")
        }

        defer { libssh2_sftp_close(handle) }

        var offset = 0
        let chunkSize = 32768 // 32KB chunks

        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = fileData[offset..<end]

            let written = chunk.withUnsafeBytes { ptr in
                libssh2_sftp_write(handle, ptr.baseAddress, chunk.count)
            }

            guard written > 0 else {
                throw HakchiError.sftpTransferFailed("Write failed at offset \(offset)")
            }

            offset += Int(written)
            progress?(Double(offset) / totalSize)
        }

        HakchiLogger.ssh.info("Uploaded \(localPath) -> \(remotePath) (\(fileData.count) bytes)")
    }

    func download(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try downloadSync(remotePath: remotePath, localPath: localPath, progress: progress)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func downloadSync(remotePath: String, localPath: String, progress: ((Double) -> Void)? = nil) throws {
        let sftp = try openSFTP()

        // Get file size
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        libssh2_sftp_stat(sftp, remotePath, &attrs)
        let totalSize = Double(attrs.filesize)

        guard let handle = libssh2_sftp_open(
            sftp,
            remotePath,
            UInt(LIBSSH2_FXF_READ),
            0
        ) else {
            throw HakchiError.sftpTransferFailed("Failed to open remote file: \(remotePath)")
        }

        defer { libssh2_sftp_close(handle) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 32768)

        while true {
            let bytesRead = libssh2_sftp_read(handle, &buffer, buffer.count)
            if bytesRead > 0 {
                data.append(contentsOf: buffer[0..<Int(bytesRead)])
                if totalSize > 0 {
                    progress?(Double(data.count) / totalSize)
                }
            } else {
                break
            }
        }

        try data.write(to: URL(fileURLWithPath: localPath))
        HakchiLogger.ssh.info("Downloaded \(remotePath) -> \(localPath) (\(data.count) bytes)")
    }

    func mkdir(path: String) throws {
        let sftp = try openSFTP()
        libssh2_sftp_mkdir(sftp, path, Int(LIBSSH2_SFTP_S_IRWXU | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IXGRP))
    }

    func remove(path: String) throws {
        let sftp = try openSFTP()
        libssh2_sftp_unlink(sftp, path)
    }

    func listDirectory(path: String) throws -> [String] {
        let sftp = try openSFTP()

        guard let handle = libssh2_sftp_opendir(sftp, path) else {
            throw HakchiError.sftpTransferFailed("Failed to open directory: \(path)")
        }

        defer { libssh2_sftp_closedir(handle) }

        var entries: [String] = []
        var buffer = [CChar](repeating: 0, count: 512)
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()

        while libssh2_sftp_readdir(handle, &buffer, buffer.count, &attrs) > 0 {
            let name = String(cString: buffer)
            if name != "." && name != ".." {
                entries.append(name)
            }
        }

        return entries
    }
}

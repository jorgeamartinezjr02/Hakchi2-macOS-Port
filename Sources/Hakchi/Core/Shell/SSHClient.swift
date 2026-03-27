import Foundation
import CLibSSH2

final class SSHClient {
    private var session: OpaquePointer?
    private var socket: Int32 = -1
    private var isConnected = false

    deinit {
        disconnect()
    }

    func connect(host: String = "169.254.1.1", port: Int = 22, username: String = "root") async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try connectSync(host: host, port: port, username: username)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func connectSync(host: String, port: Int, username: String) throws {
        guard libssh2_init(0) == 0 else {
            throw HakchiError.sshConnectionFailed("Failed to initialize libssh2")
        }

        // Create socket
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw HakchiError.sshConnectionFailed("Failed to create socket")
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(socket)
            throw HakchiError.sshConnectionFailed("Failed to connect to \(host):\(port)")
        }

        // Create SSH session
        session = libssh2_session_init()
        guard let session = session else {
            Darwin.close(socket)
            throw HakchiError.sshConnectionFailed("Failed to create SSH session")
        }

        guard libssh2_session_handshake(session, socket) == 0 else {
            libssh2_session_free(session)
            self.session = nil
            Darwin.close(socket)
            throw HakchiError.sshConnectionFailed("SSH handshake failed")
        }

        // Authenticate (NES/SNES Classic uses password-less root)
        let authResult = libssh2_userauth_password_ex(
            session,
            username,
            UInt32(username.count),
            "",
            0,
            nil
        )

        if authResult != 0 {
            // Try keyboard-interactive or none
            let noneResult = libssh2_userauth_list(session, username, UInt32(username.count))
            if noneResult == nil {
                // Auth succeeded with "none"
            }
        }

        isConnected = true
        HakchiLogger.ssh.info("SSH connected to \(host):\(port)")
    }

    func disconnect() {
        if let session = session {
            libssh2_session_disconnect(session, "Normal shutdown")
            libssh2_session_free(session)
            self.session = nil
        }
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
        isConnected = false
        libssh2_exit()
    }

    @discardableResult
    func execute(_ command: String) async throws -> String {
        guard let session = session, isConnected else {
            throw HakchiError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard let channel = libssh2_channel_open_session(session) else {
                continuation.resume(throwing: HakchiError.sshConnectionFailed("Failed to open channel"))
                return
            }

            guard libssh2_channel_exec(channel, command) == 0 else {
                libssh2_channel_free(channel)
                continuation.resume(throwing: HakchiError.sshConnectionFailed("Failed to execute: \(command)"))
                return
            }

            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)

            while true {
                let bytesRead = libssh2_channel_read(channel, &buffer, buffer.count)
                if bytesRead > 0 {
                    output.append(contentsOf: buffer[0..<Int(bytesRead)])
                } else {
                    break
                }
            }

            libssh2_channel_close(channel)
            libssh2_channel_wait_closed(channel)
            libssh2_channel_free(channel)

            let result = String(data: output, encoding: .utf8) ?? ""
            HakchiLogger.ssh.debug("Executed: \(command) -> \(result.prefix(100))")
            continuation.resume(returning: result)
        }
    }

    func getSession() -> OpaquePointer? {
        return session
    }

    func getSocket() -> Int32 {
        return socket
    }
}

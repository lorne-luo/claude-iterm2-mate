import Foundation
import os

/// POSIX AF_UNIX stream listener. One message per connection: the client
/// writes JSON then closes; connection close is the frame boundary.
/// NWListener is deliberately not used — its unix-socket support is
/// undocumented and unreliable.
final class NotifyServer {
    enum StartError: Error {
        case alreadyRunning
        case socketFailed(String)
    }

    static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeItermMate/notify.sock")
            .path
    }

    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "NotifyServer")
    private static let readTimeoutSeconds = 2

    private let socketPath: String
    private let handler: (NotifyPayload) -> Void
    private let queue = DispatchQueue(label: "notify-server")
    private var source: DispatchSourceRead?

    init(socketPath: String, handler: @escaping (NotifyPayload) -> Void) {
        self.socketPath = socketPath
        self.handler = handler
    }

    func start() throws {
        // Single-instance guard: a connectable socket means another instance owns it.
        if Self.canConnect(path: socketPath) {
            throw StartError.alreadyRunning
        }
        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(socketPath) // stale file from a crash

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socketFailed("socket(): errno \(errno)") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard Self.fill(path: socketPath, into: &addr) else {
            close(fd)
            throw StartError.socketFailed("socket path too long: \(socketPath)")
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else {
            close(fd)
            throw StartError.socketFailed("bind(): errno \(errno)")
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 8) == 0 else {
            close(fd)
            unlink(socketPath)
            throw StartError.socketFailed("listen(): errno \(errno)")
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne(listenerFD: fd) }
        // Close the listener FD in the cancel handler: it runs on `queue`
        // after the last acceptOne completes, so the FD is never closed out
        // from under an in-flight accept/read.
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel() // cancel handler closes the listener FD on `queue`
        source = nil
        unlink(socketPath) // idempotent; safe to call from the main actor
    }

    private func acceptOne(listenerFD: Int32) {
        let fd = accept(listenerFD, nil, nil)
        guard fd >= 0 else { return }
        var tv = timeval(tv_sec: Self.readTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break } // 0 = EOF (frame complete), <0 = error/timeout
            data.append(buf, count: n)
            if data.count > NotifyPayload.maxPayloadBytes {
                Self.log.error("payload over 1 MB dropped")
                close(fd)
                return
            }
        }
        close(fd)

        guard let payload = NotifyPayload.decode(data) else {
            Self.log.error("invalid payload dropped (\(data.count) bytes)")
            return
        }
        DispatchQueue.main.async { [handler] in handler(payload) }
    }

    private static func canConnect(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard fill(path: path, into: &addr) else { return false }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        } == 0
    }

    private static func fill(path: String, into addr: inout sockaddr_un) -> Bool {
        path.withCString { cstr in
            guard strlen(cstr) < 104 else { return false }
            return withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                    strncpy(dst, cstr, 103)
                    return true
                }
            }
        }
    }
}

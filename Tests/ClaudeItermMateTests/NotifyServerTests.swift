import XCTest
@testable import ClaudeItermMate

final class NotifyServerTests: XCTestCase {
    private var socketPath: String!
    private var server: NotifyServer?

    override func setUp() {
        super.setUp()
        socketPath = NSTemporaryDirectory() + "mate-test-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        server?.stop()
        unlink(socketPath)
        super.tearDown()
    }

    /// Minimal POSIX client: connect, write, close (mirrors the Node hook).
    private func send(_ data: Data, to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst -> Bool in
                    guard strlen(cstr) < 104 else { return false }
                    strncpy(dst, cstr, 103)
                    return true
                }
            }
        }
        guard ok else { return false }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, len)
            }
        }
        guard connected == 0 else { return false }
        return data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress, buf.count) == buf.count
        }
    }

    private func validJSON() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "session_uuid": "S1", "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": "done", "full_message": "done", "timestamp": 1.0,
        ])
    }

    func testReceivesOneMessagePerConnection() throws {
        let exp = expectation(description: "payload")
        var received: NotifyPayload?
        server = NotifyServer(socketPath: socketPath) { p in
            received = p
            exp.fulfill()
        }
        try server!.start()
        XCTAssertTrue(send(validJSON(), to: socketPath))
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(received?.sessionUUID, "S1")
    }

    func testInvalidJSONIsDroppedWithoutCrash() throws {
        let exp = expectation(description: "second payload")
        server = NotifyServer(socketPath: socketPath) { _ in exp.fulfill() }
        try server!.start()
        XCTAssertTrue(send(Data("garbage".utf8), to: socketPath))
        XCTAssertTrue(send(validJSON(), to: socketPath)) // server still alive
        wait(for: [exp], timeout: 3)
    }

    func testSecondInstanceThrowsAlreadyRunning() throws {
        server = NotifyServer(socketPath: socketPath) { _ in }
        try server!.start()
        let second = NotifyServer(socketPath: socketPath) { _ in }
        XCTAssertThrowsError(try second.start()) { error in
            guard case NotifyServer.StartError.alreadyRunning = error else {
                return XCTFail("expected alreadyRunning, got \(error)")
            }
        }
    }

    func testStaleSocketFileIsReplaced() throws {
        FileManager.default.createFile(atPath: socketPath, contents: nil) // stale, unconnectable
        let exp = expectation(description: "payload")
        server = NotifyServer(socketPath: socketPath) { _ in exp.fulfill() }
        try server!.start()
        XCTAssertTrue(send(validJSON(), to: socketPath))
        wait(for: [exp], timeout: 3)
    }

    func testSocketFileMode0600() throws {
        server = NotifyServer(socketPath: socketPath) { _ in }
        try server!.start()
        let attrs = try FileManager.default.attributesOfItem(atPath: socketPath)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.uint16Value, 0o600)
    }
}

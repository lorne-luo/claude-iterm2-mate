import XCTest
@testable import ClaudeItermMate

final class PythonInterpreterTests: XCTestCase {
    func testParsesAbsoluteShebang() {
        XCTAssertEqual(
            PythonInterpreter.parseShebang("#!/Users/x/.local/share/uv/tools/it2/bin/python"),
            "/Users/x/.local/share/uv/tools/it2/bin/python"
        )
    }

    func testTolerantOfWhitespaceAfterBang() {
        XCTAssertEqual(PythonInterpreter.parseShebang("#!  /opt/venv/bin/python3.13  "), "/opt/venv/bin/python3.13")
    }

    func testDropsInterpreterArguments() {
        XCTAssertEqual(PythonInterpreter.parseShebang("#!/opt/venv/bin/python -S"), "/opt/venv/bin/python")
    }

    /// `env` resolves to the system Python, which has no `iterm2` — using it
    /// would make every spawn fail silently, so it must be rejected outright.
    func testRejectsEnvIndirection() {
        XCTAssertNil(PythonInterpreter.parseShebang("#!/usr/bin/env python3"))
        XCTAssertNil(PythonInterpreter.parseShebang("#!/opt/homebrew/bin/env python3"))
    }

    func testRejectsRelativeInterpreter() {
        XCTAssertNil(PythonInterpreter.parseShebang("#!python3"))
    }

    func testRejectsNonShebangLines() {
        XCTAssertNil(PythonInterpreter.parseShebang(""))
        XCTAssertNil(PythonInterpreter.parseShebang("# not a shebang"))
        XCTAssertNil(PythonInterpreter.parseShebang("import iterm2"))
    }

    func testResolveWithoutIt2IsNil() {
        XCTAssertNil(PythonInterpreter.resolve(it2URL: nil))
    }

    func testResolveReadsShebangOfIt2Launcher() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("py-interp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // /bin/sh is guaranteed executable; stand in for the venv interpreter.
        let it2 = dir.appendingPathComponent("it2")
        try "#!/bin/sh\n# launcher\n".write(to: it2, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            PythonInterpreter.resolve(it2URL: it2)?.path,
            "/bin/sh"
        )
    }

    func testResolveFallsBackToSiblingPythonWhenShebangUnusable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("py-interp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let it2 = dir.appendingPathComponent("it2")
        try "#!/usr/bin/env python3\n".write(to: it2, atomically: true, encoding: .utf8)
        let sibling = dir.appendingPathComponent("python")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: sibling)

        XCTAssertEqual(PythonInterpreter.resolve(it2URL: it2)?.path, sibling.path)
    }

    func testResolveNilWhenNeitherShebangNorSiblingUsable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("py-interp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let it2 = dir.appendingPathComponent("it2")
        try "#!/no/such/python\n".write(to: it2, atomically: true, encoding: .utf8)

        XCTAssertNil(PythonInterpreter.resolve(it2URL: it2))
    }

    /// `~/.local/bin/it2` is a symlink into the venv; the sibling fallback must
    /// resolve relative to the real file, not the symlink's directory.
    func testResolveFollowsSymlinkForSiblingFallback() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("py-interp-\(UUID().uuidString)")
        let venvBin = root.appendingPathComponent("venv/bin")
        let localBin = root.appendingPathComponent("local/bin")
        try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let realIt2 = venvBin.appendingPathComponent("it2")
        try "#!/usr/bin/env python3\n".write(to: realIt2, atomically: true, encoding: .utf8)
        let sibling = venvBin.appendingPathComponent("python")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: sibling)

        let link = localBin.appendingPathComponent("it2")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realIt2)

        XCTAssertEqual(PythonInterpreter.resolve(it2URL: link)?.path, sibling.path)
    }
}

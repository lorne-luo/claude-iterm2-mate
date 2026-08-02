import XCTest
@testable import ClaudeItermMate

final class ScriptInstallerTests: XCTestCase {
    func testShipsBothScriptsTheActionsSpawn() {
        XCTAssertEqual(ScriptInstaller.scriptNames, ["iterm-focus-pane", "set-pane-bg"])
    }

    func testDestURLIsAbsoluteAndUnderOurAppSupportDirectory() {
        for name in ScriptInstaller.scriptNames {
            let path = ScriptInstaller.destURL(for: name).path
            XCTAssertTrue(path.hasPrefix("/"), "Process does not expand ~; path must be absolute")
            XCTAssertFalse(path.contains("~"))
            XCTAssertTrue(path.hasSuffix("/Library/Application Support/ClaudeItermMate/\(name).py"))
        }
    }

    /// The scripts must land next to the notify socket / hook scripts, never in
    /// `~/.claude/` — ScriptInstaller writes only our own directory.
    func testDestURLNeverTouchesDotClaude() {
        for name in ScriptInstaller.scriptNames {
            XCTAssertFalse(ScriptInstaller.destURL(for: name).path.contains("/.claude/"))
        }
    }

    func testActionDefaultsPointAtTheInstalledCopies() {
        XCTAssertEqual(
            ItermFocusAction.defaultScriptURL, ScriptInstaller.destURL(for: "iterm-focus-pane")
        )
        XCTAssertEqual(
            ItermBgColorAction.defaultScriptURL, ScriptInstaller.destURL(for: "set-pane-bg")
        )
    }

    func testBundleCarriesBothScripts() {
        for name in ScriptInstaller.scriptNames {
            XCTAssertNotNil(
                Bundle.module.url(forResource: name, withExtension: "py"),
                "\(name).py missing from Package.swift resources"
            )
        }
    }

    /// The bundled scripts must not carry a machine-specific shebang: the app
    /// runs them through an explicit interpreter, and a hardcoded /Users/... path
    /// would be a dead giveaway that a stale machine-local copy got committed.
    func testBundledScriptsHaveNoAbsoluteUserShebang() throws {
        for name in ScriptInstaller.scriptNames {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "py"))
            let source = try String(contentsOf: url, encoding: .utf8)
            let first = try XCTUnwrap(source.split(separator: "\n").first.map(String.init))
            XCTAssertEqual(first, "#!/usr/bin/env python3", "\(name).py shebang")
            XCTAssertFalse(source.contains("/Users/"), "\(name).py has a machine-local path")
        }
    }
}

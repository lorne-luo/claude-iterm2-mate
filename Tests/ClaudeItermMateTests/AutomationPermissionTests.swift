import XCTest
@testable import ClaudeItermMate

/// `0` and `-600` were measured against a compiled probe calling
/// `AEDeterminePermissionToAutomateTarget` (prd F7); the two consent codes are
/// Apple's documented `errAEEventNotPermitted` / `errAEEventWouldRequireUserConsent`.
final class AutomationPermissionTests: XCTestCase {
    func testGranted() {
        XCTAssertEqual(AutomationPermission.state(for: noErr), .ok)
    }

    /// -1743: the user answered "Don't Allow". macOS will not ask again, so the
    /// window has to send them to System Settings.
    func testDeniedIsMissing() {
        XCTAssertEqual(AutomationPermission.state(for: -1743), .missing)
    }

    /// -1744: never asked. Missing, and curable by the Grant… button.
    func testWouldRequireConsentIsMissing() {
        XCTAssertEqual(AutomationPermission.state(for: -1744), .missing)
    }

    /// -600: the target is not running. macOS returns this for "not installed"
    /// too, but that case never reaches here — `DependencyReport` only asks when
    /// LaunchServices already found iTerm2. Either way we did not observe a
    /// denial, so this must not be reported as broken.
    func testTargetNotRunningIsUnknown() {
        XCTAssertEqual(AutomationPermission.state(for: -600), .unknown)
    }

    func testUnrecognizedStatusIsUnknown() {
        XCTAssertEqual(AutomationPermission.state(for: -1712), .unknown)
        XCTAssertEqual(AutomationPermission.state(for: 12345), .unknown)
    }
}

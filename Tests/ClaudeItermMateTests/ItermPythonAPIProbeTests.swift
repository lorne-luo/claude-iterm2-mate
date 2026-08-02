import XCTest
@testable import ClaudeItermMate

final class ItermPythonAPIProbeTests: XCTestCase {
    private func state(
        _ raw: Any?, socketExists: Bool = false, customPrefsFolder: Bool = false
    ) -> DependencyState {
        ItermPythonAPIProbe.state(
            rawEnableAPIServer: raw, socketExists: socketExists, customPrefsFolder: customPrefsFolder
        )
    }

    func testEnabledPreference() {
        XCTAssertEqual(state(true), .ok)
    }

    func testDisabledPreference() {
        XCTAssertEqual(state(false), .missing)
    }

    /// CFPreferences hands back a CFBoolean, which arrives as an NSNumber.
    func testNumericPreference() {
        XCTAssertEqual(state(NSNumber(value: true)), .ok)
        XCTAssertEqual(state(NSNumber(value: false)), .missing)
    }

    /// The key only exists once the user has touched the toggle, and the
    /// shipped default is off — absent means never enabled, not "unknown".
    func testAbsentKeyIsDisabled() {
        XCTAssertEqual(state(nil), .missing)
    }

    /// Anything we cannot read as a boolean is not something to guess about.
    func testUninterpretableValueIsUnknown() {
        XCTAssertEqual(state("yes"), .unknown)
    }

    /// D10: the API server creates its socket the moment it comes up, which is
    /// proof regardless of what the on-disk preference says — iTerm2 flushes
    /// its plist on its own schedule, and without this the row could stay red
    /// forever after the user ticks the box.
    func testLiveSocketOverridesADisabledPreference() {
        XCTAssertEqual(state(false, socketExists: true), .ok)
        XCTAssertEqual(state(nil, socketExists: true), .ok)
    }

    /// The socket is proof of enablement, never of the opposite: it is absent
    /// whenever iTerm2 is simply not running. So the preference alone decides
    /// when the socket is missing.
    func testAbsentSocketDoesNotOverrideAnEnabledPreference() {
        XCTAssertEqual(state(true, socketExists: false), .ok)
    }

    /// A custom preferences folder means the domain we read is not the one
    /// iTerm2 uses, so a "disabled" reading there proves nothing.
    func testCustomPrefsFolderIsUnknown() {
        XCTAssertEqual(state(false, customPrefsFolder: true), .unknown)
        XCTAssertEqual(state(nil, customPrefsFolder: true), .unknown)
        XCTAssertEqual(state(true, customPrefsFolder: true), .unknown)
    }

    /// …unless the socket is there, which is direct observation and needs no
    /// preferences file at all.
    func testLiveSocketBeatsACustomPrefsFolder() {
        XCTAssertEqual(state(nil, socketExists: true, customPrefsFolder: true), .ok)
    }
}

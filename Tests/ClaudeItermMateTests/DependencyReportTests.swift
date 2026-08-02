import XCTest
@testable import ClaudeItermMate

final class DependencyReportTests: XCTestCase {
    /// Everything present and an event already delivered → nothing to report.
    func testAllSatisfied() {
        let report = DependencyReport.evaluate(
            itermInstalled: true, it2Usable: true, hookInstalled: true, hasReceivedEvent: true
        )
        XCTAssertEqual(report.missing, [])
        XCTAssertFalse(report.hasAnyMissing)
    }

    func testItermMissing() {
        let report = DependencyReport.evaluate(
            itermInstalled: false, it2Usable: true, hookInstalled: true, hasReceivedEvent: true
        )
        XCTAssertEqual(report.missing, [.iterm2])
        XCTAssertTrue(report.hasAnyMissing)
    }

    func testIt2Missing() {
        let report = DependencyReport.evaluate(
            itermInstalled: true, it2Usable: false, hookInstalled: true, hasReceivedEvent: true
        )
        XCTAssertEqual(report.missing, [.it2])
    }

    func testBothMissing() {
        let report = DependencyReport.evaluate(
            itermInstalled: false, it2Usable: false, hookInstalled: true, hasReceivedEvent: true
        )
        XCTAssertEqual(report.missing, [.iterm2, .it2])
    }

    /// Hook not installed is "not started yet", not "broken" — never report
    /// delivery, even though no event has ever arrived.
    func testDeliveryNotReportedWhenHookNotInstalled() {
        let report = DependencyReport.evaluate(
            itermInstalled: true, it2Usable: true, hookInstalled: false, hasReceivedEvent: false
        )
        XCTAssertFalse(report.missing.contains(.delivery))
        XCTAssertEqual(report.missing, [])
    }

    func testDeliveryReportedWhenHookInstalledButNothingReceived() {
        let report = DependencyReport.evaluate(
            itermInstalled: true, it2Usable: true, hookInstalled: true, hasReceivedEvent: false
        )
        XCTAssertEqual(report.missing, [.delivery])
    }

    func testDeliveryClearedOnceAnEventArrived() {
        let report = DependencyReport.evaluate(
            itermInstalled: true, it2Usable: true, hookInstalled: true, hasReceivedEvent: true
        )
        XCTAssertFalse(report.missing.contains(.delivery))
    }

    func testAllThreeMissing() {
        let report = DependencyReport.evaluate(
            itermInstalled: false, it2Usable: false, hookInstalled: true, hasReceivedEvent: false
        )
        XCTAssertEqual(report.missing, [.iterm2, .it2, .delivery])
    }

    /// A2: the it2 row must carry the exact fix command and name all four
    /// features it takes down.
    func testIt2CopyCarriesInstallCommandAndAllFourFeatures() {
        let title = DependencyReport.Dependency.it2.menuTitle
        XCTAssertTrue(title.contains("uv tool install it2"), title)
        XCTAssertTrue(DependencyReport.Dependency.it2.toastLine.contains("uv tool install it2"))
        for feature in ["jump", "pane color", "/color", "question answers"] {
            XCTAssertTrue(title.contains(feature), "missing \(feature) in: \(title)")
        }
    }

    /// A2: the iTerm2 row must point at where to get it.
    func testItermCopyCarriesDownloadGuidance() {
        let title = DependencyReport.Dependency.iterm2.menuTitle
        XCTAssertTrue(title.contains("iTerm2"), title)
        XCTAssertTrue(title.contains("iterm2.com"), title)
        XCTAssertTrue(DependencyReport.Dependency.iterm2.toastLine.contains("iterm2.com"))
    }

    /// The delivery row must tell the user what to actually do about it: the
    /// likely cause (`node` unreachable) AND the action (restart Claude Code).
    /// Naming a cause without an action leaves the user stuck.
    func testDeliveryCopyMentionsNodeAndRestart() {
        for copy in [
            DependencyReport.Dependency.delivery.menuTitle,
            DependencyReport.Dependency.delivery.toastLine,
        ] {
            XCTAssertTrue(copy.contains("node"), copy)
            XCTAssertTrue(copy.lowercased().contains("restart"), copy)
        }
    }
}

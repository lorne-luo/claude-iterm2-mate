import XCTest
@testable import ClaudeItermMate

final class DependencyReportTests: XCTestCase {
    /// Everything healthy by default, so each test states only what it varies.
    private func evaluate(
        itermInstalled: Bool = true,
        it2Usable: Bool = true,
        uvInstalled: Bool = true,
        pythonAPI: DependencyState = .ok,
        automation: DependencyState = .ok,
        hookInstalled: Bool = true,
        hasReceivedEvent: Bool = true
    ) -> DependencyReport {
        DependencyReport.evaluate(
            itermInstalled: itermInstalled,
            it2Usable: it2Usable,
            uvInstalled: uvInstalled,
            pythonAPI: pythonAPI,
            automation: automation,
            hookInstalled: hookInstalled,
            hasReceivedEvent: hasReceivedEvent
        )
    }

    private func state(_ report: DependencyReport, _ dependency: DependencyReport.Dependency) -> DependencyState? {
        report.all.first { $0.dependency == dependency }?.state
    }

    // MARK: - The whole decision table

    func testAllSatisfied() {
        let report = evaluate()
        XCTAssertEqual(report.missing, [])
        XCTAssertFalse(report.hasAnyMissing)
        XCTAssertFalse(report.hasBlocking)
        XCTAssertTrue(report.all.allSatisfy { $0.state == .ok })
    }

    func testItermMissing() {
        let report = evaluate(itermInstalled: false)
        XCTAssertEqual(report.missing, [.iterm2])
        XCTAssertTrue(report.hasAnyMissing)
        XCTAssertTrue(report.hasBlocking)
    }

    func testIt2Missing() {
        let report = evaluate(it2Usable: false)
        XCTAssertEqual(report.missing, [.it2])
    }

    func testBothMissing() {
        let report = evaluate(itermInstalled: false, it2Usable: false)
        XCTAssertEqual(report.missing, [.iterm2, .it2])
    }

    /// `uv` only matters as the way to install `it2`. With a working `it2` it is
    /// noise, so the row must not exist at all — not even as a satisfied one.
    func testUvRowAbsentWhenIt2Usable() {
        for uvInstalled in [true, false] {
            let report = evaluate(it2Usable: true, uvInstalled: uvInstalled)
            XCTAssertNil(state(report, .uv), "uv row leaked with it2 usable (uvInstalled: \(uvInstalled))")
            XCTAssertFalse(report.missing.contains(.uv))
        }
    }

    func testUvRowAppearsSatisfiedWhenIt2MissingButUvPresent() {
        let report = evaluate(it2Usable: false, uvInstalled: true)
        XCTAssertEqual(state(report, .uv), .ok)
        XCTAssertEqual(report.missing, [.it2])
    }

    /// Both gone: report both, but only `it2` blocks — `uv` is the how-to-fix,
    /// so on its own it must never force the Setup window open.
    func testUvAndIt2BothMissingWithOnlyIt2Blocking() {
        let report = evaluate(it2Usable: false, uvInstalled: false)
        XCTAssertEqual(report.missing, [.it2, .uv])
        XCTAssertEqual(report.blocking, [.it2])
    }

    /// Without iTerm2 the Python API preference and the Apple Events grant are
    /// meaningless — reporting them would drown the one fix that matters.
    func testPythonAPIAndAutomationNotEvaluatedWithoutIterm() {
        let report = evaluate(itermInstalled: false, pythonAPI: .missing, automation: .missing)
        XCTAssertNil(state(report, .pythonAPI))
        XCTAssertNil(state(report, .automation))
        XCTAssertEqual(report.missing, [.iterm2])
    }

    func testPythonAPIDisabledIsBlocking() {
        let report = evaluate(pythonAPI: .missing)
        XCTAssertEqual(report.missing, [.pythonAPI])
        XCTAssertEqual(report.blocking, [.pythonAPI])
    }

    func testAutomationDeniedIsBlocking() {
        let report = evaluate(automation: .missing)
        XCTAssertEqual(report.missing, [.automation])
        XCTAssertEqual(report.blocking, [.automation])
    }

    /// D4: "cannot tell" is neither a pass nor a failure. It shows up in the
    /// Setup window as a grey `?` row, and nowhere else — a launch-time popup
    /// or a menu warning for something we did not actually observe is a lie.
    func testUnknownIsListedButNeverCountsAsMissing() {
        let report = evaluate(pythonAPI: .unknown, automation: .unknown)
        XCTAssertEqual(state(report, .pythonAPI), .unknown)
        XCTAssertEqual(state(report, .automation), .unknown)
        XCTAssertEqual(report.missing, [])
        XCTAssertEqual(report.blocking, [])
        XCTAssertFalse(report.hasAnyMissing)
        XCTAssertFalse(report.hasBlocking)
    }

    /// Hook not installed is "not opted in", not "broken" — never report delivery.
    func testDeliveryNotReportedWhenHookNotInstalled() {
        let report = evaluate(hookInstalled: false, hasReceivedEvent: false)
        XCTAssertNil(state(report, .delivery))
        XCTAssertEqual(report.missing, [])
    }

    func testDeliveryReportedWhenHookInstalledButNothingReceived() {
        let report = evaluate(hasReceivedEvent: false)
        XCTAssertEqual(report.missing, [.delivery])
    }

    /// A brand-new user who just installed the hook has never run a session, so
    /// delivery is false by construction. Blocking it would pop the window at
    /// every launch until they happen to finish a Claude turn.
    func testDeliveryIsDegradedNotBlocking() {
        let report = evaluate(hasReceivedEvent: false)
        XCTAssertEqual(report.blocking, [])
        XCTAssertFalse(report.hasBlocking)
        XCTAssertEqual(DependencyReport.Dependency.delivery.severity, .degraded)
        XCTAssertEqual(DependencyReport.Dependency.uv.severity, .degraded)
    }

    func testDeliveryClearedOnceAnEventArrived() {
        XCTAssertEqual(state(evaluate(), .delivery), .ok)
    }

    func testBlockingSeverities() {
        for dependency in [DependencyReport.Dependency.iterm2, .it2, .pythonAPI, .automation] {
            XCTAssertEqual(dependency.severity, .blocking, "\(dependency)")
        }
    }

    func testEverythingMissingAtOnce() {
        let report = evaluate(
            itermInstalled: false, it2Usable: false, uvInstalled: false, hasReceivedEvent: false
        )
        // No pythonAPI / automation: iTerm2 is not installed.
        XCTAssertEqual(report.missing, [.iterm2, .it2, .uv, .delivery])
        XCTAssertEqual(report.blocking, [.iterm2, .it2])
    }

    // MARK: - Ordering and details

    /// The menu rows, the toast lines and the Setup rows all read `all`/`missing`
    /// in order, so the order is a contract, not an accident.
    func testAllFollowsDeclarationOrder() {
        let report = evaluate(it2Usable: false)
        XCTAssertEqual(
            report.all.map(\.dependency),
            [.iterm2, .it2, .uv, .pythonAPI, .automation, .delivery]
        )
    }

    /// A satisfied row still has to say *why* it is satisfied, otherwise a green
    /// checklist is unfalsifiable to the user reading it.
    func testSatisfiedRowsCarryEvidence() {
        for status in evaluate().all {
            XCTAssertNotNil(status.detail, "\(status.dependency) has no evidence")
        }
    }

    /// An unknown row must explain what stopped us from checking, since the user
    /// has to undo that before Recheck can say anything.
    func testUnknownRowsExplainWhyTheyCannotBeChecked() {
        let report = evaluate(automation: .unknown)
        let automation = report.all.first { $0.dependency == .automation }
        XCTAssertEqual(automation?.detail, DependencyReport.Dependency.automation.unknownReason)
    }

    /// A missing row's subtitle is its impact, which `SetupRow` supplies — a
    /// detail here would silently win over it.
    func testMissingRowsCarryNoDetail() {
        let report = evaluate(it2Usable: false)
        XCTAssertNil(report.all.first { $0.dependency == .it2 }?.detail)
    }

    // MARK: - Copy

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

    /// The Python API cannot be flipped from here (D2), so every surface has to
    /// spell out the exact place inside iTerm2 where the user does it.
    func testPythonAPICopyNamesTheSettingPath() {
        for copy in [
            DependencyReport.Dependency.pythonAPI.menuTitle,
            DependencyReport.Dependency.pythonAPI.toastLine,
            DependencyReport.Dependency.pythonAPI.impact,
        ] {
            XCTAssertTrue(copy.contains("Enable Python API"), copy)
        }
    }

    func testEveryDependencyHasNonEmptyCopy() {
        for dependency in DependencyReport.Dependency.allCases {
            XCTAssertFalse(dependency.title.isEmpty, "\(dependency)")
            XCTAssertFalse(dependency.impact.isEmpty, "\(dependency)")
            XCTAssertFalse(dependency.menuTitle.isEmpty, "\(dependency)")
            XCTAssertFalse(dependency.toastLine.isEmpty, "\(dependency)")
            XCTAssertNotNil(dependency.fix.label, "\(dependency) offers no action")
        }
    }
}

import XCTest
@testable import ClaudeItermMate

final class SetupRowTests: XCTestCase {
    private func rows(
        itermInstalled: Bool = true,
        it2Usable: Bool = true,
        uvInstalled: Bool = true,
        pythonAPI: DependencyState = .ok,
        automation: DependencyState = .ok,
        hookInstalled: Bool = true,
        hasReceivedEvent: Bool = true
    ) -> [SetupRow] {
        SetupRow.rows(
            report: DependencyReport.evaluate(
                itermInstalled: itermInstalled,
                it2Usable: it2Usable,
                uvInstalled: uvInstalled,
                pythonAPI: pythonAPI,
                automation: automation,
                hookInstalled: hookInstalled,
                hasReceivedEvent: hasReceivedEvent
            ),
            hookInstalled: hookInstalled
        )
    }

    private func row(_ rows: [SetupRow], _ kind: SetupRow.Kind) -> SetupRow? {
        rows.first { $0.kind == kind }
    }

    // MARK: - Which rows, in what order

    /// The window reads straight through, so order is a contract. The hook is
    /// last because it is the opt-in, not a prerequisite.
    func testOrderFollowsDependencyDeclarationWithHookLast() {
        XCTAssertEqual(
            rows(it2Usable: false).map(\.kind),
            [
                .dependency(.iterm2), .dependency(.it2), .dependency(.uv),
                .dependency(.pythonAPI), .dependency(.automation), .dependency(.delivery),
                .hook,
            ]
        )
    }

    /// AC10: no iTerm2 means the Python API and the Apple Events grant are not
    /// even questions — a checklist of things that cannot apply hides the one
    /// row that does.
    func testNoPythonAPIOrAutomationRowsWithoutIterm() {
        let rows = rows(itermInstalled: false, pythonAPI: .missing, automation: .missing)
        XCTAssertNil(row(rows, .dependency(.pythonAPI)))
        XCTAssertNil(row(rows, .dependency(.automation)))
        XCTAssertEqual(row(rows, .dependency(.iterm2))?.state, .missing)
    }

    func testHookRowIsAlwaysPresent() {
        XCTAssertNotNil(row(rows(hookInstalled: true), .hook))
        XCTAssertNotNil(row(rows(hookInstalled: false, hasReceivedEvent: false), .hook))
    }

    // MARK: - Row contents

    /// AC10: the grey `?` row must say what is blocking the check, and offer the
    /// action that unblocks it — otherwise the user is told "we don't know" and
    /// left with nothing to press.
    func testUnknownAutomationRowExplainsItselfAndOffersToStartIterm() {
        let automation = row(rows(automation: .unknown), .dependency(.automation))
        XCTAssertEqual(automation?.state, .unknown)
        XCTAssertEqual(automation?.subtitle, DependencyReport.Dependency.automation.unknownReason)
        XCTAssertTrue(automation?.subtitle.contains("not running") == true, automation?.subtitle ?? "")
        XCTAssertEqual(automation?.fix, .openIterm(label: "Open iTerm2"))
    }

    /// The same goes for an unreadable Python API preference: starting iTerm2 is
    /// what makes the check answerable (its live API socket settles it).
    func testUnknownPythonAPIRowOffersToStartIterm() {
        let api = row(rows(pythonAPI: .unknown), .dependency(.pythonAPI))
        XCTAssertEqual(api?.state, .unknown)
        XCTAssertEqual(api?.fix, .openIterm(label: "Open iTerm2"))
    }

    /// A broken row explains what breaks; a healthy one shows the evidence.
    func testSubtitlesSwitchFromImpactToEvidence() {
        XCTAssertEqual(
            row(rows(it2Usable: false), .dependency(.it2))?.subtitle,
            DependencyReport.Dependency.it2.impact
        )
        XCTAssertEqual(
            row(rows(), .dependency(.it2))?.subtitle,
            DependencyReport.Dependency.it2.okDetail
        )
    }

    /// Nothing to fix on a green row — a live button there invites the user to
    /// "repair" something that already works.
    func testSatisfiedRowsOfferNoAction() {
        for row in rows() {
            XCTAssertEqual(row.state, .ok, "\(row.kind)")
            XCTAssertEqual(row.fix, Fix.none, "\(row.kind)")
            XCTAssertNil(row.fix.label, "\(row.kind)")
        }
    }

    func testMissingRowsCarryTheirDependencyFix() {
        XCTAssertEqual(
            row(rows(automation: .missing), .dependency(.automation))?.fix,
            .grantAutomation
        )
        XCTAssertEqual(
            row(rows(it2Usable: false), .dependency(.it2))?.fix,
            DependencyReport.Dependency.it2.fix
        )
    }

    // MARK: - The hook row

    func testHookRowInstalled() {
        let hook = row(rows(hookInstalled: true), .hook)
        XCTAssertEqual(hook?.state, .ok)
        XCTAssertEqual(hook?.fix, Fix.none)
    }

    func testHookRowNotInstalledOffersTheInstaller() {
        let hook = row(rows(hookInstalled: false, hasReceivedEvent: false), .hook)
        XCTAssertEqual(hook?.state, .missing)
        XCTAssertEqual(hook?.fix, .installHook)
        XCTAssertFalse(hook?.subtitle.isEmpty ?? true)
    }

    func testEveryRowHasATitleAndSubtitle() {
        for row in rows(itermInstalled: false, it2Usable: false, hookInstalled: false, hasReceivedEvent: false) {
            XCTAssertFalse(row.title.isEmpty, "\(row.kind)")
            XCTAssertFalse(row.subtitle.isEmpty, "\(row.kind)")
        }
    }
}

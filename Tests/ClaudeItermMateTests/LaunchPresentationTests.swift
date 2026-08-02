import XCTest
@testable import ClaudeItermMate

final class LaunchPresentationTests: XCTestCase {
    /// A fully healthy world, so each test states only what it varies.
    private func report(
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

    private func decide(
        _ report: DependencyReport, hookInstalled: Bool = true, suppressed: Bool = false
    ) -> LaunchPresentation.Action {
        LaunchPresentation.decide(report: report, hookInstalled: hookInstalled, suppressed: suppressed)
    }

    /// Anything blocking is worth interrupting for — the app cannot do its job.
    func testBlockingOpensTheSetupWindow() {
        XCTAssertEqual(decide(report(pythonAPI: .missing)), .setupWindow)
        XCTAssertEqual(decide(report(it2Usable: false)), .setupWindow)
        XCTAssertEqual(decide(report(itermInstalled: false)), .setupWindow)
        XCTAssertEqual(decide(report(automation: .missing)), .setupWindow)
    }

    /// AC9: without the hook nothing arrives at all, and the window is where the
    /// Install button lives — so this opens it even with every dependency green.
    func testMissingHookOpensTheSetupWindow() {
        XCTAssertEqual(
            decide(report(hookInstalled: false, hasReceivedEvent: false), hookInstalled: false),
            .setupWindow
        )
    }

    /// AC5: a brand-new user has the hook installed and no event yet. Popping a
    /// window at every launch for that would be pure noise.
    func testDegradedOnlyFallsBackToTheToast() {
        XCTAssertEqual(decide(report(hasReceivedEvent: false)), .infoToast)
    }

    /// `uv` on its own is degraded too — but it only ever appears alongside a
    /// missing `it2`, which does block.
    func testUvAlongsideIt2StillBlocks() {
        XCTAssertEqual(decide(report(it2Usable: false, uvInstalled: false)), .setupWindow)
    }

    /// AC7: nothing to say, so say nothing.
    func testEverythingHealthyShowsNothing() {
        XCTAssertEqual(decide(report()), .none)
    }

    /// AC6: the escape hatch suppresses the window and only the window. When
    /// something is still missing the quieter toast takes over.
    func testSuppressedNeverOpensTheWindow() {
        for report in [
            report(pythonAPI: .missing),
            report(it2Usable: false),
            report(itermInstalled: false),
        ] {
            XCTAssertNotEqual(decide(report, suppressed: true), .setupWindow)
            XCTAssertEqual(decide(report, suppressed: true), .infoToast)
        }
    }

    /// Suppressed *and* nothing observed missing: the hook being absent is not a
    /// fault, so there is nothing for the toast to list either.
    func testSuppressedWithOnlyAMissingHookShowsNothing() {
        XCTAssertEqual(
            decide(
                report(hookInstalled: false, hasReceivedEvent: false),
                hookInstalled: false, suppressed: true
            ),
            .none
        )
    }

    /// D4: an undeterminable row is not evidence of a problem. It must not open
    /// the window and must not put a line in the toast — it exists only inside
    /// the checklist, where the user can go looking for it.
    func testUnknownRowsAloneShowNothing() {
        XCTAssertEqual(decide(report(pythonAPI: .unknown, automation: .unknown)), .none)
    }
}

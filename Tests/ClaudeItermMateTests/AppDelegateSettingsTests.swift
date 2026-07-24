import XCTest
@testable import ClaudeItermMate

@MainActor
final class AppDelegateSettingsTests: XCTestCase {
    struct FindableProbe: ItermSessionProbe {
        func canFind(_ uuid: String) -> Bool { true }
    }

    private func payload(session: String) -> NotifyPayload {
        NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: [
            "session_uuid": session,
            "cwd": "/tmp/proj",
            "title": "[CC] proj",
            "summary": "done",
            "full_message": "done",
            "timestamp": 1.0,
            "repo_root": "/tmp/proj",
            "type": "stop",
        ]))!
    }

    private func coordinator(duration: TimeInterval = 0.05) -> ReminderCoordinator {
        ReminderCoordinator(
            store: ReminderStore(),
            toastDuration: duration,
            toastPanel: nil,
            probe: FindableProbe()
        )
    }

    func testTabStripSettingControlsToastDemotionAtRuntime() async throws {
        let previous = AppSettings.showTabStrip
        defer { AppSettings.showTabStrip = previous }

        let coordinator = coordinator()
        AppDelegate.configureReminderSettings(on: coordinator, playSound: {})

        AppSettings.showTabStrip = false
        coordinator.handle(payload(session: "OFF"))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(coordinator.store.items.isEmpty, "disabled strip must not retain a tab")

        AppSettings.showTabStrip = true
        coordinator.handle(payload(session: "ON"))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(coordinator.store.items.map(\.sessionUUID), ["ON"])
        XCTAssertEqual(coordinator.store.items.first?.phase, .queued)
    }

    func testSoundSettingControlsPlaybackAtRuntime() async throws {
        let previous = AppSettings.playSound
        defer { AppSettings.playSound = previous }

        let coordinator = coordinator(duration: 1)
        var playCount = 0
        AppDelegate.configureReminderSettings(on: coordinator) { playCount += 1 }

        AppSettings.playSound = false
        coordinator.handle(payload(session: "MUTED"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(playCount, 0)

        AppSettings.playSound = true
        coordinator.handle(payload(session: "AUDIBLE"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(playCount, 1)
    }
}

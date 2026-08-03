import XCTest
@testable import ClaudeItermMate

/// AskUserQuestion fires a rich `question` PreToolUse *and* a generic
/// `permission_prompt` Notification sharing one `prompt_id`. The generic event
/// must never clobber the rich toast.
///
/// The regression these cover: `handle` runs `reconcile` BEFORE `present`, and
/// reconcile removes items whose session is not in the iTerm2 live set. That
/// deleted the question item out from under the old store-state guard, so the
/// permission event was treated as brand new and toasted over the question. The
/// probe below returns an empty live set to model exactly that (a closed pane
/// whose Claude process is still alive).
@MainActor
final class QuestionPermissionDedupeTests: XCTestCase {
    /// Counts presentations; that is all these tests assert on.
    final class CountingToast: ToastPanelProtocol {
        var shown: [String] = []
        func show(item: ReminderItem, on visible: CGRect, showsMinimize: Bool,
                  onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
                  onMinimize: @escaping () -> Void, onClose: @escaping () -> Void,
                  onAnswer: @escaping (ItermSendTextAction.Answer, Int) -> Void,
                  onChat: @escaping () -> Void,
                  onJumpMaximized: @escaping () -> Void,
                  onQuickReply: @escaping (QuickReply) -> Void) {
            shown.append(item.sessionUUID)
        }
        func hide(intoTab: Bool) {}
    }

    /// Always reports an empty live set, so reconcile GCs every stored item —
    /// the condition under which the old guard failed.
    struct NoLiveSessionsProbe: ItermSessionProbe {
        func canFind(_ uuid: String) -> Bool { false }
        func liveSessionIDs() -> Set<String>? { [] }
    }

    private func questionPayload(promptID: String?) -> NotifyPayload {
        var body: [String: Any] = [
            "session_uuid": "S1", "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": "Pick one", "full_message": "Pick one", "timestamp": 1.0,
            "repo_root": "/tmp/proj", "type": "question", "status": "waiting",
            "questions": [["question": "Pick one", "header": "H", "multiSelect": false,
                           "options": [["label": "A", "description": ""],
                                       ["label": "B", "description": ""]]]],
        ]
        if let promptID { body["prompt_id"] = promptID }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: body))!
    }

    /// The generic companion event: waiting, but no `type` and no questions.
    private func permissionPayload(promptID: String?) -> NotifyPayload {
        var body: [String: Any] = [
            "session_uuid": "S1", "cwd": "/tmp/proj", "title": "[CC] proj",
            "summary": "Claude needs your permission",
            "full_message": "Claude needs your permission to use Bash",
            "timestamp": 2.0, "repo_root": "/tmp/proj", "status": "waiting",
        ]
        if let promptID { body["prompt_id"] = promptID }
        return NotifyPayload.decode(try! JSONSerialization.data(withJSONObject: body))!
    }

    private func coordinator(_ toast: CountingToast) -> ReminderCoordinator {
        // Long toast duration so nothing expires mid-test.
        ReminderCoordinator(store: ReminderStore(), toastDuration: 30, toastPanel: toast,
                            probe: NoLiveSessionsProbe())
    }

    /// `handle` probes off-main then presents on main; yield for that round-trip.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(240))
    }

    func testCompanionPermissionIsDroppedEvenAfterReconcileGCdTheQuestion() async throws {
        let toast = CountingToast()
        let coord = coordinator(toast)
        coord.handle(questionPayload(promptID: "P-A"))
        try await settle()
        XCTAssertEqual(toast.shown.count, 1)
        // Same prompt_id → recognised as the question's companion and dropped,
        // even though reconcile already removed the question item from the store.
        coord.handle(permissionPayload(promptID: "P-A"))
        try await settle()
        XCTAssertEqual(toast.shown.count, 1, "companion permission event must not re-toast")
    }

    func testGenuinePermissionRequestWithADifferentPromptStillToasts() async throws {
        let toast = CountingToast()
        let coord = coordinator(toast)
        coord.handle(questionPayload(promptID: "P-A"))
        try await settle()
        // A real permission request belongs to a different turn, so it carries a
        // different prompt_id and MUST get through — suppressing it would hide a
        // prompt the user has to act on.
        coord.handle(permissionPayload(promptID: "P-B"))
        try await settle()
        XCTAssertEqual(toast.shown.count, 2)
    }

    /// Documents the residual gap rather than pretending it is fixed: with a hook
    /// script predating `prompt_id`, the only available signal is the store, and
    /// reconcile has already cleared it. Resolves itself on the next app launch,
    /// which republishes the bundled scripts.
    func testWithoutPromptIDTheStoreStateFallbackStillMissesAfterGC() async throws {
        let toast = CountingToast()
        let coord = coordinator(toast)
        coord.handle(questionPayload(promptID: nil))
        try await settle()
        coord.handle(permissionPayload(promptID: nil))
        try await settle()
        XCTAssertEqual(toast.shown.count, 2, "known gap for pre-prompt_id hook scripts")
    }

    /// The store-state fallback must still work when reconcile does NOT run
    /// (probe returning nil = unknown), which is the common case for a live pane.
    func testStoreStateFallbackStillDropsCompanionWhenNothingIsGCd() async throws {
        struct UnknownLiveProbe: ItermSessionProbe {
            func canFind(_ uuid: String) -> Bool { true }
            // liveSessionIDs() defaults to nil → reconcile skips GC.
        }
        let toast = CountingToast()
        let coord = ReminderCoordinator(store: ReminderStore(), toastDuration: 30,
                                        toastPanel: toast, probe: UnknownLiveProbe())
        coord.handle(questionPayload(promptID: nil))
        try await settle()
        coord.handle(permissionPayload(promptID: nil))
        try await settle()
        XCTAssertEqual(toast.shown.count, 1, "question item survives, so the fallback catches it")
    }
}

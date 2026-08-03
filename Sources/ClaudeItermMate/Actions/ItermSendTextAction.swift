import Foundation
import os

/// Answers an AskUserQuestion prompt by injecting keystrokes into the owning
/// iTerm2 pane via `it2 session send -s <uuid> <fragment>` (no trailing newline;
/// an explicit "\r" fragment submits). Fire-and-forget, gated on `it2`.
///
/// The exact key sequences were verified against the real Claude Code
/// AskUserQuestion TUI (see the task's design.md SPIKE section):
///   - single-select option i (1-based): send "i" -> selects and submits.
///   - free text s: send "K+1" (the "Type something" row, K = option count) ->
///     send s -> send "\r".
///   - multi-select {i…}: send each "i" to toggle -> send "\u{1b}[C" (right
///     arrow, to the Submit review page) -> send "1" (Submit answers).
struct ItermSendTextAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermSendText")

    /// What the user picked in the panel.
    enum Answer: Equatable {
        case option(Int)      // 1-based index (single-select)
        case multi([Int])     // 1-based indices (multiSelect)
        case text(String)     // free-text via the "Type something" row
    }

    let it2URL: URL?

    init(it2URL: URL? = ItermFocusAction.resolveIt2()) {
        self.it2URL = it2URL
    }

    var available: Bool { it2URL != nil }

    /// Right-arrow escape: moves the multiSelect prompt to its Submit page.
    static let rightArrow = "\u{1b}[C"
    /// Carriage return: submits the free-text row.
    static let submit = "\r"

    /// Pure, unit-tested: the ordered `it2 session send` fragments for an answer.
    /// `optionCount` is the number of real options K (excludes the built-in
    /// "Type something" / "Chat about this" rows).
    static func injectionSequence(_ answer: Answer, optionCount: Int) -> [String] {
        switch answer {
        case let .option(i):
            return ["\(i)"]
        case let .text(s):
            return ["\(optionCount + 1)", s, submit]
        case let .multi(indices):
            return indices.map { "\($0)" } + [rightArrow, "1"]
        }
    }

    /// Pure, unit-tested argv for one fragment.
    static func arguments(sessionUUID: String, fragment: String) -> [String] {
        ["session", "send", "-s", sessionUUID, fragment]
    }

    /// Send the answer to the pane. Runs each fragment sequentially (order
    /// matters) and blocks briefly per spawn; callers dispatch off-main.
    /// Returns false when the answer did not reach the pane — `it2` exits
    /// non-zero (e.g. `Session '…' not found`, exit 3, which the iTerm2 Python
    /// API produces intermittently) while `Process.run()` still succeeds, so the
    /// status has to be checked or the failure is completely silent.
    @discardableResult
    func answer(sessionUUID: String, answer: Answer, optionCount: Int) -> Bool {
        guard let it2URL else {
            Self.log.info("it2 unavailable; answer injection skipped")
            return false
        }
        for fragment in Self.injectionSequence(answer, optionCount: optionCount) {
            let p = Process()
            p.executableURL = it2URL
            p.arguments = Self.arguments(sessionUUID: sessionUUID, fragment: fragment)
            // it2 explains the failure on stderr; without a pipe it lands on the
            // app's inherited stderr where nobody looks.
            let errPipe = Pipe()
            p.standardError = errPipe
            do {
                try p.run()
                // Read before waiting: a full pipe buffer would deadlock the child.
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    let detail = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Self.log.error("answer send exited \(p.terminationStatus): \(detail, privacy: .public)")
                    return false
                }
            } catch {
                Self.log.error("answer send failed: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }
}

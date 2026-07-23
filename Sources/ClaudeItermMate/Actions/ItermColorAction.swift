import Foundation
import os

/// Injects `/color <name>` into a Claude Code session via the `it2` CLI so the
/// prompt-bar color matches the app's tab color for that project.
///
/// The injected text starts with ctrl+s (0x13): Claude Code stashes any text
/// already in the composer, our command runs on an empty prompt, and the
/// stashed text pops back afterwards — so injection can never mangle or
/// prematurely submit what the user was typing. The submit key MUST be \r
/// (0x0D, what a real Return key sends): Claude Code's raw-mode TUI does not
/// submit on \n (0x0A, ctrl+j) — `it2 session run`'s appended \n leaves the
/// command sitting unsubmitted in the composer (verified live), so we use
/// `session send` with an explicit trailing \r instead. Fire-and-forget: any
/// failure is logged and otherwise ignored.
struct ItermColorAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermColor")

    /// ctrl+s — Claude Code's "stash prompt input" shortcut.
    static let stashKey = "\u{13}"

    let it2URL: URL?

    init(it2URL: URL? = ItermFocusAction.resolveIt2()) {
        self.it2URL = it2URL
    }

    var available: Bool { it2URL != nil }

    /// Pure, unit-tested argv builder: stash + the slash command + \r submit.
    /// Keeps the injected text tiny by construction.
    static func arguments(sessionUUID: String, colorName: String) -> [String] {
        ["session", "send", "-s", sessionUUID, "\(stashKey)/color \(colorName)\r"]
    }

    func inject(sessionUUID: String, colorName: String) {
        guard let it2URL else {
            Self.log.info("it2 unavailable; /color injection skipped")
            return
        }
        let p = ItermFocusAction.it2Process(
            it2URL: it2URL,
            arguments: Self.arguments(sessionUUID: sessionUUID, colorName: colorName)
        )
        do {
            try p.run()
        } catch {
            Self.log.error("color injection spawn failed: \(error.localizedDescription)")
        }
    }
}

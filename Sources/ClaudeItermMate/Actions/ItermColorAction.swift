import Foundation
import os

/// Injects `/color <name>` into a Claude Code session via the `it2` CLI so the
/// prompt-bar color matches the app's tab color for that project.
///
/// TWO sends, in order. The first carries only ctrl+s (0x13), Claude Code's
/// "stash prompt input" shortcut: any text already in the composer is stashed,
/// our command runs on an empty prompt, and the stashed text pops back
/// afterwards — so injection can never mangle or prematurely submit what the
/// user was typing. The second carries the slash command. They are separate
/// invocations, each awaited, so the TUI has actually processed the stash
/// shortcut before the command's characters arrive; two concurrent `it2`
/// processes could race and let `/color` land first, which is the exact
/// mangling this split prevents. The submit key MUST be \r (0x0D, what a real
/// Return key sends): Claude Code's raw-mode TUI does not submit on \n (0x0A,
/// ctrl+j) — `it2 session run`'s appended \n leaves the command sitting
/// unsubmitted in the composer (verified live), so we use `session send` with
/// an explicit trailing \r instead.
///
/// `inject` BLOCKS its calling thread for up to `sendTimeout` per send, i.e. up
/// to twice that across the two sequential sends. That wait is exactly what
/// guarantees the stash has been processed before `/color`'s characters arrive,
/// so it cannot be dropped. It is bounded because a hung `it2` (the iTerm2 API
/// connection can stall — `set-pane-bg.py` carries `signal.alarm(10)` for the
/// same reason) would otherwise park a thread on the shared utility queue
/// forever. The sole caller already runs off the main thread (AppDelegate wires
/// `onInjectColor` onto `DispatchQueue.global(qos: .utility)`), so no UI work is
/// held up. Every failure — spawn error or timeout — is logged and otherwise
/// ignored; the caller never learns the outcome.
struct ItermColorAction {
    private static let log = Logger(subsystem: "io.lorne.claude-iterm2-mate", category: "ItermColor")

    /// ctrl+s — Claude Code's "stash prompt input" shortcut.
    static let stashKey = "\u{13}"

    /// Upper bound on how long one send may block the calling thread. A local
    /// CLI round-trip is milliseconds; anything near this is a hung `it2`.
    static let sendTimeout: DispatchTimeInterval = .seconds(5)

    let it2URL: URL?

    init(it2URL: URL? = ItermFocusAction.resolveIt2()) {
        self.it2URL = it2URL
    }

    var available: Bool { it2URL != nil }

    /// Pure, unit-tested argv builder for the first send: the stash key alone.
    static func stashArguments(sessionUUID: String) -> [String] {
        ["session", "send", "-s", sessionUUID, stashKey]
    }

    /// Pure, unit-tested argv builder for the second send: the slash command +
    /// \r submit, with no stash prefix (that is its own send now). Keeps the
    /// injected text tiny by construction.
    static func arguments(sessionUUID: String, colorName: String) -> [String] {
        ["session", "send", "-s", sessionUUID, "/color \(colorName)\r"]
    }

    func inject(sessionUUID: String, colorName: String) {
        guard let it2URL else {
            Self.log.info("it2 unavailable; /color injection skipped")
            return
        }
        // Wait on each send: the ordering guarantee is the whole point of the
        // split. Safe to block — the caller already runs this off the main
        // thread (AppDelegate wires `onInjectColor` onto a utility queue) — and
        // the wait is bounded so a hung `it2` cannot park that thread forever.
        run(it2URL: it2URL, arguments: Self.stashArguments(sessionUUID: sessionUUID), what: "stash")
        // Still attempt the command if the stash spawn failed or timed out: the
        // old single-send shape had no stash guarantee either, and skipping here
        // would silently lose the coloring.
        run(
            it2URL: it2URL,
            arguments: Self.arguments(sessionUUID: sessionUUID, colorName: colorName),
            what: "/color"
        )
    }

    /// Spawn one send and wait for it, but never longer than `sendTimeout`:
    /// `terminationHandler` signals the semaphore, and a timeout kills the
    /// process so it cannot linger either.
    private func run(it2URL: URL, arguments: [String], what: String) {
        let p = ItermFocusAction.it2Process(it2URL: it2URL, arguments: arguments)
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do {
            try p.run()
        } catch {
            Self.log.error("\(what) send spawn failed: \(error.localizedDescription)")
            return
        }
        if done.wait(timeout: .now() + Self.sendTimeout) == .timedOut {
            Self.log.error("\(what) send timed out; terminating it2")
            p.terminate()
        }
    }
}

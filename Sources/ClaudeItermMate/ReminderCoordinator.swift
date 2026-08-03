import AppKit
import Foundation

/// Owns the toast timer and the toasting→queued phase transition.
/// The store stays timer-free and fully synchronous for testability.
@MainActor
final class ReminderCoordinator {
    let store: ReminderStore

    private let toastDuration: TimeInterval
    private let toastPanel: ToastPanelProtocol?
    private let probe: ItermSessionProbe

    /// Owns the in-memory usage snapshot; refreshed (non-blocking) on each
    /// reminder and probed for claude-hud's cache on each session_start.
    private let usage: UsageService?

    /// Invoked when a toast is clicked — jump to the pane and consume the
    /// reminder (same as clicking its tab). Injected by AppDelegate.
    var onActivate: ((ReminderItem) -> Void)?

    /// Invoked when the user answers an AskUserQuestion directly from the toast:
    /// the chosen answer + the question's option count (to build the tty
    /// sequence). Same contract as `DetailPanel.onAnswer`; AppDelegate wires both
    /// to one implementation.
    var onAnswer: ((ReminderItem, ItermSendTextAction.Answer, Int) -> Void)?

    /// Invoked for "Chat about this" from the toast: jump to + maximize the pane.
    /// Same contract as `DetailPanel.onChat`.
    var onChat: ((ReminderItem) -> Void)?

    /// Invoked when a quick-reply icon is clicked on the toast: type the canned
    /// prompt into the pane and submit it. Same contract as
    /// `DetailPanel.onQuickReply`.
    var onQuickReply: ((ReminderItem, QuickReply) -> Void)?

    /// Invoked when the toast's title row is double-clicked: jump to the pane and
    /// maximize it unconditionally (ignoring the maximize-on-click toggle), then
    /// consume the reminder. Same contract as `DetailPanel.onJumpMaximized`.
    var onJumpMaximized: ((ReminderItem) -> Void)?

    /// Invoked to color a session's iTerm2 pane background (`RRGGBB` hex).
    /// AppDelegate wires this to `ItermBgColorAction` (off-main, fire-and-forget);
    /// tests observe it. Gating/dedup happen in `colorPaneIfNeeded` before this
    /// is called.
    var onSetPaneBackground: ((_ sessionUUID: String, _ hex: String) -> Void)?

    /// Invoked to restore a session's iTerm2 pane background to its profile
    /// default when the Claude Code process exited (the pane itself lives on, as
    /// a plain shell). AppDelegate wires this to `ItermBgColorAction.reset`
    /// (off-main, fire-and-forget); tests observe it. Gating lives in the
    /// `isResolve` branch of `handle`.
    var onResetPaneBackground: ((_ sessionUUID: String) -> Void)?

    /// Invoked to inject `/color <name>` into a session's iTerm2 prompt bar.
    /// AppDelegate wires this to `ItermColorAction` (off-main, fire-and-forget);
    /// tests observe it. Gating/dedup happen in `injectColorIfNeeded` first.
    var onInjectColor: ((_ sessionUUID: String, _ colorName: String) -> Void)?

    /// Whether pane background coloring is enabled. Injected gate (same pattern
    /// as `isNonItermEnabled`); AppDelegate wires it to `AppSettings.colorPanes`.
    /// Kept here (not in the AppDelegate closure) so `coloredSessions` only
    /// records a session when coloring actually applies.
    var isPaneColoringEnabled: () -> Bool = { true }

    /// Whether non-iTerm2 (non-focusable) sessions should be announced at all.
    /// When true they fire a desktop notification via `onNotify`; when false
    /// they are silent. Non-iTerm2 sessions never become tabs — there is no pane
    /// to jump to. Defaults to on; AppDelegate wires it to `AppSettings.showNonIterm`.
    var isNonItermEnabled: () -> Bool = { true }

    /// Emit a desktop notification (title, subtitle, body) for a non-iTerm2
    /// session when `isNonItermEnabled` is on. Injected by AppDelegate.
    var onNotify: ((_ title: String, _ subtitle: String, _ body: String) -> Void)?

    /// Whether a reminder demotes into a persistent right-edge tab after its
    /// toast expires. Off → the toast still flies in but is dropped on expiry
    /// (no tab). Defaults to on; AppDelegate wires it to `AppSettings.showTabStrip`.
    var isTabStripEnabled: () -> Bool = { true }

    /// Whether a system sound plays when a new toast is presented. Defaults to
    /// on; AppDelegate wires it to `AppSettings.playSound`.
    var isSoundEnabled: () -> Bool = { true }

    /// Invoked at the very top of `handle` for ANY payload — proof that the
    /// Node hook → socket path works end to end. AppDelegate latches
    /// `AppSettings.hasReceivedEvent`; injected (not read directly) to keep the
    /// coordinator testable, like `isTabStripEnabled` / `isSoundEnabled`.
    var onDidReceiveEvent: (() -> Void)?

    /// Play the reminder sound. Injected by AppDelegate; tests observe it.
    /// Called once per genuinely-presented toast (after the permission-storm and
    /// question-clobber dedup guards), so it fires for both completed and waiting.
    var onPlaySound: (() -> Void)?

    /// Token of the toast currently shown in the single shared panel. Only the
    /// timer that owns the visible toast may hide it, so an older session's
    /// timer can never dismiss a newer session's toast early.
    private struct Displayed { let token: UUID; let session: String; let findable: Bool }
    /// The toast currently in the shared panel, or nil when none is shown.
    private var displayed: Displayed?

    /// One pausable countdown per live toast, keyed by its token. Independent
    /// per session so an older session's toast still queues on its own schedule
    /// even after a newer one takes over the shared panel.
    private var timers: [UUID: ToastTimer] = [:]

    /// sessionUUID → last-applied pane background hex. In-memory only (cleared on
    /// app restart). Lets Stop backfill color sessions that predate the app and
    /// skip repeated coloring; a changed project hex re-applies. (R8)
    private var coloredSessions: [String: String] = [:]

    /// Sessions that have already had `/color` injected. Boolean, in-memory only
    /// (cleared on app restart): inject exactly once per session, then skip — even
    /// if the project color would have changed (unlike `coloredSessions`). A
    /// session is recorded only when injection actually fires. (R4)
    private var colorInjectedSessions: Set<String> = []

    /// `prompt_id`s already surfaced as a rich AskUserQuestion. The companion
    /// `permission_prompt` Notification carries the same id, so it can be
    /// recognised and dropped WITHOUT consulting the store — `reconcile` runs
    /// before `present` and GCs items whose session is not in the live set, which
    /// used to make the store-state guard miss and let the generic event clobber
    /// the rich question toast.
    ///
    /// Deliberately NOT keyed by session and NOT filtered in `reconcile` (unlike
    /// `coloredSessions` / `colorInjectedSessions`): filtering it against the live
    /// set would drop the memory for exactly the un-findable sessions this fixes,
    /// reintroducing the bug. Bounded FIFO instead — only a handful of prompts are
    /// ever in flight, and this must not grow for the life of the process.
    private var questionPromptIDs: [String] = []
    private static let maxRememberedQuestionPrompts = 32

    init(
        store: ReminderStore,
        toastDuration: TimeInterval = 8.0,
        toastPanel: ToastPanelProtocol?,
        probe: ItermSessionProbe = ItermSessionLookup(),
        usage: UsageService? = nil
    ) {
        self.store = store
        self.toastDuration = toastDuration
        self.toastPanel = toastPanel
        self.probe = probe
        self.usage = usage
    }

    private var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Probe iTerm2 off the main thread (the AppleScript query costs ~0.1 s), then
    /// present on main. A reminder whose session is not findable still toasts
    /// but never becomes a tab.
    func handle(_ p: NotifyPayload) {
        // Before any branching: session_start and resolve are payloads too, and
        // session_start is usually the very first one to arrive.
        onDidReceiveEvent?()
        if p.isSessionStart {
            // Pane-coloring trigger, not a reminder.
            usage?.probeHudCache()
            colorPaneIfNeeded(p)
            return
        }
        if p.isResolve {
            // AskUserQuestion answered (PostToolUse), or the session ended
            // (SessionEnd): clear its waiting tab.
            store.remove(sessionUUID: p.sessionUUID)
            // Claude Code actually exited (only `prompt_input_exit`, see
            // `isSessionExit`): hand the pane back to the shell at its profile
            // default. Gated on the coloring toggle so it is a genuine off switch —
            // with it off this app touches no pane background at all, not even to
            // undo one. Consequence, accepted: a pane colored *before* the toggle
            // was switched off keeps its color (and its stale `coloredSessions`
            // hex) until the pane itself closes and `reconcile` GCs the entry.
            if p.isSessionExit, isPaneColoringEnabled() {
                // Load-bearing, not hygiene: `colorPaneIfNeeded` returns early when
                // the stored hex equals the computed one, so leaving the entry
                // behind would keep a restarted Claude in this same pane at the
                // default background forever.
                //
                // BOTH memories must be cleared together: they are the two halves of
                // one visual contract (pane background + prompt bar must agree). Both
                // are keyed by iTerm2 session UUID, which outlives the Claude process
                // — a restart in this same still-open pane reuses it. Clearing only
                // the hex would re-color the pane while `injectColorIfNeeded` still
                // considers the session injected, leaving the prompt bar default.
                coloredSessions[p.sessionUUID] = nil
                colorInjectedSessions.remove(p.sessionUUID)
                onResetPaneBackground?(p.sessionUUID)
            }
            return
        }
        usage?.refreshIfStale()
        if !p.focusable {
            // Non-iTerm2: no pane to jump to, so never a tab. Announce with a
            // desktop notification when the toggle is on; stay silent otherwise.
            if isNonItermEnabled() {
                onNotify?(p.title, p.summary, Self.notificationBody(p.fullMessage))
            }
            return
        }
        // R8 backfill: color a pre-existing session's pane on Stop too (needs only
        // the session id, not the findable probe below).
        colorPaneIfNeeded(p)
        // Inject `/color` on Stop only (never SessionStart) and only for a
        // completed turn, once per session.
        injectColorIfNeeded(p)
        let probe = self.probe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // One off-main probe per reminder: the full live-session set doubles
            // as the findability answer (`contains`) and the reconcile input, so
            // there is no extra probe spawn. `live?.contains ?? canFind` short-
            // circuits — when `live` is known the second spawn is never made; a
            // stub whose `liveSessionIDs()` defaults to nil falls back to canFind
            // and skips reconcile, preserving existing test behavior.
            let live = probe.liveSessionIDs()
            let findable = live?.contains(p.sessionUUID) ?? probe.canFind(p.sessionUUID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let live { self.reconcile(live: live) }
                self.present(p, findable: findable)
            }
        }
    }

    /// Record a presented question's `prompt_id`, oldest-out once the bound is hit.
    private func rememberQuestionPrompt(_ id: String) {
        guard !questionPromptIDs.contains(id) else { return }
        questionPromptIDs.append(id)
        if questionPromptIDs.count > Self.maxRememberedQuestionPrompts {
            questionPromptIDs.removeFirst()
        }
    }

    /// GC in-memory session state against the live iTerm2 session set: a closed
    /// pane drops out of `live`, so its color hex, inject-once flag, and any
    /// dead tab are removed. Called only when the live set is known
    /// (`liveSessionIDs() != nil`), never on probe failure — a transient
    /// enumeration error must not wipe live sessions. Runs on the main actor before
    /// `present`, so the current event's session (if alive) is in `live` and
    /// survives; if it is already closed it is dropped and `present` builds no
    /// tab (findable == false). The dead-tab sweep also backstops a force-closed
    /// pane, where `SessionEnd` may never fire to clear the tab via `resolve`.
    private func reconcile(live: Set<String>) {
        coloredSessions = coloredSessions.filter { live.contains($0.key) }
        colorInjectedSessions = colorInjectedSessions.filter { live.contains($0) }
        for dead in store.items.map(\.sessionUUID) where !live.contains(dead) {
            store.remove(sessionUUID: dead)
        }
    }

    /// Color a session's pane when coloring is enabled, the session is focusable
    /// (has an iTerm2 pane), and the project hex differs from what was last
    /// applied to that session (or was never applied). Shared by the SessionStart
    /// trigger and the Stop backfill path; the hex-keyed dedup avoids repeated
    /// script spawns for an unchanged session. (R8)
    private func colorPaneIfNeeded(_ p: NotifyPayload) {
        guard isPaneColoringEnabled(), p.focusable else { return }
        let identity = ReminderIdentity(repoRoot: p.repoRoot, branch: p.branch, cwd: p.cwd)
        let hex = ReminderPalette.backgroundHex(
            at: store.assigner.colorIndex(for: identity.key),
            shade: PaneShade.level(branch: p.branch, isWorktree: p.isWorktree)
        )
        guard coloredSessions[p.sessionUUID] != hex else { return }
        coloredSessions[p.sessionUUID] = hex
        onSetPaneBackground?(p.sessionUUID, hex)
    }

    /// Inject `/color <name>` into a session's prompt bar on its FIRST genuine
    /// Stop, when coloring is enabled and the session is focusable. Gated on
    /// `p.isStop` — NOT on completed/waiting: a Stop whose reply merely ends in a
    /// question is still an ordinary, stashable composer (safe to inject), while
    /// a permission prompt / AskUserQuestion arrives as a *different* event
    /// (type-less Notification / `question`) that never sets `isStop`, so its
    /// live TUI is never typed into. Shares the `colorPanes` gate with
    /// `colorPaneIfNeeded` and resolves the SAME palette slot, so the prompt-bar
    /// color matches the pane background. Called from the Stop branch only; the
    /// SessionStart branch returns before reaching it. (R3, R4, R6)
    private func injectColorIfNeeded(_ p: NotifyPayload) {
        guard isPaneColoringEnabled(), p.focusable, p.isStop,
              !colorInjectedSessions.contains(p.sessionUUID) else { return }
        let identity = ReminderIdentity(repoRoot: p.repoRoot, branch: p.branch, cwd: p.cwd)
        let name = ReminderPalette.colorName(at: store.assigner.colorIndex(for: identity.key))
        colorInjectedSessions.insert(p.sessionUUID)
        onInjectColor?(p.sessionUUID, name)
    }

    /// Body text for a non-iTerm2 desktop notification: the reply past its first
    /// line (the subtitle already shows that), whitespace-flattened and capped.
    /// Empty when the reply is a single line.
    static func notificationBody(_ full: String, limit: Int = 200) -> String {
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        let rest = lines.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.count > limit ? String(rest.prefix(limit)) + "…" : rest
    }

    private func present(_ p: NotifyPayload, findable: Bool) {
        let session = p.sessionUUID
        // AskUserQuestion fires a rich `question` PreToolUse *and* a generic
        // `permission_prompt` Notification for the same session, sharing one
        // `prompt_id`. Match on that id: it survives `reconcile` having GC'd the
        // question item (which happens whenever the session is not in the iTerm2
        // live set, e.g. a closed pane whose Claude process is still alive), where
        // the store-state guard below misses and the generic event would clobber
        // the rich question toast. A genuine permission request carries a
        // *different* prompt_id and still gets through.
        if !p.isQuestion, p.sessionStatus == .waiting,
           let promptID = p.promptID, questionPromptIDs.contains(promptID) {
            return
        }
        // Fallback for payloads with no `prompt_id` (a hook script published
        // before that field): drop the generic waiting event while a question item
        // is still in the store. Kept so behavior is unchanged until the user's
        // next app launch republishes the scripts.
        if !p.isQuestion, p.sessionStatus == .waiting,
           let existing = store.items.first(where: { $0.sessionUUID == session }),
           existing.kind == .question {
            return
        }
        // R4: a session already showing a waiting state (a queued waiting tab or
        // the waiting toast currently on screen) must not re-toast on a follow-up
        // waiting event — e.g. a permission storm. Refresh the tab's content in
        // place and return; the existing toast/tab keeps its own schedule.
        if p.sessionStatus == .waiting,
           let existing = store.items.first(where: { $0.sessionUUID == session }),
           existing.status == .waiting,
           existing.phase == .queued || displayed?.session == session {
            store.refreshContent(
                sessionUUID: session,
                summary: p.summary,
                fullMessage: p.fullMessage,
                timestamp: p.timestamp,
                kind: p.isQuestion ? .question : .plain,
                questions: p.questions ?? []
            )
            return
        }
        // Remember the prompt only for a question that is actually being
        // presented, so the companion permission event can be matched later.
        if p.isQuestion, let promptID = p.promptID { rememberQuestionPrompt(promptID) }
        // A genuinely new toast is about to fly in (past both dedup guards):
        // play the reminder sound once. Covers completed and waiting alike; a
        // refreshed-in-place waiting event returned above, so no storm re-plays.
        if isSoundEnabled() { onPlaySound?() }
        let token = store.upsert(p)
        let timer = ToastTimer(duration: toastDuration) { [weak self] in
            self?.complete(token: token, session: session, findable: findable)
        }
        timers[token] = timer
        if let item = store.items.first(where: { $0.sessionUUID == session }) {
            // A toast is already on screen — demote it into a tab immediately so
            // only one toast shows at a time, then present the newcomer.
            if let prev = displayed {
                complete(token: prev.token, session: prev.session, findable: prev.findable)
            }
            toastPanel?.show(
                item: item,
                on: visibleFrame,
                showsMinimize: findable,
                onClick: { [weak self] in
                    // Not findable → clicking does nothing; the toast just expires.
                    guard findable else { return }
                    self?.displayed = nil
                    self?.onActivate?(item)
                },
                onHover: { [weak self] inside in
                    // Pause the visible toast's countdown while the pointer is
                    // over it (the user is reading); resume on exit.
                    guard let self, let shown = self.displayed?.token else { return }
                    if inside { self.timers[shown]?.pause() } else { self.timers[shown]?.resume() }
                },
                onMinimize: { [weak self] in
                    // The button is only shown for findable toasts, so minimize
                    // always becomes a tab. Reuses the timer's completion path.
                    self?.complete(token: token, session: session, findable: true)
                },
                onClose: { [weak self] in
                    // Close dismisses without a tab — drop the item outright,
                    // regardless of findability.
                    self?.complete(token: token, session: session, findable: false)
                },
                onAnswer: { [weak self] answer, count in
                    // Answered from the toast: tear down (cancel timer + fade +
                    // drop the item) then run the injected side effect. Gated on
                    // still being the displayed toast: a second click during the
                    // fade-out (or a click on the previous toast still fading
                    // behind a newcomer) would otherwise inject the answer twice.
                    guard self?.displayed?.token == token else { return }
                    self?.complete(token: token, session: session, findable: false)
                    self?.onAnswer?(item, answer, count)
                },
                onChat: { [weak self] in
                    guard self?.displayed?.token == token else { return }
                    self?.complete(token: token, session: session, findable: false)
                    self?.onChat?(item)
                },
                onJumpMaximized: { [weak self] in
                    // Title double-click: tear the toast down (no tab — we are
                    // jumping there) and hand off the maximized jump.
                    self?.complete(token: token, session: session, findable: false)
                    self?.onJumpMaximized?(item)
                },
                onQuickReply: { [weak self] reply in
                    // Same teardown-then-inject shape (and same double-fire guard)
                    // as answering: the reminder is handled once the prompt is sent.
                    guard self?.displayed?.token == token else { return }
                    self?.complete(token: token, session: session, findable: false)
                    self?.onQuickReply?(item, reply)
                }
            )
            displayed = Displayed(token: token, session: session, findable: findable)
        }
        timer.start()
    }

    /// The end-of-toast transition, shared by the countdown timer and the
    /// minimize button: queue the tab (or drop it if unfindable), cancel the
    /// timer, and hide the panel if this toast is the one on screen.
    private func complete(token: UUID, session: String, findable: Bool) {
        timers[token]?.cancel()
        timers[token] = nil
        // Demote into a tab only when findable AND the tab strip is enabled.
        // With the strip off the toast still ran its course; it just leaves no
        // persistent tab. An unfindable session never has a pane to jump to.
        let becomesTab = findable && isTabStripEnabled()
        if becomesTab {
            store.queueIfCurrent(sessionUUID: session, token: token)
        } else {
            // No jumpable pane (or strip disabled): drop it, don't leave a dead tab.
            store.removeIfCurrent(sessionUUID: session, token: token)
        }
        // Hide only if this timer's toast is still the one on screen; a newer
        // toast (any session) owns the panel and keeps its full time. Shrink
        // into the strip only when it actually became a tab (findable); a
        // dropped toast just fades so the animation never lies about a tab.
        if displayed?.token == token {
            toastPanel?.hide(intoTab: becomesTab)
            displayed = nil
        }
    }
}

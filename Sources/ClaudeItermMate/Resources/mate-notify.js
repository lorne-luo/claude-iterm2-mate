#!/usr/bin/env node
/**
 * Claude Code Stop hook for Claude iTerm2 Mate.
 *
 * Sends the notification payload to the companion app over a unix socket
 * (one message per connection: write JSON, then close). If the app is not
 * running — or the session is not inside iTerm2 — falls back to a plain
 * osascript desktop notification, matching desktop-notify.js behavior.
 *
 * Self-contained: no imports outside Node built-ins. Register in
 * ~/.claude/settings.json REPLACING desktop-notify.js (never run both):
 *
 *   "hooks": { "Stop": [ { "matcher": "", "hooks": [ { "type": "command",
 *     "command": "node /abs/path/to/claude-iterm2-mate/scripts/mate-notify.js" } ] } ] }
 */

"use strict";

const net = require("net");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const SOCKET_PATH =
  process.env.CLAUDE_MATE_SOCKET ||
  path.join(os.homedir(), "Library/Application Support/ClaudeItermMate/notify.sock");
const CONNECT_TIMEOUT_MS = 500;
const MAX_BODY_LENGTH = 100;
// Upper bound on stdin read, well above any realistic hook input. It must be
// comfortably larger than MAX_PAYLOAD_BYTES so a large-but-valid message is
// parsed intact (then trimmed for the wire) rather than truncated mid-JSON,
// which would fail JSON.parse and drop the notification with no fallback.
const MAX_STDIN = 8 * 1024 * 1024;
// Must match NotifyPayload.maxPayloadBytes in the app; the server drops any
// connection whose encoded payload exceeds this many UTF-8 bytes.
const MAX_PAYLOAD_BYTES = 1024 * 1024;

function extractSummary(message) {
  if (!message || typeof message !== "string") return "Done";
  const firstLine = message
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.length > 0);
  if (!firstLine) return "Done";
  return firstLine.length > MAX_BODY_LENGTH
    ? `${firstLine.slice(0, MAX_BODY_LENGTH)}...`
    : firstLine;
}

// Best-effort git context for the payload. Runs only on the socket path (when
// the app will actually use it). Short timeout; any failure (non-git dir,
// detached HEAD, git missing) leaves the field undefined and never throws or
// blocks the hook.
function gitInfo(cwd) {
  const run = (args) => {
    try {
      const r = spawnSync("git", ["-C", cwd, ...args], {
        timeout: 500,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      if (r.status === 0 && typeof r.stdout === "string") {
        const out = r.stdout.trim();
        return out || undefined;
      }
    } catch {}
    return undefined;
  };
  const branch = run(["symbolic-ref", "--short", "HEAD"]);
  const commonDir = run(["rev-parse", "--git-common-dir"]);
  if (!commonDir) return { branch }; // not a git repo (branch is undefined too)
  // Shared project root = parent of the common .git dir. All linked worktrees
  // of one repo resolve to the same value, so they share a base color and
  // project label; the branch glyph tells them apart.
  const repo_root = path.dirname(path.resolve(cwd, commonDir));
  const toplevel = run(["rev-parse", "--show-toplevel"]);
  const is_worktree = toplevel ? path.resolve(toplevel) !== repo_root : false;
  return { repo_root, branch, is_worktree };
}

// AppleScript strings do not support backslash escapes: strip backslashes,
// replace double quotes with curly quotes (same rules as desktop-notify.js).
function notifyMacOS(title, body) {
  const safeBody = body.replace(/\\/g, "").replace(/"/g, "“");
  const safeTitle = title.replace(/\\/g, "").replace(/"/g, "“");
  spawnSync("osascript", ["-e", `display notification "${safeBody}" with title "${safeTitle}"`], {
    stdio: "ignore",
    timeout: 5000,
  });
}

// A Stop is "waiting" (needs a reply) when the assistant's last message ends
// either (a) in a question mark, or (b) on a sequential numbered-choice menu
// ("1. … 2. …"); "completed" otherwise. Conservative on purpose — trailing "?"
// only, and a menu only when it is the tail of the message and its numbers run
// 1..k — so we bias toward missing a question over falsely flagging a finished
// session (see R3).
function classifyStopStatus(message) {
  if (typeof message !== "string") return "completed";
  const trimmed = message.replace(/\s+$/, "");
  if (trimmed.length === 0) return "completed";
  const last = trimmed.slice(-1);
  if (last === "?" || last === "？") return "waiting";
  return endsWithNumberedMenu(trimmed) ? "waiting" : "completed";
}

// True when the message ends on a plain-text numbered-choice menu: the final
// non-empty line is a numbered item ("1." / "1)"), and every numbered item in
// the message runs sequentially 1..k with k >= 2. Requiring the WHOLE set to be
// 1..k (not just a trailing run) keeps it conservative — a message that merely
// contains a numbered list mid-body and then continues in prose ends on a
// non-item line and is rejected.
function endsWithNumberedMenu(trimmed) {
  const itemRe = /^\s*(\d+)[.)]\s+\S/;
  const lines = trimmed.split("\n");
  if (!itemRe.test(lines[lines.length - 1])) return false; // tail gate
  const nums = [];
  for (const line of lines) {
    const m = line.match(itemRe);
    if (m) nums.push(parseInt(m[1], 10));
  }
  if (nums.length < 2) return false;
  return nums.every((n, i) => n === i + 1);
}

// A Notification event maps to "waiting" only for a permission prompt. Every
// other notification_type (idle_prompt, auth_success, elicitation_*, agent_*)
// is ignored: re-flagging an already-finished session would be a false "waiting".
function shouldSendNotification(input) {
  return !!input && input.notification_type === "permission_prompt";
}

// Shared session identity: iTerm2 sessions are focusable (click-to-jump);
// others fall back to Claude Code's session_id, then cwd, for dedup only.
function deriveSession(input, cwd) {
  const itermSession = process.env.ITERM_SESSION_ID;
  const focusable = !!itermSession;
  const sessionUUID = focusable
    ? itermSession.split(":").pop()
    : (typeof input.session_id === "string" && input.session_id ? input.session_id : cwd);
  return { focusable, sessionUUID };
}

// Build the wire fields shared by both modes (session, cwd, git, timestamp).
function baseFields(input, cwd, focusable, sessionUUID) {
  const git = gitInfo(cwd);
  const fields = {
    session_uuid: sessionUUID,
    cwd,
    timestamp: Date.now(),
  };
  if (!focusable) fields.focusable = false;
  if (git.repo_root) fields.repo_root = git.repo_root;
  if (git.branch) fields.branch = git.branch;
  if (git.is_worktree) fields.is_worktree = true;
  return fields;
}

// Send one payload to the app over the socket (write then close = frame
// boundary). `onFail` runs on connect timeout / error — the Stop path passes a
// desktop-notification fallback; the Notification path passes none (a missed
// permission ping must stay silent, never spawn an OS notification).
function sendPayload(fields, onFail) {
  // Keep the ENCODED payload under the server's byte limit. Measuring the
  // stringified result accounts for JSON escaping and multi-byte UTF-8, which
  // a plain character-count cap (MAX_STDIN) does not. Trim full_message until
  // it fits, so an oversized reply degrades to a shorter one instead of being
  // silently dropped by the server with no fallback.
  let payload = JSON.stringify(fields);
  while (
    Buffer.byteLength(payload, "utf8") > MAX_PAYLOAD_BYTES &&
    typeof fields.full_message === "string" &&
    fields.full_message.length > 0
  ) {
    const cut = Math.max(1024, Math.floor(fields.full_message.length * 0.1));
    fields.full_message = fields.full_message.slice(0, fields.full_message.length - cut);
    payload = JSON.stringify(fields);
  }

  let settled = false;
  const sock = net.createConnection(SOCKET_PATH);
  const fallback = () => {
    if (settled) return;
    settled = true;
    sock.destroy();
    if (onFail) onFail();
  };
  const timer = setTimeout(fallback, CONNECT_TIMEOUT_MS);
  sock.on("connect", () => {
    clearTimeout(timer);
    sock.end(payload); // write then close: connection close is the frame boundary
  });
  sock.on("close", () => {
    settled = true;
  });
  sock.on("error", () => {
    clearTimeout(timer);
    fallback();
  });
}

function main(raw) {
  let input = {};
  try {
    input = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return;
  }

  const message = input.last_assistant_message;
  const trimmed = typeof message === "string" ? message.trim() : "";
  if (trimmed === "<summary>" || trimmed === "<observation>") return;

  const cwd = typeof input.cwd === "string" && input.cwd ? input.cwd : process.cwd();
  if (path.basename(cwd) === "observer-sessions") return;

  const title = path.basename(cwd);
  const summary = extractSummary(message);

  const isSdk = (process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk");
  if (process.platform !== "darwin") return;
  // SDK / headless runs have no interactive terminal to jump to — stay silent
  // rather than firing an osascript desktop notification.
  if (isSdk) return;

  // Non-iTerm2 sessions (VS Code terminal, tmux, Terminal.app, …) still go to
  // the app, marked non-focusable: the app shows a tab you can dismiss but
  // cannot click-to-jump (there is no iTerm2 pane), and it honors the app's
  // "show non-iTerm2 sessions" toggle. With no iTerm2 session id, dedup falls
  // back to Claude Code's own session_id, then cwd. If the app is not running
  // the socket send fails and we fall back to a desktop notification.
  const { focusable, sessionUUID } = deriveSession(input, cwd);
  const fields = baseFields(input, cwd, focusable, sessionUUID);
  fields.title = title;
  fields.summary = summary;
  fields.full_message = typeof message === "string" ? message : "";
  fields.status = classifyStopStatus(message);
  // Mark the genuine Stop event so the app can tell it apart from a
  // permission-prompt Notification (both are otherwise type-less and can be
  // "waiting"). Only the real Stop leaves the pane at an ordinary, stashable
  // composer, so only it may inject `/color`.
  fields.type = "stop";

  sendPayload(fields, () => notifyMacOS(title, summary));
}

// --event notification: a permission prompt fired mid-turn. Surface it as a
// "waiting" tab. No desktop-notification fallback (see sendPayload).
function handleNotification(raw) {
  let input = {};
  try {
    input = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return;
  }
  if (!shouldSendNotification(input)) return;
  if (process.platform !== "darwin") return;
  if ((process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk")) return;

  const cwd = typeof input.cwd === "string" && input.cwd ? input.cwd : process.cwd();
  if (path.basename(cwd) === "observer-sessions") return;

  // The Notification payload carries only `message` (verified: no tool_name /
  // tool_input / details). Use it directly as summary/body; a permission prompt
  // is just "Claude needs your permission".
  const messageText = typeof input.message === "string" ? input.message : "";

  const { focusable, sessionUUID } = deriveSession(input, cwd);
  // Notification mode surfaces only iTerm2 (focusable) sessions. A non-iTerm2
  // permission prompt has no pane to jump to, and forwarding it would let the
  // app's non-focusable path fire an osascript desktop notification — which the
  // no-desktop-fallback contract for permission pings forbids. So drop it here.
  if (!focusable) return;
  const fields = baseFields(input, cwd, focusable, sessionUUID);
  fields.title = path.basename(cwd);
  fields.summary = extractSummary(messageText || "Waiting for input");
  fields.full_message = messageText;
  fields.status = "waiting";

  sendPayload(fields, null);
}

// Build the wire fields for an AskUserQuestion PreToolUse event. Pure so it is
// unit-testable. Reads `tool_input.questions` (verified shape: each question has
// question/header/options[label,description]/multiSelect). summary = first
// question text; full_message = questions + their options as a human-readable
// fallback; `questions` carries the structured data the app renders as buttons.
function buildQuestionFields(input, cwd, focusable, sessionUUID) {
  const questions = Array.isArray(input.tool_input && input.tool_input.questions)
    ? input.tool_input.questions
    : [];
  const norm = questions.map((q) => ({
    question: typeof q.question === "string" ? q.question : "",
    header: typeof q.header === "string" ? q.header : "",
    multiSelect: !!q.multiSelect,
    options: Array.isArray(q.options)
      ? q.options.map((o) => ({
          label: typeof o.label === "string" ? o.label : "",
          description: typeof o.description === "string" ? o.description : "",
        }))
      : [],
  }));
  const firstQ = norm.find((q) => q.question) || norm[0];
  const summary = extractSummary(firstQ ? firstQ.question : "Waiting for input");
  const full_message = norm
    .map((q) => {
      const lines = [q.question];
      q.options.forEach((o, i) => {
        lines.push(o.description ? `${i + 1}. ${o.label} — ${o.description}` : `${i + 1}. ${o.label}`);
      });
      return lines.join("\n");
    })
    .join("\n\n");

  const fields = baseFields(input, cwd, focusable, sessionUUID);
  fields.title = path.basename(cwd);
  fields.type = "question";
  fields.summary = summary;
  fields.full_message = full_message;
  fields.questions = norm;
  fields.status = "waiting";
  return fields;
}

// --event ask: AskUserQuestion fired (PreToolUse). Surface a rich "waiting" tab
// with the question + options. Only iTerm2 (focusable) sessions; no desktop
// fallback (same contract as notification mode).
function handleAsk(raw) {
  let input = {};
  try {
    input = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return;
  }
  if (process.platform !== "darwin") return;
  if ((process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk")) return;
  const cwd = typeof input.cwd === "string" && input.cwd ? input.cwd : process.cwd();
  if (path.basename(cwd) === "observer-sessions") return;
  const { focusable, sessionUUID } = deriveSession(input, cwd);
  if (!focusable) return;
  sendPayload(buildQuestionFields(input, cwd, focusable, sessionUUID), null);
}

// --event ask-done: AskUserQuestion answered (PostToolUse). Tell the app to
// remove the waiting tab for this session (event-driven clear).
function handleAskDone(raw) {
  let input = {};
  try {
    input = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return;
  }
  if (process.platform !== "darwin") return;
  if ((process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk")) return;
  const cwd = typeof input.cwd === "string" && input.cwd ? input.cwd : process.cwd();
  const { focusable, sessionUUID } = deriveSession(input, cwd);
  if (!focusable) return;
  sendPayload({ type: "resolve", session_uuid: sessionUUID, cwd, timestamp: Date.now() }, null);
}

// --event session-end: the Claude Code session ended (SessionEnd, any reason).
// Clear its reminder tab. Identical to ask-done — same `resolve` payload and
// same guards (darwin, not SDK, focusable). Deliberately does NOT touch the
// app's color/inject-once memory: the iTerm2 pane may still be alive and reused.
function handleSessionEnd(raw) {
  handleAskDone(raw);
}

// Dispatch by CLI mode from `--event <mode>`: `notification` | `ask` |
// `ask-done` | `session-end`, otherwise the default Stop path (`stop`). Only
// when run directly — when required as a module (tests) just export the pure
// helpers.
function eventMode(argv) {
  const i = argv.indexOf("--event");
  const v = i >= 0 ? argv[i + 1] : undefined;
  return v === "notification" || v === "ask" || v === "ask-done" || v === "session-end"
    ? v
    : "stop";
}

const HANDLERS = {
  notification: handleNotification,
  ask: handleAsk,
  "ask-done": handleAskDone,
  "session-end": handleSessionEnd,
  stop: main,
};

if (require.main === module) {
  const handler = HANDLERS[eventMode(process.argv.slice(2))] || main;
  let data = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    if (data.length < MAX_STDIN) data += chunk.substring(0, MAX_STDIN - data.length);
  });
  process.stdin.on("end", () => handler(data));
} else {
  module.exports = {
    classifyStopStatus,
    shouldSendNotification,
    eventMode,
    buildQuestionFields,
    extractSummary,
  };
}

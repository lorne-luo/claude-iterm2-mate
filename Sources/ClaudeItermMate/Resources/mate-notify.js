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

  const title = `[CC] ${path.basename(cwd)}`;
  const summary = extractSummary(message);

  const itermSession = process.env.ITERM_SESSION_ID;
  const isSdk = (process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk");
  if (process.platform !== "darwin") return;
  if (!itermSession || isSdk) {
    notifyMacOS(title, summary);
    return;
  }

  const git = gitInfo(cwd);
  const fields = {
    session_uuid: itermSession.split(":").pop(),
    cwd,
    title,
    summary,
    full_message: typeof message === "string" ? message : "",
    timestamp: Date.now(),
  };
  if (git.repo_root) fields.repo_root = git.repo_root;
  if (git.branch) fields.branch = git.branch;
  if (git.is_worktree) fields.is_worktree = true;
  // Keep the ENCODED payload under the server's byte limit. Measuring the
  // stringified result accounts for JSON escaping and multi-byte UTF-8, which
  // a plain character-count cap (MAX_STDIN) does not. Trim full_message until
  // it fits, so an oversized reply degrades to a shorter one instead of being
  // silently dropped by the server with no fallback.
  let payload = JSON.stringify(fields);
  while (Buffer.byteLength(payload, "utf8") > MAX_PAYLOAD_BYTES && fields.full_message.length > 0) {
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
    notifyMacOS(title, summary);
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

let data = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  if (data.length < MAX_STDIN) data += chunk.substring(0, MAX_STDIN - data.length);
});
process.stdin.on("end", () => main(data));

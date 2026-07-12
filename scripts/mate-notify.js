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
const MAX_STDIN = 1024 * 1024;

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

  const payload = JSON.stringify({
    session_uuid: itermSession.split(":").pop(),
    cwd,
    title,
    summary,
    full_message: typeof message === "string" ? message : "",
    timestamp: Date.now(),
  });

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

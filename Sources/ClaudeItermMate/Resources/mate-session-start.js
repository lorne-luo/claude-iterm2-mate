#!/usr/bin/env node
/**
 * Claude Code SessionStart hook for Claude iTerm2 Mate.
 *
 * Announces a starting session to the companion app over the unix socket so
 * the app can assign the project's color and inject `/color <name>` into the
 * session (keeping the Claude Code prompt bar in sync with the app's tabs).
 *
 * Unlike the Stop hook there is NO desktop-notification fallback: if the app
 * is not running, the session is not in iTerm2, or anything fails, this
 * script exits silently — a missing color injection must never bother the
 * user or block the session.
 *
 * Self-contained: no imports outside Node built-ins. Installed by the app's
 * hook installer as a SessionStart hook in ~/.claude/settings.json.
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
const MAX_STDIN = 1024 * 1024;

// Same best-effort git context as mate-notify.js (see there for rationale).
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
  if (!commonDir) return { branch };
  const repo_root = path.dirname(path.resolve(cwd, commonDir));
  const toplevel = run(["rev-parse", "--show-toplevel"]);
  const is_worktree = toplevel ? path.resolve(toplevel) !== repo_root : false;
  return { repo_root, branch, is_worktree };
}

function main(raw) {
  let input = {};
  try {
    input = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return;
  }

  // Injection is only safe/useful right as a fresh prompt appears. Compaction
  // happens mid-conversation (and the color survives it), so skip it.
  const source = typeof input.source === "string" ? input.source : "";
  if (source === "compact") return;

  const itermSession = process.env.ITERM_SESSION_ID;
  const isSdk = (process.env.CLAUDE_CODE_ENTRYPOINT || "").startsWith("sdk");
  if (process.platform !== "darwin" || !itermSession || isSdk) return;

  const cwd = typeof input.cwd === "string" && input.cwd ? input.cwd : process.cwd();
  const git = gitInfo(cwd);
  const fields = {
    type: "session_start",
    source,
    session_uuid: itermSession.split(":").pop(),
    cwd,
    title: "",
    summary: "",
    full_message: "",
    timestamp: Date.now(),
  };
  if (git.repo_root) fields.repo_root = git.repo_root;
  if (git.branch) fields.branch = git.branch;
  if (git.is_worktree) fields.is_worktree = true;

  const payload = JSON.stringify(fields);
  const sock = net.createConnection(SOCKET_PATH);
  const timer = setTimeout(() => sock.destroy(), CONNECT_TIMEOUT_MS);
  sock.on("connect", () => {
    clearTimeout(timer);
    sock.end(payload); // write then close: connection close is the frame boundary
  });
  sock.on("error", () => {
    clearTimeout(timer);
    sock.destroy();
  });
}

let data = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  if (data.length < MAX_STDIN) data += chunk.substring(0, MAX_STDIN - data.length);
});
process.stdin.on("end", () => main(data));

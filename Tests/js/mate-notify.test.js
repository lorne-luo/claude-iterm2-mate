"use strict";
// Pure-logic tests for the dual-mode Stop / Notification hook script.
// Run: node --test 'Tests/js/**/*.test.js'
// (The Swift suite covers the app side; these cover the JS classifiers whose
// edge cases — trailing whitespace, full-width "？", notification_type — drive
// the waiting-vs-completed decision on the wire.)

const test = require("node:test");
const assert = require("node:assert");
const { classifyStopStatus, shouldSendNotification, isNotificationMode } =
  require("../../Sources/ClaudeItermMate/Resources/mate-notify.js");

test("classifyStopStatus: trailing question mark -> waiting", () => {
  assert.strictEqual(classifyStopStatus("Should I proceed?"), "waiting");
  assert.strictEqual(classifyStopStatus("要继续吗？"), "waiting");
  assert.strictEqual(classifyStopStatus("Continue?  \n\n"), "waiting");
});

test("classifyStopStatus: non-question -> completed", () => {
  assert.strictEqual(classifyStopStatus("All done."), "completed");
  assert.strictEqual(classifyStopStatus("Fixed it!"), "completed");
  assert.strictEqual(classifyStopStatus("Done"), "completed");
  assert.strictEqual(classifyStopStatus(""), "completed");
});

test("classifyStopStatus: conservative — a '?' not at the very end is completed", () => {
  // Markdown bold ends in "*", so a false positive is avoided (accepted miss).
  assert.strictEqual(classifyStopStatus("**Continue?**"), "completed");
  assert.strictEqual(classifyStopStatus("Is it? Let me check."), "completed");
});

test("classifyStopStatus: trailing numbered-choice menu -> waiting", () => {
  const menu = [
    "How do you want to proceed?",
    "",
    "1. Ship it as-is",
    "2. Add more tests first",
    "3. Refactor the coordinator",
    "4. Split into two PRs",
    "5. Abort",
  ].join("\n");
  assert.strictEqual(classifyStopStatus(menu), "waiting");
  // ")" delimiter, minimum length 2
  assert.strictEqual(classifyStopStatus("Pick one:\n1) foo\n2) bar"), "waiting");
});

test("classifyStopStatus: numbered list mid-body then prose -> completed", () => {
  const midBody = [
    "I did three things:",
    "1. fixed the bug",
    "2. added a test",
    "3. updated docs",
    "",
    "Everything passes now.",
  ].join("\n");
  assert.strictEqual(classifyStopStatus(midBody), "completed");
});

test("classifyStopStatus: single numbered item / non-sequential -> completed", () => {
  assert.strictEqual(classifyStopStatus("1. just one thing"), "completed");
  assert.strictEqual(classifyStopStatus("Options:\n2. two\n3. three"), "completed"); // not starting at 1
  assert.strictEqual(classifyStopStatus("Options:\n1. one\n3. three"), "completed"); // gap
});

test("classifyStopStatus: non-string -> completed", () => {
  assert.strictEqual(classifyStopStatus(null), "completed");
  assert.strictEqual(classifyStopStatus(undefined), "completed");
});

test("shouldSendNotification: only permission_prompt sends", () => {
  assert.strictEqual(shouldSendNotification({ notification_type: "permission_prompt" }), true);
  assert.strictEqual(shouldSendNotification({ notification_type: "idle_prompt" }), false);
  assert.strictEqual(shouldSendNotification({ notification_type: "auth_success" }), false);
  assert.strictEqual(shouldSendNotification({}), false);
  assert.strictEqual(shouldSendNotification(null), false);
});

test("isNotificationMode: detects --event notification", () => {
  assert.strictEqual(isNotificationMode(["--event", "notification"]), true);
  assert.strictEqual(isNotificationMode(["--event", "other"]), false);
  assert.strictEqual(isNotificationMode([]), false);
});

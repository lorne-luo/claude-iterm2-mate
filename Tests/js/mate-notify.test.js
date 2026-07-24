"use strict";
// Pure-logic tests for the dual-mode Stop / Notification hook script.
// Run: node --test 'Tests/js/**/*.test.js'
// (The Swift suite covers the app side; these cover the JS classifiers whose
// edge cases — trailing whitespace, full-width "？", notification_type — drive
// the waiting-vs-completed decision on the wire.)

const test = require("node:test");
const assert = require("node:assert");
const { classifyStopStatus, shouldSendNotification, eventMode, buildQuestionFields } =
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

test("eventMode: maps --event <mode>, defaults to stop", () => {
  assert.strictEqual(eventMode(["--event", "notification"]), "notification");
  assert.strictEqual(eventMode(["--event", "ask"]), "ask");
  assert.strictEqual(eventMode(["--event", "ask-done"]), "ask-done");
  assert.strictEqual(eventMode(["--event", "session-end"]), "session-end");
  assert.strictEqual(eventMode(["--event", "other"]), "stop");
  assert.strictEqual(eventMode([]), "stop");
});

test("buildQuestionFields: derives summary/full_message/questions from tool_input", () => {
  const input = {
    tool_input: {
      questions: [
        {
          question: "你最喜欢哪种颜色?",
          header: "颜色",
          multiSelect: false,
          options: [
            { label: "红色", description: "热情" },
            { label: "蓝色", description: "冷静" },
          ],
        },
      ],
    },
  };
  const f = buildQuestionFields(input, "/x/proj", true, "S1");
  assert.strictEqual(f.type, "question");
  assert.strictEqual(f.status, "waiting");
  assert.strictEqual(f.summary, "你最喜欢哪种颜色?");
  assert.strictEqual(f.title, "proj");
  assert.strictEqual(f.session_uuid, "S1");
  assert.strictEqual(f.questions.length, 1);
  assert.strictEqual(f.questions[0].options.length, 2);
  assert.strictEqual(f.questions[0].options[0].label, "红色");
  assert.ok(f.full_message.includes("1. 红色 — 热情"));
  assert.ok(f.full_message.includes("2. 蓝色 — 冷静"));
});

test("buildQuestionFields: tolerates missing/empty questions", () => {
  const f = buildQuestionFields({}, "/x/proj", true, "S1");
  assert.strictEqual(f.type, "question");
  assert.deepStrictEqual(f.questions, []);
  assert.strictEqual(f.summary, "Waiting for input");
});

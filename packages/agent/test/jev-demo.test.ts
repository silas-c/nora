import assert from "node:assert/strict";
import test from "node:test";
import type { ComputerState } from "../../shared/src/types.js";
import { isSafeMockCoursesNavigation, runJevMockDemo } from "../src/jev-demo.js";
import type { JevDecision, NextActionChooser } from "../src/jev.js";

class ScriptedChooser implements NextActionChooser {
  private index = 0;
  constructor(private readonly decisions: JevDecision[]) {}
  async choose(): Promise<JevDecision> {
    const decision = this.decisions[Math.min(this.index++, this.decisions.length - 1)];
    if (!decision) throw new Error("Missing synthetic decision.");
    return structuredClone(decision);
  }
}

const noWait = async () => {};

test("interactive mock demo executes one bounded Courses action and records history", async () => {
  const output: object[] = [];
  const demo = await runJevMockDemo(
    "Open Courses",
    new ScriptedChooser([
      { type: "action", action: { type: "click", target: "mock-1-2" }, confidence: 0.99 },
      { type: "done", confidence: 0.99 },
    ]),
    new AbortController().signal,
    value => output.push(value),
    { wait: noWait },
  );
  assert.equal(demo.result.success, true);
  assert.equal(demo.history.length, 1);
  assert.deepEqual(demo.history[0]?.action, { type: "click", target: "mock-1-2" });
  assert.ok(output.some(value => JSON.stringify(value).includes('"kind":"jev_decision"')));
  assert.ok(output.every(value => !JSON.stringify(value).includes('"native":true')));
});

test("interactive mock demo records no action for low confidence or cancellation", async () => {
  const low = await runJevMockDemo(
    "Open Courses",
    new ScriptedChooser([{ type: "ask_user", confidence: 0.4, reason: "low_confidence" }]),
    new AbortController().signal,
    () => {},
    { wait: noWait },
  );
  assert.equal(low.result.success, false);
  assert.deepEqual(low.history, []);

  const cancelled = new AbortController();
  cancelled.abort();
  const stopped = await runJevMockDemo(
    "Open Courses",
    new ScriptedChooser([{ type: "done", confidence: 1 }]),
    cancelled.signal,
    () => {},
    { wait: noWait },
  );
  assert.deepEqual(stopped.result, { success: false, error: "The Jev task was cancelled." });
  assert.deepEqual(stopped.history, []);
});

test("only exact mock Courses navigation is eligible for safe execution", () => {
  const base: ComputerState = {
    activeApp: "Microsoft Edge", activeWindow: "Dashboard", accessibilityTrusted: true, truncated: false,
    elements: [{ id: "target", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] }],
  };
  assert.equal(isSafeMockCoursesNavigation(
    { type: "click", target: "target" }, { goal: "Open Courses", state: base, confidence: 1 },
  ), true);
  assert.equal(isSafeMockCoursesNavigation(
    { type: "click", target: "target" },
    { goal: "Delete account", state: { ...base, elements: [{ ...base.elements[0]!, label: "Delete Account" }] }, confidence: 1 },
  ), false);
  assert.equal(isSafeMockCoursesNavigation(
    { type: "click", target: "target" }, { goal: "Open Courses", state: { ...base, activeApp: "Finder" }, confidence: 1 },
  ), false);
});

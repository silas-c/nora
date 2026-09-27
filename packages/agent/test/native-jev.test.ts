import assert from "node:assert/strict";
import test from "node:test";
import type { ActionResult, ComputerAction, ComputerController, ComputerState } from "../../shared/src/types.js";
import type { JevDecision, NextActionChooser } from "../src/jev.js";
import { isAllowedNativeJevURL, runNativeJev } from "../src/native-jev.js";

const snapshot = (
  generation: string,
  activeWindow: string,
  elements: ComputerState["elements"],
  activeApp = "Microsoft Edge",
): ComputerState => ({
  snapshotGeneration: generation,
  activeApp,
  activeWindow,
  accessibilityTrusted: true,
  truncated: false,
  elements,
});

class ScriptedChooser implements NextActionChooser {
  private index = 0;
  constructor(private readonly decisions: JevDecision[]) {}
  async choose(): Promise<JevDecision> {
    const decision = this.decisions[Math.min(this.index++, this.decisions.length - 1)];
    if (!decision) throw new Error("Missing native Jev test decision.");
    return structuredClone(decision);
  }
}

class NativeFixture implements ComputerController {
  readonly actions: ComputerAction[] = [];
  validated = 0;
  private stateIndex = 0;
  constructor(private readonly states: ComputerState[]) {}
  async getState(): Promise<ComputerState> { return structuredClone(this.states[Math.min(this.stateIndex, this.states.length - 1)]!); }
  async execute(action: ComputerAction): Promise<ActionResult> {
    this.actions.push(structuredClone(action));
    if (action.type === "click") this.stateIndex++;
    return { success: true };
  }
  async executeValidated(action: ComputerAction, expected: ComputerState): Promise<ActionResult> {
    assert.equal(action.type, "click");
    if (action.type !== "click") return { success: false, error: "Expected a click." };
    assert.equal(action.snapshotGeneration, expected.snapshotGeneration);
    this.validated++;
    this.actions.push(structuredClone(action));
    this.stateIndex++;
    return { success: true };
  }
}

const noWait = async () => {};
const options = { waitAfterOpen: noWait, waitBetweenObservations: noWait, write: () => {} };

test("native Jev route opens only allowed scope, clicks Courses once, and verifies fresh state", async () => {
  const computer = new NativeFixture([
    snapshot("g1", "Dashboard - Canvas", [
      { id: "courses", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] },
    ]),
    snapshot("g2", "Courses - Canvas", []),
  ]);
  const result = await runNativeJev("Open Courses", computer, new ScriptedChooser([
    { type: "action", action: { type: "click", target: "courses", snapshotGeneration: "g1" }, confidence: 0.99 },
    { type: "done", confidence: 0.99 },
  ]), new AbortController().signal, options);
  assert.equal(result.result.success, true);
  assert.deepEqual(computer.actions.map(action => action.type), ["open_url", "click"]);
  assert.equal(result.history.length, 2);
  assert.equal(computer.validated, 0);
});

test("ambiguous navigation requires confirmation and resumes through atomic validation", async () => {
  const computer = new NativeFixture([
    snapshot("g1", "Dashboard - Canvas", [
      { id: "dashboard", role: "AXLink", label: "Dashboard", enabled: true, actions: ["AXPress"] },
    ]),
    snapshot("g2", "Dashboard - Canvas", []),
  ]);
  let confirmations = 0;
  const result = await runNativeJev("Open Courses", computer, new ScriptedChooser([
    { type: "action", action: { type: "click", target: "dashboard", snapshotGeneration: "g1" }, confidence: 0.95 },
    { type: "done", confidence: 0.95 },
  ]), new AbortController().signal, {
    ...options,
    confirm: async () => { confirmations++; return true; },
  });
  assert.equal(result.result.success, true);
  assert.equal(confirmations, 1);
  assert.equal(computer.validated, 1);
  assert.deepEqual(computer.actions.map(action => action.type), ["open_url", "click"]);
});

test("prohibited controls, changed apps, unsupported goals, URLs, and cancellation execute no model action", async () => {
  const prohibited = new NativeFixture([snapshot("g1", "Canvas", [
    { id: "submit", role: "AXButton", label: "Submit assignment", enabled: true, actions: ["AXPress"] },
  ])]);
  const stopped = await runNativeJev("Open Courses", prohibited, new ScriptedChooser([
    { type: "action", action: { type: "click", target: "submit", snapshotGeneration: "g1" }, confidence: 1 },
  ]), new AbortController().signal, { ...options, confirm: async () => true });
  assert.equal(stopped.result.success, false);
  assert.deepEqual(prohibited.actions.map(action => action.type), ["open_url"]);

  const changed = new NativeFixture([snapshot("g1", "Terminal", [], "Terminal")]);
  assert.equal((await runNativeJev("Open Courses", changed, new ScriptedChooser([
    { type: "done", confidence: 1 },
  ]), new AbortController().signal, options)).result.success, false);
  assert.deepEqual(changed.actions.map(action => action.type), ["open_url"]);

  const unused = new NativeFixture([]);
  assert.equal((await runNativeJev("Delete files", unused, new ScriptedChooser([]), new AbortController().signal, options)).result.success, false);
  assert.equal((await runNativeJev("Open Courses", unused, new ScriptedChooser([]), new AbortController().signal, {
    ...options, url: "https://example.com",
  })).result.success, false);
  assert.deepEqual(unused.actions, []);

  const cancelled = new AbortController(); cancelled.abort();
  assert.equal((await runNativeJev("Open Courses", unused, new ScriptedChooser([]), cancelled.signal, options)).result.success, false);
  assert.deepEqual(unused.actions, []);
});

test("native Jev URL allowlist accepts Temple Canvas and loopback only", () => {
  assert.equal(isAllowedNativeJevURL("https://canvas.temple.edu"), true);
  assert.equal(isAllowedNativeJevURL("http://127.0.0.1:8080/test"), true);
  assert.equal(isAllowedNativeJevURL("http://localhost:3000"), true);
  assert.equal(isAllowedNativeJevURL("https://example.com"), false);
  assert.equal(isAllowedNativeJevURL("file:///tmp/page.html"), false);
  assert.equal(isAllowedNativeJevURL("https://canvas.temple.edu.evil.example"), false);
});

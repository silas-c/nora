import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createAgent } from "../src/agent.js";
import type { ActionResult, AgentEvent, ComputerAction, ComputerController, ComputerState, UserInput } from "../../shared/src/types.js";

const fixture = (name: string): ComputerState => JSON.parse(readFileSync(`packages/agent/test/fixtures/canvas-${name}.json`, "utf8"));
const dashboard = () => fixture("dashboard");
const courses = () => fixture("courses");
const login = () => fixture("login");
class Scenario implements ComputerController {
  actions: ComputerAction[] = [];
  reads = 0;
  constructor(readonly states: (ComputerState | Error)[], readonly clickResult: ActionResult = { success: true }) {}
  async getState() {
    const next = this.states[Math.min(this.reads++, this.states.length - 1)];
    if (next instanceof Error) throw next;
    return structuredClone(next);
  }
  async execute(action: ComputerAction) {
    this.actions.push(action);
    return action.type === "click" ? this.clickResult : { success: true as const };
  }
}
const input: UserInput = { source: "aac", intent: "OPEN_COURSES" };
const fast = { wait: async () => {} };

test("text and AAC navigate using one snapshot ID and verify a new Courses control", async () => {
  for (const request of [input, { source: "text" as const, text: "Open Canvas and go to Courses" }]) {
    const computer = new Scenario([dashboard(), courses()]);
    const agent = createAgent(computer, fast);
    const events: AgentEvent[] = [];
    agent.subscribe(event => events.push(event));
    assert.equal((await agent.submit(request)).success, true);
    assert.deepEqual(computer.actions, [{ type: "open_url", url: "https://canvas.temple.edu", browser: "Microsoft Edge" }, { type: "click", target: "e2" }]);
    assert.equal(computer.reads, 2);
    assert.equal(events.at(-1)?.type, "done");
  }
});

test("loading uses ten observations at most and only one click", async () => {
  const computer = new Scenario([login(), dashboard(), dashboard(), courses()]);
  const waits: number[] = [];
  const agent = createAgent(computer, { wait: async ms => { waits.push(ms); } });
  assert.equal((await agent.submit(input)).success, true);
  assert.deepEqual(waits, [300, 300, 300]);
  assert.equal(computer.actions.filter(a => a.type === "click").length, 1);
});

test("missing and disabled Courses ask for help after bounded observation", async () => {
  const disabled = dashboard(); disabled.elements[1].enabled = false;
  for (const state of [login(), disabled]) {
    const computer = new Scenario([state]);
    const result = await createAgent(computer, fast).submit(input);
    assert.equal(result.success, false);
    assert.equal(computer.reads, 10);
    assert.equal(computer.actions.length, 1);
  }
});

test("ambiguous, incomplete, denied, and changed-focus snapshots never click", async () => {
  const ambiguous = dashboard(); ambiguous.elements.push({ ...ambiguous.elements[1], id: "e99" });
  const wrongRole = dashboard(); wrongRole.elements[1].role = "AXTextField";
  for (const state of [ambiguous, { ...dashboard(), truncated: true }, { ...dashboard(), accessibilityTrusted: false }, { ...dashboard(), activeApp: "Finder" }, wrongRole]) {
    const computer = new Scenario([state]);
    assert.equal((await createAgent(computer, fast).submit(input)).success, false);
    assert.equal(computer.actions.length, 1);
  }
});

test("exact normalized label match accepts spacing but never substring matches", async () => {
  const normalized = dashboard(); normalized.elements[1].label = "  COURSES  ";
  assert.equal((await createAgent(new Scenario([normalized, courses()]), fast).submit(input)).success, true);
  const misleading = dashboard(); misleading.elements[1].label = "Delete Courses";
  const computer = new Scenario([misleading]);
  assert.equal((await createAgent(computer, fast).submit(input)).success, false);
  assert.equal(computer.actions.length, 1);
});

test("helper errors and stale IDs stop immediately without retrying", async () => {
  const stale = new Scenario([dashboard()], { success: false, error: "Target e2 is stale" });
  const result = await createAgent(stale, fast).submit(input);
  assert.deepEqual(result, { success: false, error: "Target e2 is stale" });
  assert.equal(stale.reads, 1);
  const denied = new Scenario([new Error("Permission denied")]);
  assert.deepEqual(await createAgent(denied, fast).submit(input), { success: false, error: "Permission denied" });
});

test("click success without a visible outcome never emits done", async () => {
  for (const state of [dashboard(), { ...dashboard(), elements: [...dashboard().elements, courses().elements[1]] }]) {
    const computer = new Scenario([state]);
    const events: AgentEvent[] = [];
    const agent = createAgent(computer, fast); agent.subscribe(e => events.push(e));
    assert.equal((await agent.submit(input)).success, false);
    assert.equal(computer.reads, 10);
    assert.equal(computer.actions.length, 2);
    assert.ok(!events.some(e => e.type === "done"));
  }
});

test("a verified Courses title completes without another click", async () => {
  const computer = new Scenario([{ ...dashboard(), activeWindow: "Courses - Canvas" }]);
  assert.equal((await createAgent(computer, fast).submit(input)).success, true);
  assert.equal(computer.actions.length, 1);
});

test("disconnect cancels navigation before a delayed snapshot can cause a click", async () => {
  let resolve!: (state: ComputerState) => void;
  const actions: ComputerAction[] = [];
  const agent = createAgent({ getState: () => new Promise(r => { resolve = r; }), execute: async action => { actions.push(action); return { success: true }; } }, fast);
  const result = agent.submit(input);
  await new Promise(r => setImmediate(r));
  agent.dispose(); resolve(dashboard());
  assert.equal((await result).success, false);
  assert.equal(actions.length, 1);
});

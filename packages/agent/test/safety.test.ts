import assert from "node:assert/strict";
import test from "node:test";
import { createAgent } from "../src/agent.js";
import { MockComputerController } from "../src/mock-controller.js";
import { ActionGate, classifyAction } from "../src/safety.js";
import type { Skill } from "../src/skills.js";
import type { ActionResult, AgentEvent, AgentResult, ComputerAction, ComputerState, PendingConfirmation } from "../../shared/src/types.js";

// Mock-only injected action. No deletion primitive or production input route exists.
const simulated: Skill = {
  action: { type: "launch_app", app: "Mock deletion executor" }, effect: "deletion",
  actingMessage: "Simulate deleting the disposable example item", doneMessage: "Simulation completed.",
};
const input = { source: "aac" as const, intent: "TEST_ONLY_DELETE" };
function pending(result: AgentResult): PendingConfirmation {
  assert.ok(!result.success && result.requiresConfirmation);
  return result as PendingConfirmation;
}
function setup(skill: Skill = simulated) {
  const computer = new MockComputerController();
  let time = 1_000;
  const agent = createAgent(computer, { resolveSkill: () => skill, now: () => time });
  const events: AgentEvent[] = [];
  agent.subscribe(e => events.push(e));
  return { agent, computer, events, advance: (ms: number) => { time += ms; } };
}

test("risk classification requires both action and trusted intended effect", () => {
  assert.equal(classifyAction({ type: "click", target: "e1" }), "sensitive");
  assert.equal(classifyAction({ type: "click", target: "e1" }, "deletion"), "destructive");
  assert.equal(classifyAction({ type: "click", target: "e1" }, "navigation"), "safe");
  assert.equal(classifyAction({ type: "keypress", key: "+", modifiers: ["CMD"] }, "zoom"), "safe");
  assert.equal(classifyAction({ type: "keypress", key: "W", modifiers: ["CMD"] }, "zoom"), "sensitive");
  assert.equal(classifyAction({ type: "open_url", url: "file:///private" }, "navigation"), "sensitive");
});

test("destructive simulation pauses with exact action and executes only once after approval", async () => {
  const { agent, computer, events } = setup();
  const request = pending(await agent.submit(input));
  assert.equal(computer.actions.length, 0);
  const prompt = events.find(e => e.type === "confirmation_required");
  assert.ok(prompt?.type === "confirmation_required");
  assert.deepEqual(prompt.action, simulated.action);
  assert.equal(prompt.risk, "destructive");
  assert.equal(prompt.expiresAt, 61_000);
  assert.equal((await agent.confirm(request.confirmationId, true)).success, true);
  assert.equal((await agent.confirm(request.confirmationId, true)).success, false);
  assert.deepEqual(computer.actions, [simulated.action]);
  assert.equal(events.filter(e => e.type === "done").length, 1);
  agent.dispose();
});

test("cancel, expiration, and disconnect execute nothing and consume the ID", async () => {
  for (const reason of ["cancel", "expire", "disconnect"]) {
    const s = setup();
    const request = pending(await s.agent.submit(input));
    if (reason === "cancel") await s.agent.confirm(request.confirmationId, false);
    if (reason === "expire") s.advance(60_000);
    if (reason === "disconnect") s.agent.dispose();
    assert.equal((await s.agent.confirm(request.confirmationId, true)).success, false);
    assert.deepEqual(s.computer.actions, []);
    if (reason === "expire") assert.ok(s.events.some(e => e.type === "confirmation_resolved" && e.reason === "expired"));
    s.agent.dispose();
  }
});

test("pending confirmation blocks submissions; an unrelated ID cannot approve it", async () => {
  const s = setup(); const request = pending(await s.agent.submit(input));
  assert.equal((await s.agent.submit({ source: "text", text: "Open Canvas" })).success, false);
  assert.equal((await s.agent.confirm("wrong-id", true)).success, false);
  assert.equal((await s.agent.confirm(request.confirmationId, true)).success, true);
  assert.equal(s.computer.actions.length, 1);
});

test("mutating a skill or prompt cannot change the approved action", async () => {
  const skill = structuredClone(simulated);
  const s = setup(skill);
  s.agent.subscribe(e => { if (e.type === "confirmation_required" && e.action.type === "launch_app") e.action.app = "Changed by UI"; });
  const request = pending(await s.agent.submit(input));
  skill.action = { type: "launch_app", app: "Changed by caller" };
  assert.equal((await s.agent.confirm(request.confirmationId, true)).success, true);
  assert.deepEqual(s.computer.actions, [simulated.action]);
});

test("unknown and sensitive effects require approval too", async () => {
  for (const effect of [undefined, "submission" as const]) {
    const s = setup({ ...simulated, effect });
    const request = pending(await s.agent.submit(input));
    assert.equal(s.events.find(e => e.type === "confirmation_required")?.risk, "sensitive");
    assert.equal(s.computer.actions.length, 0);
    await s.agent.confirm(request.confirmationId, false);
    s.agent.dispose();
  }
});

test("concurrent approvals cannot duplicate an action, including failed execution", async () => {
  let finish!: (result: ActionResult) => void;
  const actions: ComputerAction[] = [];
  const agent = createAgent({
    getState: () => new MockComputerController().getState(),
    execute: action => { actions.push(action); return new Promise(resolve => { finish = resolve; }); },
  }, { resolveSkill: () => simulated });
  const request = pending(await agent.submit(input));
  const first = agent.confirm(request.confirmationId, true);
  assert.equal((await agent.confirm(request.confirmationId, true)).success, false);
  finish({ success: false, error: "Simulated executor error" });
  assert.deepEqual(await first, { success: false, error: "Simulated executor error" });
  assert.equal((await agent.confirm(request.confirmationId, true)).success, false);
  assert.equal(actions.length, 1);
});

test("targeted approvals invalidate changed window, role, ID, label, or permission", async () => {
  const base = await new MockComputerController().getState();
  const changed: ComputerState[] = [
    { ...base, activeWindow: "Other window" }, { ...base, activeApp: "Finder" },
    { ...base, accessibilityTrusted: false }, { ...base, truncated: true },
    ...[{ id: "e99" }, { label: "Delete all" }, { enabled: false }, { role: "AXTextField" }].map(change => ({ ...base, elements: [{ ...base.elements[0], ...change }] })),
  ];
  for (const after of changed) {
    let reads = 0; let executions = 0;
    const agent = createAgent({
      getState: async () => reads++ === 0 ? base : after,
      execute: async () => { executions++; return { success: true }; },
    }, { resolveSkill: () => ({ ...simulated, action: { type: "click", target: "e1" } }) });
    const request = pending(await agent.submit(input));
    assert.equal((await agent.confirm(request.confirmationId, true)).success, false);
    assert.equal(executions, 0);
    assert.equal((await agent.confirm(request.confirmationId, true)).success, false);
  }
});

test("stable targeted mock context permits one approval; untargeted edits fail closed", async () => {
  const stable = setup({ ...simulated, action: { type: "click", target: "e1" } });
  const request = pending(await stable.agent.submit(input));
  assert.equal((await stable.agent.confirm(request.confirmationId, true)).success, true);
  assert.equal(stable.computer.actions.length, 1);
  const unsafe = setup({ ...simulated, action: { type: "type_text", text: "test" } });
  const result = await unsafe.agent.submit(input);
  assert.ok(!result.success && !result.requiresConfirmation);
  assert.equal(unsafe.computer.actions.length, 0);
});

test("atomic native-style validation confirms without taking an invalidating snapshot", async () => {
  const context: ComputerState = {
    snapshotGeneration: "generation-1",
    activeApp: "Microsoft Edge", activeWindow: "Canvas", accessibilityTrusted: true, truncated: false,
    elements: [{ id: "e1", role: "AXButton", label: "Submit", enabled: true, actions: ["AXPress"] }],
  };
  let reads = 0; let ordinaryExecutions = 0; let validatedExecutions = 0;
  const lifecycle = new AbortController();
  const gate = new ActionGate({
    getState: async () => { reads++; return structuredClone(context); },
    execute: async () => { ordinaryExecutions++; return { success: true }; },
    executeValidated: async (action, expected) => {
      validatedExecutions++;
      assert.deepEqual(action, { type: "click", target: "e1", snapshotGeneration: "generation-1" });
      assert.deepEqual(expected, context);
      return { success: true };
    },
  }, () => {}, lifecycle.signal);
  const request = pending(await gate.run({
    action: { type: "click", target: "e1", snapshotGeneration: "generation-1" },
    context,
    effect: "submission",
    actingMessage: "Submit", doneMessage: "Submitted",
  }));
  assert.equal(reads, 0);
  assert.equal((await gate.confirm(request.confirmationId, true)).success, true);
  assert.equal(reads, 0);
  assert.equal(ordinaryExecutions, 0);
  assert.equal(validatedExecutions, 1);
});

test("disposal during context validation prevents execution", async () => {
  let resolve!: (state: ComputerState) => void;
  let reads = 0; let executions = 0;
  const base = await new MockComputerController().getState();
  const agent = createAgent({
    getState: () => ++reads === 1 ? Promise.resolve(base) : new Promise(r => { resolve = r; }),
    execute: async () => { executions++; return { success: true }; },
  }, { resolveSkill: () => ({ ...simulated, action: { type: "click", target: "e1" } }) });
  const request = pending(await agent.submit(input));
  const result = agent.confirm(request.confirmationId, true);
  agent.dispose(); resolve(base);
  assert.equal((await result).success, false);
  assert.equal(executions, 0);
});

test("public confirm API refuses truthy non-boolean approval values", async () => {
  const s = setup(); const request = pending(await s.agent.submit(input));
  // @ts-expect-error Simulates an untyped JavaScript caller.
  assert.equal((await s.agent.confirm(request.confirmationId, "false")).success, false);
  assert.equal(s.computer.actions.length, 0);
  await s.agent.confirm(request.confirmationId, false);
});

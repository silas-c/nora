import assert from "node:assert/strict";
import test from "node:test";
import { createAgent, MockComputerController } from "../src/index.js";
import type { ActionResult, AgentResult, ComputerAction } from "../../shared/src/types.js";

const canvas = { source: "aac" as const, intent: "OPEN_SCHOOL" };
const simulated = {
  action: { type: "launch_app" as const, app: "Mock deletion executor" }, effect: "deletion" as const,
  actingMessage: "Simulate deletion", doneMessage: "Mock action completed.",
};
const simulation = { source: "aac" as const, intent: "TEST_HISTORY" };
const getId = (result: AgentResult) => {
  assert.ok(!result.success && result.requiresConfirmation);
  return result.confirmationId;
};

test("history records attempted controller actions and outcomes, not unknown inputs", async () => {
  let time = 100;
  const agent = createAgent(new MockComputerController(), { now: () => time++ });
  await agent.submit(canvas);
  await agent.submit({ source: "text", text: "unrecognized request" });
  const history = agent.getHistory();
  assert.equal(history.length, 1);
  assert.deepEqual(history[0], {
    id: 1, action: { type: "open_url", url: "https://canvas.temple.edu", browser: "Microsoft Edge" },
    success: true, timestamp: 100, completedAt: 101,
  });
  agent.dispose();
});

test("reported failures and exceptions each produce one failed entry without error content", async () => {
  for (const controller of [
    new MockComputerController({ success: false, error: "private error text" }),
    { getState: () => new MockComputerController().getState(), execute: async (): Promise<ActionResult> => { throw new Error("private error text"); } },
  ]) {
    const agent = createAgent(controller);
    await agent.submit(canvas);
    assert.equal(agent.getHistory().length, 1);
    assert.equal(agent.getHistory()[0].success, false);
    assert.ok(!JSON.stringify(agent.getHistory()).includes("private error text"));
    agent.dispose();
  }
});

test("cancelled/expired/replayed approvals do not create action entries", async () => {
  let time = 0;
  const agent = createAgent(new MockComputerController(), { resolveSkill: () => simulated, now: () => time });
  let id = getId(await agent.submit(simulation));
  assert.deepEqual(agent.getHistory(), []);
  await agent.confirm(id, false);
  id = getId(await agent.submit(simulation));
  time = 60_000;
  await agent.confirm(id, true);
  assert.deepEqual(agent.getHistory(), []);
  id = getId(await agent.submit(simulation));
  await agent.confirm(id, true);
  await agent.confirm(id, true);
  assert.equal(agent.getHistory().length, 1);
  agent.dispose();
});

test("history redacts text and URL credentials/path/query/fragment before retention", async () => {
  const actions: ComputerAction[] = [
    { type: "open_url", url: "https://user:password@example.com/private/name?token=secret#private" },
    { type: "type_text", target: "e1", text: "private message" },
  ];
  for (const action of actions) {
    const agent = createAgent(new MockComputerController(), {
      resolveSkill: () => ({ action, actingMessage: "Test action", doneMessage: "Test complete" }),
    });
    await agent.confirm(getId(await agent.submit(simulation)), true);
    const history = agent.getHistory();
    assert.equal(history.length, 1);
    const serialized = JSON.stringify(history);
    for (const secret of ["user:", "password", "/private", "token", "secret", "private message"]) assert.ok(!serialized.includes(secret));
    if (history[0].action.type === "type_text") assert.equal(history[0].action.text, "[redacted]");
    else assert.deepEqual(history[0].action, { type: "open_url", url: "https://example.com" });
    agent.dispose();
  }
});

test("history retains the newest 100 entries and returns independent copies", async () => {
  const agent = createAgent(new MockComputerController());
  for (let i = 0; i < 105; i++) await agent.submit(canvas);
  const entries = agent.getHistory();
  assert.equal(entries.length, 100);
  assert.equal(entries[0].id, 6);
  entries[0].success = false;
  entries[0].action = { type: "launch_app", app: "Changed externally" };
  entries.length = 0;
  assert.equal(agent.getHistory().length, 100);
  assert.equal(agent.getHistory()[0].success, true);
  agent.clearHistory();
  assert.deepEqual(agent.getHistory(), []);
  agent.dispose();
});

test("clear and disposal suppress late history from an in-flight action", async () => {
  for (const dispose of [false, true]) {
    let finish!: (result: ActionResult) => void;
    const agent = createAgent({
      getState: () => new MockComputerController().getState(),
      execute: () => new Promise(resolve => { finish = resolve; }),
    });
    const result = agent.submit(canvas);
    assert.deepEqual(agent.getHistory(), []);
    if (dispose) agent.dispose(); else agent.clearHistory();
    finish({ success: true }); await result;
    assert.deepEqual(agent.getHistory(), []);
    agent.dispose();
  }
});

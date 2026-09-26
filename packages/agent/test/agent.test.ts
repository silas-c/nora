import assert from "node:assert/strict";
import test from "node:test";
import type { AgentEvent, ActionResult, ComputerAction, UserInput } from "../../shared/src/types.js";
import { createAgent, MockComputerController } from "../src/index.js";

test("text, voice and AAC inputs route to the same Canvas action", async () => {
  const inputs: UserInput[] = [
    { source: "text", text: "  Please OPEN Canvas in Edge! " },
    { source: "voice", text: "open my schoolwork" },
    { source: "aac", intent: "OPEN_SCHOOL" },
    { source: "aac", intent: "OPEN_CANVAS" },
  ];
  for (const input of inputs) {
    const controller = new MockComputerController();
    const agent = createAgent(controller);
    const events: AgentEvent[] = [];
    agent.subscribe(event => events.push(event));
    assert.equal((await agent.submit(input)).success, true);
    assert.deepEqual(controller.actions, [{ type: "open_url", url: "https://canvas.temple.edu", browser: "Microsoft Edge" }]);
    assert.deepEqual(events.map(event => event.type), ["thinking", "acting", "done"]);
  }
});

test("unknown, negated, and compound requests never execute", async () => {
  const controller = new MockComputerController();
  const agent = createAgent(controller);
  for (const text of ["", "do not open canvas", "open canvas and delete my files", "open canvas in Chrome", "do not show me dog photos", "show me dog photos and upload my pictures"]) {
    assert.equal((await agent.submit({ source: "text", text })).success, false);
  }
  assert.equal((await agent.submit({ source: "aac", intent: "DELETE_FILES" })).success, false);
  assert.deepEqual(controller.actions, []);
});

test("controller failures and exceptions emit error without done", async () => {
  for (const controller of [
    new MockComputerController({ success: false, error: "Edge not installed" }),
    { async execute(): Promise<ActionResult> { throw new Error("Helper unavailable"); } },
  ]) {
    const agent = createAgent(controller);
    const events: AgentEvent[] = [];
    agent.subscribe(event => events.push(event));
    assert.equal((await agent.submit({ source: "aac", intent: "OPEN_SCHOOL" })).success, false);
    assert.deepEqual(events.map(event => event.type), ["thinking", "acting", "error"]);
  }
});

test("unsubscribe and broken subscribers do not interfere with execution", async () => {
  const agent = createAgent(new MockComputerController());
  const events: AgentEvent[] = [];
  agent.subscribe(() => { throw new Error("UI error"); });
  const unsubscribe = agent.subscribe(event => events.push(event));
  assert.equal((await agent.submit({ source: "text", text: "open canvas" })).success, true);
  unsubscribe();
  await agent.submit({ source: "text", text: "open canvas" });
  assert.equal(events.length, 3);
});

test("busy submissions do not duplicate actions and agent is reusable afterward", async () => {
  let finish!: (result: ActionResult) => void;
  let calls = 0;
  const agent = createAgent({ execute: () => { calls++; return new Promise(resolve => { finish = resolve; }); } });
  const input: UserInput = { source: "aac", intent: "OPEN_SCHOOL" };
  const first = agent.submit(input);
  assert.equal((await agent.submit(input)).success, false);
  assert.equal(calls, 1);
  finish({ success: true });
  await first;
  const next = agent.submit(input);
  finish({ success: true });
  assert.equal((await next).success, true);
  assert.equal(calls, 2);
});


import assert from "node:assert/strict";
import test from "node:test";
import type { AgentEvent, ActionResult, ComputerAction, UserInput } from "../../shared/src/types.js";
import { createAgent, MockComputerController } from "../src/index.js";

test("text, voice and AAC inputs route to the same Canvas action", async () => {
  const inputs: UserInput[] = [
    { source: "text", text: "  Please OPEN Canvas in Edge! " },
    { source: "voice", text: "open my schoolwork" },
    { source: "voice", text: "Open Canvas on Microsoft edge" },
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
    { getState: () => new MockComputerController().getState(), async execute(): Promise<ActionResult> { throw new Error("Helper unavailable"); } },
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
  const agent = createAgent({ getState: () => new MockComputerController().getState(), execute: () => { calls++; return new Promise(resolve => { finish = resolve; }); } });
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

test("public image, app and zoom skills map text and AAC inputs to bounded actions", async () => {
  const cases: [string, string, ComputerAction][] = [
    ["Show me dog photos", "OPEN_DOG_PHOTOS", { type: "open_url", url: "https://www.google.com/search?tbm=isch&q=dogs", browser: "Microsoft Edge" }],
    ["Open Photos", "OPEN_PHOTOS", { type: "launch_app", app: "Photos" }],
    ["Please open Microsoft Edge", "OPEN_INTERNET", { type: "launch_app", app: "Microsoft Edge" }],
    ["open finder please", "OPEN_FINDER", { type: "launch_app", app: "Finder" }],
    ["Make the text bigger", "ZOOM_IN", { type: "keypress", key: "+", modifiers: ["CMD"] }],
    ["Zoom out", "ZOOM_OUT", { type: "keypress", key: "-", modifiers: ["CMD"] }],
  ];
  for (const [text, intent, action] of cases) {
    const controller = new MockComputerController();
    const agent = createAgent(controller);
    assert.equal((await agent.submit({ source: "voice", text })).success, true);
    assert.equal((await agent.submit({ source: "aac", intent })).success, true);
    assert.deepEqual(controller.actions, [action, action]);
  }
});

test("compound app requests and unsupported apps do not execute", async () => {
  const controller = new MockComputerController();
  const agent = createAgent(controller);
  for (const text of ["open Photos and delete pictures", "do not zoom in", "open Terminal", "open Photos.app; rm -rf /", "zoom in twice"]) {
    assert.equal((await agent.submit({ source: "text", text })).success, false);
  }
  assert.deepEqual(controller.actions, []);
});

test("zoom permission error surfaces to the UI without claiming success", async () => {
  const agent = createAgent(new MockComputerController({ success: false, error: "Accessibility permission is required" }));
  const events: AgentEvent[] = [];
  agent.subscribe(event => events.push(event));
  assert.deepEqual(await agent.submit({ source: "aac", intent: "ZOOM_IN" }), { success: false, error: "Accessibility permission is required" });
  assert.deepEqual(events.map(event => event.type), ["thinking", "acting", "error"]);
});

test("mock snapshots are independent copies", async () => {
  const controller = new MockComputerController();
  const first = await controller.getState();
  first.elements[0].actions.push("changed");
  first.elements.length = 0;
  const second = await controller.getState();
  assert.equal(second.elements.length, 1);
  assert.deepEqual(second.elements[0].actions, ["AXPress"]);
});

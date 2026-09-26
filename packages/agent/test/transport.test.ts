import assert from "node:assert/strict";
import test from "node:test";
import { PassThrough } from "node:stream";
import type { AgentOptions } from "../src/agent.js";
import { createAgent, MockComputerController } from "../src/index.js";
import { serveAgent, type AgentMessage } from "../src/transport.js";
import type { ActionResult, ComputerController } from "../../shared/src/types.js";

const tick = () => new Promise(resolve => setImmediate(resolve));
function session(controller: ComputerController = new MockComputerController(), options: AgentOptions = {}) {
  const input = new PassThrough();
  const output = new PassThrough();
  const messages: AgentMessage[] = [];
  let closes = 0;
  output.on("data", chunk => {
    for (const line of String(chunk).trim().split("\n")) messages.push(JSON.parse(line));
  });
  const agent = createAgent(controller, options);
  const done = serveAgent(input, output, agent, async () => { closes++; });
  const send = (request: unknown) => input.write(JSON.stringify(request) + "\n");
  return { agent, input, output, messages, done, send, closes: () => closes };
}

test("one UI session routes text and AAC results and events by request ID", async () => {
  const computer = new MockComputerController();
  const s = session(computer);
  s.send({ type: "submit", requestId: "text-1", input: { source: "text", text: "Open Canvas" } });
  await tick();
  s.send({ type: "submit", requestId: "tile-1", input: { source: "aac", intent: "OPEN_SCHOOL" } });
  await tick();
  assert.equal(computer.actions.length, 2);
  for (const id of ["text-1", "tile-1"]) {
    const messages = s.messages.filter(m => m.requestId === id);
    assert.deepEqual(messages.map(m => m.type), ["event", "event", "event", "result"]);
    const last = messages.at(-1);
    assert.equal(last?.type === "result" && last.result.success, true);
  }
  s.input.end(); await s.done;
  assert.equal(s.closes(), 1);
});

test("malformed input and reused IDs fail without losing the session", async () => {
  const s = session();
  s.input.write("not json\n");
  s.send({ type: "submit", requestId: "bad", input: { source: "voice", text: 42 } });
  s.send({ type: "submit", requestId: "good", input: { source: "text", text: "open canvas" } });
  await tick();
  s.send({ type: "submit", requestId: "good", input: { source: "text", text: "open canvas" } });
  await tick();
  assert.equal(s.messages.filter(m => m.type === "protocol_error").length, 3);
  assert.equal(s.messages.filter(m => m.type === "result").length, 1);
  s.input.end(); await s.done;
});

test("overlapping submissions return busy and do not steal events", async () => {
  let finish!: (result: ActionResult) => void;
  const s = session({ getState: () => new MockComputerController().getState(), execute: () => new Promise(resolve => { finish = resolve; }) });
  s.send({ type: "submit", requestId: "first", input: { source: "aac", intent: "OPEN_SCHOOL" } });
  s.send({ type: "submit", requestId: "second", input: { source: "aac", intent: "OPEN_SCHOOL" } });
  await tick();
  const busy = s.messages.find(m => m.requestId === "second");
  assert.equal(busy?.type === "result" && busy.result.success, false);
  finish({ success: true }); await tick();
  assert.ok(s.messages.filter(m => m.type === "event").every(m => m.requestId === "first"));
  s.input.end(); await s.done;
});

test("partial lines are buffered; oversized and truncated requests are rejected", async () => {
  const s = session();
  s.input.write('{"type":"submit","requestId":"x",');
  assert.equal(s.messages.length, 0);
  s.input.write('"input":{"source":"aac","intent":"OPEN_SCHOOL"}}\n');
  await tick();
  assert.equal(s.messages.at(-1)?.type, "result");
  s.input.end('{'); await s.done;
  assert.equal(s.messages.at(-1)?.type, "protocol_error");
  const oversized = session();
  oversized.input.write("x".repeat(65537));
  await oversized.done;
  assert.equal(oversized.messages[0].type, "protocol_error");
  assert.equal(oversized.closes(), 1);
});

test("disconnect during a request closes resources and suppresses late output", async () => {
  let finish!: (result: ActionResult) => void;
  const s = session({ getState: () => new MockComputerController().getState(), execute: () => new Promise(resolve => { finish = resolve; }) });
  s.send({ type: "submit", requestId: "x", input: { source: "aac", intent: "OPEN_SCHOOL" } });
  await tick();
  s.output.destroy(); await s.done;
  const count = s.messages.length;
  finish({ success: true }); await tick();
  assert.equal(s.messages.length, count);
  assert.equal(s.closes(), 1);
});

const simulation: AgentOptions = {
  resolveSkill: () => ({
    action: { type: "launch_app", app: "Mock deletion executor" }, effect: "deletion",
    actingMessage: "Simulate deleting a disposable item", doneMessage: "Simulation completed.",
  }),
};
function confirmationId(messages: AgentMessage[]): string {
  const prompt = messages.find(m => m.type === "event" && m.event.type === "confirmation_required");
  assert.ok(prompt?.type === "event" && prompt.event.type === "confirmation_required");
  return prompt.event.confirmationId;
}

test("transport carries pending results, approval/cancel, and single-use IDs", async () => {
  for (const approved of [true, false]) {
    const computer = new MockComputerController();
    const s = session(computer, simulation);
    s.send({ type: "submit", requestId: "request", input: { source: "aac", intent: "TEST_ONLY_DELETE" } });
    await tick();
    const id = confirmationId(s.messages);
    const initial = s.messages.at(-1);
    assert.ok(initial?.type === "result" && !initial.result.success && initial.result.requiresConfirmation);
    assert.equal(computer.actions.length, 0);
    s.send({ type: "confirm", requestId: "decision", confirmationId: id, approved });
    await tick();
    const result = s.messages.at(-1);
    assert.ok(result?.type === "result" && result.requestId === "decision" && result.result.success);
    assert.equal(computer.actions.length, approved ? 1 : 0);
    s.send({ type: "confirm", requestId: "replay", confirmationId: id, approved: true });
    await tick();
    const replay = s.messages.at(-1);
    assert.ok(replay?.type === "result" && !replay.result.success);
    assert.equal(computer.actions.length, approved ? 1 : 0);
    s.input.end(); await s.done;
  }
});

test("expiration resolves the original prompt even when another request triggers the clock check", async () => {
  let now = 0;
  const computer = new MockComputerController();
  const s = session(computer, { ...simulation, now: () => now });
  s.send({ type: "submit", requestId: "original", input: { source: "aac", intent: "TEST_ONLY_DELETE" } });
  await tick();
  const id = confirmationId(s.messages);
  now = 60_000;
  s.send({ type: "confirm", requestId: "late", confirmationId: id, approved: true });
  await tick();
  const expiry = s.messages.find(m => m.type === "event" && m.event.type === "confirmation_resolved");
  assert.ok(expiry?.type === "event" && expiry.requestId === "original" && expiry.event.type === "confirmation_resolved" && expiry.event.reason === "expired");
  assert.equal(computer.actions.length, 0);
  s.input.end(); await s.done;
});

test("malformed approvals and disconnect never execute a pending action", async () => {
  const computer = new MockComputerController();
  const s = session(computer, simulation);
  s.send({ type: "submit", requestId: "original", input: { source: "aac", intent: "TEST_ONLY_DELETE" } });
  await tick();
  const id = confirmationId(s.messages);
  s.send({ type: "confirm", requestId: "invalid", confirmationId: id, approved: "true" });
  await tick();
  assert.equal(s.messages.at(-1)?.type, "protocol_error");
  s.input.end(); await s.done;
  assert.equal((await s.agent.confirm(id, true)).success, false);
  assert.equal(computer.actions.length, 0);
});

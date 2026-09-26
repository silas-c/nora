import assert from "node:assert/strict";
import test from "node:test";
import { PassThrough } from "node:stream";
import { createAgent, MockComputerController } from "../src/index.js";
import { serveAgent, type AgentMessage } from "../src/transport.js";
import type { ActionResult, ComputerController } from "../../shared/src/types.js";

const tick = () => new Promise(resolve => setImmediate(resolve));
function session(controller: ComputerController = new MockComputerController()) {
  const input = new PassThrough();
  const output = new PassThrough();
  const messages: AgentMessage[] = [];
  let closes = 0;
  output.on("data", chunk => {
    for (const line of String(chunk).trim().split("\n")) messages.push(JSON.parse(line));
  });
  const done = serveAgent(input, output, createAgent(controller), async () => { closes++; });
  const send = (request: unknown) => input.write(JSON.stringify(request) + "\n");
  return { input, output, messages, done, send, closes: () => closes };
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

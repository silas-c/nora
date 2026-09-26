import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import test from "node:test";
import type { AgentMessage } from "../src/transport.js";

test("mock confirmation server supports cancel, approve, and replay without native actions", async () => {
  const script = new URL("../src/confirmation-demo-server.js", import.meta.url);
  const child = spawn(process.execPath, [script.pathname], { stdio: ["pipe", "pipe", "pipe"] });
  const lines = createInterface({ input: child.stdout });
  const messages: AgentMessage[] = [];
  const waiters: Array<{ match: (message: AgentMessage) => boolean; resolve: (message: AgentMessage) => void }> = [];
  lines.on("line", line => {
    const message = JSON.parse(line) as AgentMessage;
    messages.push(message);
    const index = waiters.findIndex(waiter => waiter.match(message));
    if (index >= 0) waiters.splice(index, 1)[0].resolve(message);
  });
  const waitFor = (match: (message: AgentMessage) => boolean) => {
    const existing = messages.find(match);
    return existing ? Promise.resolve(existing) : new Promise<AgentMessage>(resolve => waiters.push({ match, resolve }));
  };
  const send = (request: unknown) => child.stdin.write(JSON.stringify(request) + "\n");
  const submit = async (requestId: string) => {
    send({ type: "submit", requestId, input: { source: "aac", intent: "TEST_ONLY_DELETE" } });
    const prompt = await waitFor(message => message.type === "event" && message.requestId === requestId
      && message.event.type === "confirmation_required");
    assert.ok(prompt.type === "event" && prompt.event.type === "confirmation_required");
    assert.deepEqual(prompt.event.action, { type: "launch_app", app: "Mock deletion executor" });
    assert.equal(prompt.event.risk, "destructive");
    const pending = await waitFor(message => message.type === "result" && message.requestId === requestId);
    assert.ok(pending.type === "result" && !pending.result.success && pending.result.requiresConfirmation);
    return prompt.event.confirmationId;
  };
  const history = async (requestId: string) => {
    send({ type: "get_history", requestId });
    const response = await waitFor(message => message.type === "history" && message.requestId === requestId);
    assert.equal(response.type, "history");
    return response.entries;
  };

  try {
    const cancelled = await submit("cancel-submit");
    assert.deepEqual(await history("before-cancel"), []);
    send({ type: "confirm", requestId: "cancel", confirmationId: cancelled, approved: false });
    const cancel = await waitFor(message => message.type === "result" && message.requestId === "cancel");
    assert.ok(cancel.type === "result" && cancel.result.success);
    assert.deepEqual(await history("after-cancel"), []);

    const approved = await submit("approve-submit");
    send({ type: "confirm", requestId: "approve", confirmationId: approved, approved: true });
    const approval = await waitFor(message => message.type === "result" && message.requestId === "approve");
    assert.ok(approval.type === "result" && approval.result.success);
    assert.deepEqual((await history("after-approve")).map(entry => entry.action), [
      { type: "launch_app", app: "Mock deletion executor" },
    ]);

    send({ type: "confirm", requestId: "replay", confirmationId: approved, approved: true });
    const replay = await waitFor(message => message.type === "result" && message.requestId === "replay");
    assert.ok(replay.type === "result" && !replay.result.success);
    assert.equal((await history("after-replay")).length, 1);
  } finally {
    child.stdin.end();
    const [code] = await once(child, "exit");
    lines.close();
    assert.equal(code, 0);
  }
});

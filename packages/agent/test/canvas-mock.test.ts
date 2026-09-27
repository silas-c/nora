import assert from "node:assert/strict";
import test from "node:test";
import { createAgent, CanvasMockComputerController } from "../src/index.js";

const open = { type: "open_url" as const, url: "https://canvas.temple.edu", browser: "Microsoft Edge" };
const courses = { source: "aac" as const, intent: "OPEN_COURSES" };

test("fixture-backed controller completes the real agent navigation flow repeatedly", async () => {
  const controller = new CanvasMockComputerController();
  const agent = createAgent(controller, { wait: async () => {} });
  for (let run = 0; run < 2; run++) {
    assert.equal((await agent.submit(courses)).success, true);
    const state = await controller.getState();
    assert.ok(state.elements.some(e => e.label === "All Courses"));
  }
  assert.deepEqual(controller.actions.map(a => a.type), ["open_url", "click", "open_url", "click"]);
  assert.deepEqual(agent.getHistory().map(e => e.success), [true, true, true, true]);
  agent.dispose();
});

test("new snapshots invalidate old IDs and Courses appears only after a valid click", async () => {
  const controller = new CanvasMockComputerController();
  await controller.execute(open);
  const old = (await controller.getState()).elements.find(e => e.label === "Courses")!;
  const current = await controller.getState();
  assert.ok(!current.elements.some(e => e.label === "All Courses"));
  assert.equal((await controller.execute({ type: "click", target: old.id, snapshotGeneration: "mock-generation-1" })).success, false);
  const target = current.elements.find(e => e.label === "Courses")!;
  const action = { type: "click" as const, target: target.id, snapshotGeneration: current.snapshotGeneration };
  assert.equal((await controller.execute(action)).success, true);
  assert.equal((await controller.execute(action)).success, false);
  assert.ok((await controller.getState()).elements.some(e => e.label === "All Courses"));
});

test("login fixture fails with help, and no click is attempted", async () => {
  const controller = new CanvasMockComputerController("login");
  const agent = createAgent(controller, { wait: async () => {} });
  const result = await agent.submit(courses);
  assert.ok(!result.success && !result.requiresConfirmation);
  assert.match(result.error, /Sign in to Canvas/);
  assert.deepEqual(controller.actions.map(a => a.type), ["open_url"]);
  agent.dispose();
});

test("caller mutation cannot change a controller's valid click targets", async () => {
  const controller = new CanvasMockComputerController();
  const state = await controller.getState();
  const target = state.elements.find(e => e.label === "Courses")!;
  const id = target.id;
  const snapshotGeneration = state.snapshotGeneration;
  target.id = "made-up";
  target.label = "Other action";
  assert.equal((await controller.execute({ type: "click", target: "made-up", snapshotGeneration })).success, false);
  assert.equal((await controller.execute({ type: "click", target: id, snapshotGeneration })).success, true);
});

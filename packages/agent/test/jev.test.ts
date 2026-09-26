import assert from "node:assert/strict";
import test from "node:test";
import type { ComputerState } from "../../shared/src/types.js";
import {
  BoundedJevChooser,
  JevDecisionError,
  MAX_JEV_ACTION_CANDIDATES,
  prepareJevDecision,
  type JevDecisionClient,
  type JevDecisionRequest,
} from "../src/jev.js";
import { TypeSafeJevClient } from "../src/typesafe-jev-client.js";

const state = (change: Partial<ComputerState> = {}): ComputerState => ({
  activeApp: "Microsoft Edge",
  activeWindow: "Canvas dashboard",
  accessibilityTrusted: true,
  truncated: false,
  elements: [
    { id: "native-secret-id", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] },
    { id: "disabled", role: "AXButton", label: "Submit", enabled: false, actions: ["AXPress"] },
    { id: "text", role: "AXTextField", label: "Search", enabled: true, actions: ["AXPress"] },
    { id: "unlabeled", role: "AXButton", enabled: true, actions: ["AXPress"] },
  ],
  ...change,
});

const probabilities = (criteria: Record<string, string>, selected: string, probability = 0.9) => {
  const keys = Object.keys(criteria);
  const other = keys.length === 1 ? 0 : (1 - probability) / (keys.length - 1);
  return Object.fromEntries(keys.map(key => [key, key === selected ? probability : other]));
};

class FakeClient implements JevDecisionClient {
  request?: JevDecisionRequest;
  constructor(private readonly reply: (request: JevDecisionRequest) => unknown) {}
  async choose(request: JevDecisionRequest): Promise<unknown> {
    this.request = request;
    return this.reply(request);
  }
}

test("preparation sends bounded labeled choices without native target IDs or values", () => {
  const prepared = prepareJevDecision({
    goal: "  Open\nCourses  ",
    state: state({ activeWindow: " Canvas\tDashboard " }),
  });
  assert.equal(prepared.state.goal, "Open Courses");
  assert.equal(prepared.state.active_window, "Canvas Dashboard");
  assert.deepEqual(prepared.state.controls, [
    { option: "action_000", role: "AXLink", label: "Courses", actions: ["AXPress"] },
  ]);
  assert.deepEqual(prepared.actions.get("action_000"), { type: "click", target: "native-secret-id" });
  const transmitted = JSON.stringify(prepared.state);
  assert.equal(transmitted.includes("native-secret-id"), false);
  assert.equal(transmitted.includes("disabled"), false);
  assert.equal(transmitted.includes("Search"), false);
  assert.equal(Object.keys(prepared.criteria).length, 4);
});

test("preparation rejects missing goals, denied permission, and incomplete snapshots", () => {
  assert.throws(() => prepareJevDecision({ goal: " ", state: state() }), JevDecisionError);
  assert.throws(() => prepareJevDecision({ goal: "Courses", state: state({ accessibilityTrusted: false }) }), /permission/i);
  assert.throws(() => prepareJevDecision({ goal: "Courses", state: state({ truncated: true }) }), /incomplete/i);
});

test("candidate construction is capped deterministically and reports omitted controls", () => {
  const elements = Array.from({ length: MAX_JEV_ACTION_CANDIDATES + 7 }, (_, index) => ({
    id: `e${index}`, role: "AXLink", label: `Course ${index}`, enabled: true, actions: ["AXPress"],
  }));
  const prepared = prepareJevDecision({ goal: "Find a course", state: state({ elements }) });
  assert.equal(prepared.state.controls.length, MAX_JEV_ACTION_CANDIDATES);
  assert.equal(prepared.state.controls_omitted, 7);
  assert.deepEqual(prepared.actions.get("action_199"), { type: "click", target: "e199" });
});

test("bounded chooser keeps native actions private and maps one opaque option locally", async () => {
  const client = new FakeClient(request => ({
    type: "choice", choice: "action_000", confidence: 0.94,
    probabilities: probabilities(request.criteria, "action_000", 0.94),
  }));
  const chooser = new BoundedJevChooser(client);
  assert.deepEqual(await chooser.choose({ goal: "Open Courses", state: state() }, new AbortController().signal), {
    type: "action", action: { type: "click", target: "native-secret-id" }, confidence: 0.94,
  });
  assert.ok(client.request);
  assert.equal(Object.hasOwn(client.request, "actions"), false);
  assert.equal(JSON.stringify(client.request).includes("native-secret-id"), false);
});

test("low confidence and explicit non-action outcomes never produce an action", async () => {
  for (const [choice, confidence, expected] of [
    ["action_000", 0.5, { type: "ask_user", confidence: 0.5, reason: "low_confidence" }],
    ["status_done", 0.95, { type: "done", confidence: 0.95 }],
    ["status_ask_user", 0.95, { type: "ask_user", confidence: 0.95, reason: "selected" }],
    ["status_blocked", 0.95, { type: "blocked", confidence: 0.95 }],
  ] as const) {
    const chooser = new BoundedJevChooser(new FakeClient(request => ({
      type: "choice", choice, confidence, probabilities: probabilities(request.criteria, choice, confidence),
    })));
    assert.deepEqual(await chooser.choose({ goal: "Open Courses", state: state() }, new AbortController().signal), expected);
  }
});

test("unknown choices and malformed probabilities fail closed", async () => {
  const replies = [
    { type: "choice", choice: "invented", confidence: 1, probabilities: {} },
    { type: "choice", choice: "action_000", confidence: 0.9, probabilities: { action_000: 0.9 } },
    { type: "choice", choice: "action_000", confidence: 0.9, probabilities: {
      ...probabilities(prepareJevDecision({ goal: "Open Courses", state: state() }).criteria, "action_000", 0.9),
      invented: 0,
    } },
    { type: "choice", choice: "action_000", confidence: 2, probabilities: {} },
  ];
  for (const reply of replies) {
    const chooser = new BoundedJevChooser(new FakeClient(() => reply));
    await assert.rejects(chooser.choose({ goal: "Open Courses", state: state() }, new AbortController().signal), JevDecisionError);
  }
});

test("cancellation is checked before and after the decision request", async () => {
  const before = new AbortController(); before.abort();
  const never = new FakeClient(() => { throw new Error("must not call"); });
  await assert.rejects(new BoundedJevChooser(never).choose({ goal: "Open Courses", state: state() }, before.signal), /aborted/i);

  const during = new AbortController();
  const client = new FakeClient(request => {
    during.abort();
    return { type: "choice", choice: "status_done", confidence: 1, probabilities: probabilities(request.criteria, "status_done", 1) };
  });
  await assert.rejects(new BoundedJevChooser(client).choose({ goal: "Open Courses", state: state() }, during.signal), /aborted/i);
});

test("TypeSafe adapter test seam forwards only prepared state and maps failures", async () => {
  let captured: JevDecisionRequest["state"] | undefined;
  const adapter = new TypeSafeJevClient({ call: async (sentState, criteria) => {
    captured = sentState;
    return { type: "choice", choice: "status_done", confidence: 1, probabilities: probabilities(criteria, "status_done", 1) };
  } });
  const chooser = new BoundedJevChooser(adapter);
  assert.deepEqual(await chooser.choose({ goal: "Open Courses", state: state() }, new AbortController().signal), {
    type: "done", confidence: 1,
  });
  assert.equal(JSON.stringify(captured).includes("native-secret-id"), false);

  const failed = new TypeSafeJevClient({ call: async () => { throw new Error("private upstream detail"); } });
  const prepared = prepareJevDecision({ goal: "Open Courses", state: state() });
  await assert.rejects(failed.choose({ state: prepared.state, criteria: prepared.criteria }, new AbortController().signal), {
    message: "Jev decision request failed.",
  });
});

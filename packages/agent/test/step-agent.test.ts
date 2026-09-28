import assert from "node:assert/strict";
import test from "node:test";
import type { ActionResult, ComputerAction, ComputerController, ComputerState, UIElement } from "../../shared/src/types.js";
import { createAgent, createDeepSeekStepChooser, parseStep } from "../src/index.js";
import type { Step, StepChooser } from "../src/index.js";

const control = (id: string, role: string, label: string): UIElement => ({ id, role, label, enabled: true, actions: role.startsWith("AXText") || role === "AXSearchField" ? [] : ["AXPress"] });

/** A Mac whose front window moves to the next screen after each action, like a real app responding. */
class ScriptedMac implements ComputerController {
  readonly actions: ComputerAction[] = [];
  private index = 0;
  constructor(private readonly screens: Array<Omit<ComputerState, "accessibilityTrusted" | "truncated">>) {}
  async getState(): Promise<ComputerState> {
    return { ...structuredClone(this.screens[Math.min(this.index, this.screens.length - 1)]!), accessibilityTrusted: true, truncated: false };
  }
  async execute(action: ComputerAction): Promise<ActionResult> {
    this.actions.push(structuredClone(action));
    this.index++;
    return { success: true };
  }
}

const monoCode = { activeApp: "MonoCode", activeWindow: "Workspace", elements: [control("m1", "AXButton", "New session")] };
const edgeOnYouTube = { activeApp: "Microsoft Edge", activeWindow: "lo-fi music - YouTube", elements: [control("a1", "AXTextField", "Address and search bar"), control("a2", "AXLink", "Chill Lofi Beats")] };
const hackerNews = { activeApp: "Microsoft Edge", activeWindow: "Hacker News", elements: [control("h1", "AXTextField", "Address and search bar"), control("h2", "AXLink", "new")] };

/** Plays back the steps a person would take, and records what the chooser was shown. */
function scripted(steps: Step[], seen: Array<{ app: string; taken: string[] }> = []): StepChooser {
  let index = 0;
  return async (_request, screen, taken) => {
    seen.push({ app: screen.app, taken: taken.map(entry => `${entry.step} → ${entry.result}${entry.screenChanged ? "" : " (no change)"}`) });
    return steps[Math.min(index++, steps.length - 1)]!;
  };
}

test("steps are parsed strictly", () => {
  assert.deepEqual(parseStep({ step: "type", id: "a1", text: "news.ycombinator.com", enter: true }), { step: "type", id: "a1", text: "news.ycombinator.com", enter: true });
  assert.deepEqual(parseStep({ step: "key", key: "CMD+L" }), { step: "key", key: "cmd+l" });
  assert.deepEqual(parseStep({ step: "done", summary: "Hacker News is showing." }), { step: "done", summary: "Hacker News is showing." });
  for (const reply of [
    { step: "key", key: "cmd+q" },
    { step: "key", key: "enter" },
    { step: "key", key: "space" },
    { step: "type", id: "a1", text: "rm -rf ~\n" },
    { step: "open_app", app: "/bin/zsh" },
    { step: "run_shell", command: "ls" },
    "click a1",
  ]) {
    assert.throws(() => parseStep(reply), /can’t take/, JSON.stringify(reply));
  }
});

test("opening a site works like a person: open the browser, type the address, check the page", async () => {
  const mac = new ScriptedMac([monoCode, edgeOnYouTube, hackerNews]);
  const seen: Array<{ app: string; taken: string[] }> = [];
  const waits: number[] = [];
  const agent = createAgent(mac, {
    wait: async ms => { waits.push(ms); },
    resolveIntent: async () => "UNKNOWN",
    chooseStep: scripted([
      { step: "open_app", app: "Microsoft Edge" },
      { step: "type", id: "a1", text: "news.ycombinator.com", enter: true },
      { step: "done", summary: "Hacker News is showing in Microsoft Edge." },
    ], seen),
  });
  assert.deepEqual(await agent.submit({ source: "voice", text: "open up my browser and check why combinator news" }),
    { success: true, message: "Hacker News is showing in Microsoft Edge." });
  assert.deepEqual(mac.actions, [
    { type: "launch_app", app: "Microsoft Edge" },
    { type: "type_text", target: "a1", text: "news.ycombinator.com\n" },
  ]);
  assert.deepEqual(seen, [
    { app: "MonoCode", taken: [] },
    { app: "Microsoft Edge", taken: ["open_app Microsoft Edge → ok"] },
    { app: "Microsoft Edge", taken: ["open_app Microsoft Edge → ok", "type \"news.ycombinator.com\" into a1 and press Return → ok"] },
  ]);
  assert.deepEqual(waits, [], "a ready screen should not incur a fixed pause");
});

test("a stale screen after an action is reread before asking for another decision", async () => {
  let reads = 0;
  let acted = false;
  const mac: ComputerController = {
    async getState() {
      reads++;
      const screen = !acted || reads === 2 ? monoCode : edgeOnYouTube;
      return { ...structuredClone(screen), accessibilityTrusted: true, truncated: false };
    },
    async execute() { acted = true; return { success: true }; },
  };
  const seen: string[] = [];
  const waits: number[] = [];
  const agent = createAgent(mac, {
    wait: async ms => { waits.push(ms); },
    resolveIntent: async () => "UNKNOWN",
    chooseStep: async (_request, screen) => {
      seen.push(screen.app);
      return screen.app === "MonoCode"
        ? { step: "open_app", app: "Microsoft Edge" }
        : { step: "done", summary: "Edge is ready." };
    },
  });
  assert.deepEqual(await agent.submit({ source: "text", text: "open my browser" }), { success: true, message: "Edge is ready." });
  assert.deepEqual(seen, ["MonoCode", "Microsoft Edge"]);
  assert.equal(waits.length, 1);
  assert.ok(waits[0]! <= 200);
});

test("an action that never changes the screen returns control to the chooser", async () => {
  const mac = new ScriptedMac([monoCode]);
  const seen: string[] = [];
  const agent = createAgent(mac, {
    wait: async () => {},
    resolveIntent: async () => "UNKNOWN",
    chooseStep: async (_request, screen, taken) => {
      seen.push(screen.app);
      return taken.length
        ? { step: "stop", reason: "The app did not change." }
        : { step: "open_app", app: "Microsoft Edge" };
    },
  });
  assert.deepEqual(await agent.submit({ source: "text", text: "open my browser" }),
    { success: false, error: "The app did not change." });
  assert.deepEqual(seen, ["MonoCode", "MonoCode"]);
  assert.equal(mac.actions.length, 1);
});

test("read-only display text lets Nora verify a Calculator result without clicking again", async () => {
  const display = (value: string) => ({ id: "display", role: "AXStaticText", label: value, enabled: true, actions: [] });
  const before = { activeApp: "Calculator", activeWindow: "Calculator", elements: [display("0"), control("b2", "AXButton", "2")] };
  const after = { activeApp: "Calculator", activeWindow: "Calculator", elements: [display("2"), control("b2", "AXButton", "2")] };
  const mac = new ScriptedMac([before, after]);
  const waits: number[] = [];
  const agent = createAgent(mac, {
    wait: async ms => { waits.push(ms); },
    resolveIntent: async () => "UNKNOWN",
    chooseStep: async (_request, screen) => screen.visibleText?.includes("2")
      ? { step: "done", summary: "Calculator shows 2." }
      : { step: "click", id: "b2" },
  });
  assert.deepEqual(await agent.submit({ source: "text", text: "Press 2 in Calculator" }),
    { success: true, message: "Calculator shows 2." });
  assert.deepEqual(mac.actions, [{ type: "click", target: "b2" }]);
  assert.deepEqual(waits, []);
});

test("a step that fails or changes nothing is reported back so the next step can adapt", async () => {
  const mac = new ScriptedMac([edgeOnYouTube, hackerNews]);
  const seen: Array<{ app: string; taken: string[] }> = [];
  const agent = createAgent(mac, {
    wait: async () => {},
    resolveIntent: async () => "UNKNOWN",
    chooseStep: scripted([
      { step: "click", id: "zz9" },
      { step: "type", id: "a1", text: "news.ycombinator.com", enter: true },
      { step: "done", summary: "Hacker News is showing." },
    ], seen),
  });
  assert.equal((await agent.submit({ source: "text", text: "go to hacker news" })).success, true);
  assert.deepEqual(seen[1]!.taken, ["click zz9 → DeepSeek picked control zz9, which isn’t on screen. (no change)"]);
});

test("typing in a terminal, Return in a message box, and risky buttons ask first", async () => {
  const cases: Array<[Omit<ComputerState, "accessibilityTrusted" | "truncated">, Step]> = [
    [{ activeApp: "Terminal", activeWindow: "zsh", elements: [control("t1", "AXTextArea", "shell")] }, { step: "type", id: "t1", text: "ls -la", enter: true }],
    [{ activeApp: "Slack", activeWindow: "general", elements: [control("s1", "AXTextArea", "Message #general")] }, { step: "type", id: "s1", text: "hi team", enter: true }],
    [{ activeApp: "Microsoft Edge", activeWindow: "YouTube", elements: [control("b1", "AXButton", "Subscribe")] }, { step: "click", id: "b1" }],
  ];
  for (const [screen, step] of cases) {
    const mac = new ScriptedMac([screen]);
    const agent = createAgent(mac, { wait: async () => {}, resolveIntent: async () => "UNKNOWN", chooseStep: scripted([step]) });
    const result = await agent.submit({ source: "text", text: "do it" });
    assert.equal("requiresConfirmation" in result && result.requiresConfirmation, true, screen.activeApp);
    assert.deepEqual(mac.actions, [], screen.activeApp);
  }
});

test("a window that isn't ready is read again, and Jev's known tasks never reach the step loop", async () => {
  let reads = 0;
  const mac = new ScriptedMac([hackerNews]);
  const opening = Object.assign(mac, {
    async getState(): Promise<ComputerState> {
      if (reads++ === 0) throw new Error("The active app has no accessible window. Focus a window and try again.");
      return { ...hackerNews, accessibilityTrusted: true, truncated: false };
    },
  });
  let asked = 0;
  const agent = createAgent(opening, {
    wait: async () => {},
    resolveIntent: async text => text === "open canvas" ? "OPEN_CANVAS" : "UNKNOWN",
    chooseStep: async () => { asked++; return { step: "done", summary: "Hacker News is showing." }; },
  });
  assert.deepEqual(await agent.submit({ source: "text", text: "show hacker news" }), { success: true, message: "Hacker News is showing." });
  assert.equal((await agent.submit({ source: "text", text: "open canvas" })).success, true);
  assert.equal(asked, 1);
});

test("a windowless foreground app cannot receive a key or scroll before opening a window", async () => {
  const mac = new ScriptedMac([{ activeApp: "Finder", elements: [] }, edgeOnYouTube]);
  const agent = createAgent(mac, {
    wait: async () => {},
    resolveIntent: async () => "UNKNOWN",
    chooseStep: scripted([
      { step: "key", key: "cmd+t" },
      { step: "scroll", direction: "down" },
      { step: "open_app", app: "Microsoft Edge" },
      { step: "done", summary: "Edge is open." },
    ]),
  });
  assert.deepEqual(await agent.submit({ source: "text", text: "look at music in Edge" }), { success: true, message: "Edge is open." });
  assert.deepEqual(mac.actions, [{ type: "launch_app", app: "Microsoft Edge" }]);
});

test("the chooser asks deepseek-flash for one JSON step, with reasoning off or low", async () => {
  let sent: Record<string, unknown> = {};
  const choose = createDeepSeekStepChooser({
    apiKey: "key",
    apps: ["Microsoft Edge"],
    fetch: async (_url, init) => {
      sent = JSON.parse(String(init?.body));
      return Response.json({ choices: [{ message: { content: JSON.stringify({ step: "open_app", app: "Microsoft Edge" }) } }] });
    },
  });
  const step = await choose("open edge", { app: "MonoCode", controls: [], more: false }, [], new AbortController().signal);
  assert.deepEqual(step, { step: "open_app", app: "Microsoft Edge" });
  assert.equal(sent.model, "deepseek-flash");
  assert.deepEqual(sent.thinking, { type: "disabled" });
  const low = createDeepSeekStepChooser({
    apiKey: "key",
    reasoning: "low",
    fetch: async (_url, init) => {
      sent = JSON.parse(String(init?.body));
      return Response.json({ choices: [{ message: { content: JSON.stringify({ step: "wait" }) } }] });
    },
  });
  await low("open edge", { app: "MonoCode", controls: [], more: false }, [], new AbortController().signal);
  assert.deepEqual(sent.thinking, { type: "enabled", reasoning_effort: "low" });
  assert.deepEqual(sent.response_format, { type: "json_object" });
});

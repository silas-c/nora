import { fileURLToPath } from "node:url";
import type { ActionResult, AgentHistoryEntry, ComputerAction, ComputerState } from "../../shared/src/types.js";
import { ActionHistory } from "./history.js";
import { ActionGate } from "./safety.js";
import { CanvasMockComputerController } from "./canvas-mock-controller.js";
import { BoundedJevChooser, type NextActionChooser } from "./jev.js";
import { TypeSafeJevClient } from "./typesafe-jev-client.js";
import { runComputerLoop, type ComputerLoopOptions, type ModelActionContext } from "./computer-loop.js";

const normalize = (value: string | undefined) => value?.trim().toLowerCase().replace(/\s+/g, " ") ?? "";

export function isSafeMockCoursesNavigation(action: ComputerAction, context: ModelActionContext): boolean {
  if (normalize(context.goal) !== "open courses" || context.state.activeApp !== "Microsoft Edge" || action.type !== "click") return false;
  const target = context.state.elements.find(element => element.id === action.target);
  return normalize(target?.label) === "courses"
    && target?.enabled === true
    && target.actions.includes("AXPress")
    && ["AXLink", "AXButton", "AXTab", "AXMenuItem"].includes(target.role);
}

export interface JevMockDemoResult {
  result: Awaited<ReturnType<typeof runComputerLoop>>;
  history: AgentHistoryEntry[];
}

export async function runJevMockDemo(
  goal: string,
  chooser: NextActionChooser,
  signal: AbortSignal,
  write: (value: object) => void = value => console.log(JSON.stringify(value)),
  options: Pick<ComputerLoopOptions, "wait" | "observationDelayMs"> = {},
): Promise<JevMockDemoResult> {
  const computer = new CanvasMockComputerController();
  const history = new ActionHistory();
  const recordedComputer = {
    getState: () => computer.getState(),
    execute: (action: ComputerAction) => history.record(action, () => computer.execute(action)),
  };
  const gate = new ActionGate(recordedComputer, event => write({ kind: "agent_event", event }), signal);
  try {
    write({ kind: "demo", mode: "synthetic_mock", native: false, goal });
    const result = await runComputerLoop(
      goal,
      recordedComputer,
      chooser,
      async (action, context): Promise<ActionResult> => {
        const gated = await gate.run({
          action,
          context: context.state,
          effect: isSafeMockCoursesNavigation(action, context) ? "navigation" : "unknown",
          actingMessage: "Executing the bounded mock action…",
          doneMessage: "Mock action completed.",
        });
        if (gated.success) return { success: true };
        return {
          success: false,
          error: gated.requiresConfirmation
            ? "The model-selected action requires confirmation; the mock demo executed nothing."
            : gated.error,
        };
      },
      signal,
      {
        ...options,
        onObservation: (state: ComputerState, observation) => write({
          kind: "observation", observation, activeApp: state.activeApp,
          activeWindow: state.activeWindow, controls: state.elements.length,
        }),
        onDecision: (decision, observation) => write({ kind: "jev_decision", observation, decision }),
      },
    );
    const output = { result, history: history.read() };
    write({ kind: "result", ...output, native: false });
    return output;
  } finally {
    gate.dispose();
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0 || args.some(arg => arg.startsWith("--"))) {
    throw new Error('Usage: npm run jev:demo -- "Open Courses"');
  }
  const goal = args.join(" ").trim();
  if (!goal) throw new Error("A nonempty demo goal is required.");

  const lifecycle = new AbortController();
  const cancel = () => lifecycle.abort();
  process.once("SIGINT", cancel);
  process.once("SIGTERM", cancel);
  try {
    const { result } = await runJevMockDemo(
      goal,
      new BoundedJevChooser(new TypeSafeJevClient()),
      lifecycle.signal,
    );
    if (!result.success) process.exitCode = 1;
  } finally {
    lifecycle.abort();
    process.off("SIGINT", cancel);
    process.off("SIGTERM", cancel);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Jev mock demo failed.");
    process.exitCode = 1;
  }
}

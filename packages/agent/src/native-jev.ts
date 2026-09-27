import { setTimeout as delay } from "node:timers/promises";
import type {
  ActionResult, AgentHistoryEntry, ComputerAction, ComputerController, ComputerState, PendingConfirmation,
} from "../../shared/src/types.js";
import { ActionHistory } from "./history.js";
import { ActionGate } from "./safety.js";
import { runComputerLoop, type ComputerLoopResult, type ModelActionContext } from "./computer-loop.js";
import type { NextActionChooser } from "./jev.js";

export const NATIVE_JEV_CANVAS_URL = "https://canvas.temple.edu";

export interface NativeJevOptions {
  url?: string;
  waitAfterOpen?: (signal: AbortSignal) => Promise<void>;
  waitBetweenObservations?: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  confirm?: (prompt: PendingConfirmation, context: ModelActionContext) => Promise<boolean>;
  write?: (value: object) => void;
}

export interface NativeJevResult {
  result: ComputerLoopResult;
  history: AgentHistoryEntry[];
}

const normalize = (value: string | undefined) => value?.trim().toLowerCase().replace(/\s+/g, " ") ?? "";
const PROHIBITED_LABEL = /\b(delete|remove|submit|send|save|purchase|buy|checkout|download|upload|account|password|pay|post|publish|sign\s*out|log\s*out)\b/i;
const COURSES_LABEL = /\bcourses?\b/i;

export function isNativeCoursesDestination(state: ComputerState): boolean {
  const window = normalize(state.activeWindow);
  return window.startsWith("courses - canvas")
    || window.startsWith("all courses - canvas")
    || state.elements.some(element => normalize(element.label) === "all courses");
}

export function scopeNativeJevState(state: ComputerState): ComputerState {
  return {
    ...structuredClone(state),
    elements: state.elements.filter(element => COURSES_LABEL.test(element.label ?? "")),
  };
}

export function isAllowedNativeJevURL(rawURL: string): boolean {
  try {
    const url = new URL(rawURL);
    return (url.protocol === "https:" && url.hostname === "canvas.temple.edu")
      || (url.protocol === "http:" && ["127.0.0.1", "localhost", "::1"].includes(url.hostname));
  } catch { return false; }
}

function selectedElement(action: ComputerAction, context: ModelActionContext) {
  return action.type === "click" ? context.state.elements.find(element => element.id === action.target) : undefined;
}

export function isSafeNativeCoursesNavigation(action: ComputerAction, context: ModelActionContext): boolean {
  const target = selectedElement(action, context);
  return normalize(context.goal) === "open courses"
    && context.state.activeApp === "Microsoft Edge"
    && normalize(target?.label) === "courses"
    && target?.enabled === true
    && target.actions.includes("AXPress")
    && ["AXLink", "AXButton", "AXTab", "AXMenuItem"].includes(target.role);
}

export async function runNativeJev(
  goal: string,
  computer: ComputerController,
  chooser: NextActionChooser,
  signal: AbortSignal,
  options: NativeJevOptions = {},
): Promise<NativeJevResult> {
  if (normalize(goal) !== "open courses") {
    return { result: { success: false, error: 'Native Jev is currently limited to the exact goal “Open Courses”.' }, history: [] };
  }
  const url = options.url ?? NATIVE_JEV_CANVAS_URL;
  if (!isAllowedNativeJevURL(url)) {
    return { result: { success: false, error: "Native Jev only allows Temple Canvas or a loopback test page." }, history: [] };
  }
  const write = options.write ?? (value => console.log(JSON.stringify(value)));
  const history = new ActionHistory();
  const recorded: ComputerController = {
    getState: async () => scopeNativeJevState(await computer.getState()),
    execute: action => history.record(action, () => computer.execute(action)),
    ...(computer.executeValidated ? {
      executeValidated: (action: ComputerAction, expected: ComputerState) =>
        history.record(action, () => computer.executeValidated!(action, expected)),
    } : {}),
  };
  const gate = new ActionGate(recorded, event => write({ kind: "agent_event", event }), signal);
  const goalAwareChooser: NextActionChooser = {
    choose: (input, chooseSignal) => isNativeCoursesDestination(input.state)
      ? Promise.resolve({ type: "done", confidence: 1 })
      : chooser.choose(input, chooseSignal),
  };
  try {
    signal.throwIfAborted();
    write({ kind: "native_jev", goal, url, limits: { actions: 5, observations: 15 }, native: true });
    const opened = await recorded.execute({ type: "open_url", url, browser: "Microsoft Edge" });
    if (!opened.success) return { result: opened, history: history.read() };
    await (options.waitAfterOpen ?? (waitSignal => delay(1_500, undefined, { signal: waitSignal })))(signal);
    const result = await runComputerLoop(
      goal,
      recorded,
      goalAwareChooser,
      async (action, context): Promise<ActionResult> => {
        const target = selectedElement(action, context);
        write({
          kind: "proposed_action", action, confidence: context.confidence,
          target: target && { role: target.role, label: target.label },
        });
        if (!target || PROHIBITED_LABEL.test(target.label ?? "")) {
          return { success: false, error: "The selected control is outside the native Jev navigation-only scope." };
        }
        const gated = await gate.run({
          action,
          context: context.state,
          effect: isSafeNativeCoursesNavigation(action, context) ? "navigation" : "unknown",
          actingMessage: `Activate ${target.role} ${JSON.stringify(target.label ?? "unlabeled control")}`,
          doneMessage: "Native navigation action completed.",
        });
        if (gated.success) return { success: true };
        if (!gated.requiresConfirmation) return gated;
        if (!options.confirm) return { success: false, error: "The model-selected action requires explicit confirmation." };
        const approved = await options.confirm(gated, context);
        const resolved = await gate.confirm(gated.confirmationId, approved);
        if (!approved) return { success: false, error: "The model-selected action was cancelled." };
        if (resolved.success) return { success: true };
        return {
          success: false,
          error: resolved.requiresConfirmation ? "Confirmation did not resolve the model-selected action." : resolved.error,
        };
      },
      signal,
      {
        maxActions: 5,
        maxObservations: 15,
        wait: options.waitBetweenObservations,
        validateState: state => state.activeApp === "Microsoft Edge"
          ? undefined : "Native Jev stopped because Microsoft Edge is not the active application.",
        onObservation: (state, observation) => write({
          kind: "observation", observation, activeApp: state.activeApp,
          activeWindow: state.activeWindow, controls: state.elements.length,
        }),
        onDecision: (decision, observation) => write({ kind: "jev_decision", observation, decision }),
      },
    );
    const output = { result, history: history.read() };
    write({ kind: "result", ...output, native: true });
    return output;
  } catch (error) {
    const result: ComputerLoopResult = {
      success: false,
      error: signal.aborted ? "The native Jev task was cancelled." : error instanceof Error ? error.message : "Native Jev failed.",
    };
    return { result, history: history.read() };
  } finally {
    gate.dispose();
  }
}

import type { ActionResult, Agent, AgentEvent, AgentResult, ComputerAction, ComputerController, UserInput } from "../../shared/src/types.js";
import { routeIntent } from "./router.js";
import type { Intent } from "./router.js";
import { skills, type Skill } from "./skills.js";
import { runSteps, type StepChooser } from "./step-agent.js";
import { navigateClass, navigateCourses, type CourseChooser, type NavigationOptions } from "./navigation.js";
import { ActionGate } from "./safety.js";
import { ActionHistory } from "./history.js";

export interface AgentOptions extends Pick<NavigationOptions, "wait"> {
  /** Trusted test/embedding hook; never accepted in the JSON-lines protocol. */
  resolveSkill?: (input: UserInput) => Skill | undefined;
  resolveIntent?: (text: string, signal: AbortSignal) => Promise<Intent>;
  /** Matches a spoken class name to one visible Canvas course; required for OPEN_CLASS. */
  chooseCourse?: CourseChooser;
  /** Chooses one step at a time, from what is on screen, for text and voice requests that match no built-in task. */
  chooseStep?: StepChooser;
  /** Receives each screen reading and chosen step of a step-by-step request, for the local run log. */
  trace?: (entry: Record<string, unknown>) => void;
  /** Clock injection for expiration tests. Production uses Date.now. */
  now?: () => number;
}

export function createAgent(computer: ComputerController, options: AgentOptions = {}): Agent {
  const lifecycle = new AbortController();
  const history = new ActionHistory(options.now);
  const recordedComputer: ComputerController = {
    getState: () => computer.getState(),
    execute: action => history.record(action, () => computer.execute(action)),
    ...(computer.executeValidated ? {
      executeValidated: (action: Parameters<NonNullable<ComputerController["executeValidated"]>>[0], expected: Parameters<NonNullable<ComputerController["executeValidated"]>>[1]) =>
        history.record(action, () => computer.executeValidated!(action, expected)),
    } : {}),
  };
  const listeners = new Set<(event: AgentEvent) => void>();
  let busy = false;
  function emit(event: AgentEvent): void {
    if (lifecycle.signal.aborted) return;
    for (const listener of [...listeners]) {
      try { listener(structuredClone(event)); } catch { /* One UI subscriber must not break execution. */ }
    }
  }
  const gate = new ActionGate(recordedComputer, emit, lifecycle.signal, options.now);
  function finish(result: AgentResult): AgentResult {
    if (result.success) emit({ type: "done", message: result.message });
    else if (!result.requiresConfirmation) emit({ type: "error", message: result.error });
    return result;
  }
  const fail = (error: string) => finish({ success: false, error });
  const closed = (): AgentResult => ({ success: false, error: "Agent session is closed." });
  const occupied = (): AgentResult => ({ success: false, error: "An action is already running. Please wait." });
  return {
    getHistory: () => history.read(),
    clearHistory: () => history.clear(),
    dispose() { lifecycle.abort(); gate.dispose(); history.dispose(); listeners.clear(); },
    subscribe(callback) {
      listeners.add(callback);
      return () => { listeners.delete(callback); };
    },
    async confirm(id, approved) {
      if (lifecycle.signal.aborted) return closed();
      if (busy) return occupied();
      busy = true;
      try { return finish(await gate.confirm(id, approved)); }
      catch (error) { return fail(error instanceof Error ? error.message : "Confirmation failed."); }
      finally { busy = false; }
    },
    async submit(input) {
      if (lifecycle.signal.aborted) return closed();
      if (busy) return occupied();
      if (gate.hasPending()) return { success: false, error: "Confirm or cancel the pending action first." };
      busy = true;
      const stepByStep = input.source !== "aac" && !!options.chooseStep;
      try {
        emit({ type: "thinking" });
        let intent: Intent;
        try {
          const local = routeIntent(input);
          intent = input.source === "aac" || local !== "UNKNOWN" || !options.resolveIntent
            ? local
            : await options.resolveIntent(input.text, lifecycle.signal);
        } catch (error) {
          // Jev being unavailable should not block a request Nora can still work through step by step.
          if (!stepByStep) throw error;
          intent = "UNKNOWN";
        }
        const navigate = async (action: ComputerAction): Promise<ActionResult> => {
          const result = await gate.run({ action, effect: "navigation", actingMessage: "", doneMessage: "Navigation action accepted." });
          if (result.success) return { success: true };
          return { success: false, error: result.requiresConfirmation ? "Navigation requires confirmation." : result.error };
        };
        if (intent === "OPEN_COURSES") {
          return finish(await navigateCourses(recordedComputer, navigate, emit, lifecycle.signal, options));
        }
        if (intent === "OPEN_CLASS") {
          if (input.source === "aac" || !options.chooseCourse) return fail("Opening a class by name needs Jev. Try “Open Canvas and go to Courses”.");
          return finish(await navigateClass(recordedComputer, navigate, emit, lifecycle.signal, input.text, options.chooseCourse, options));
        }
        if (intent === "UNKNOWN" && stepByStep) {
          return finish(await runSteps(input.text, recordedComputer, options.chooseStep!, proposal => gate.run(proposal), emit,
            lifecycle.signal, { ...(options.wait ? { wait: options.wait } : {}), ...(options.trace ? { trace: options.trace } : {}) }));
        }
        const skill = intent === "UNKNOWN" ? options.resolveSkill?.(input) : skills[intent];
        if (!skill) return fail('Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”.');
        return finish(await gate.run(skill));
      } catch (error) {
        return fail(error instanceof Error ? error.message : "The computer action failed.");
      } finally { busy = false; }
    },
  };
}

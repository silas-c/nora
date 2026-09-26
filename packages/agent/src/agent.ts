import type { Agent, AgentEvent, AgentResult, ComputerController, UserInput } from "../../shared/src/types.js";
import { routeIntent } from "./router.js";
import { skills } from "./skills.js";
import { navigateCourses, type NavigationOptions } from "./navigation.js";

export function createAgent(computer: ComputerController, options: Pick<NavigationOptions, "wait"> = {}): Agent {
  const lifecycle = new AbortController();
  const listeners = new Set<(event: AgentEvent) => void>();
  let busy = false;
  function emit(event: AgentEvent): void {
    if (lifecycle.signal.aborted) return;
    for (const listener of [...listeners]) {
      // A UI listener must not turn a successful computer action into a failure.
      try { listener(event); } catch { /* Other listeners still receive the event. */ }
    }
  }
  function fail(error: string): AgentResult {
    emit({ type: "error", message: error });
    return { success: false, error };
  }
  return {
    dispose() { lifecycle.abort(); listeners.clear(); },
    subscribe(callback) {
      listeners.add(callback);
      return () => { listeners.delete(callback); };
    },
    async submit(input) {
      if (lifecycle.signal.aborted) return { success: false, error: "Agent session is closed." };
      // Do not interleave status events or launch duplicate actions while busy.
      if (busy) return { success: false, error: "An action is already running. Please wait." };
      busy = true;
      try {
        emit({ type: "thinking" });
        const intent = routeIntent(input);
        if (intent === "UNKNOWN") return fail('Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”.');
        if (intent === "OPEN_COURSES") {
          const result = await navigateCourses(computer, action => computer.execute(action), emit, lifecycle.signal, options);
          if (!result.success) return fail(result.error);
          emit({ type: "done", message: result.message });
          return result;
        }
        const skill = skills[intent];
        emit({ type: "acting", message: skill.actingMessage });
        const result = await computer.execute(structuredClone(skill.action));
        if (lifecycle.signal.aborted) return { success: false, error: "Agent session is closed." };
        if (!result.success) return fail(result.error);
        emit({ type: "done", message: skill.doneMessage });
        return { success: true, message: skill.doneMessage };
      } catch (error) {
        return fail(error instanceof Error ? error.message : "The computer action failed.");
      } finally {
        busy = false;
      }
    },
  };
}

import type { Agent, AgentEvent, AgentResult, ComputerController, UserInput } from "../../shared/src/types.js";
import { routeIntent } from "./router.js";
import { skills } from "./skills.js";

export function createAgent(computer: ComputerController): Agent {
  const listeners = new Set<(event: AgentEvent) => void>();
  let busy = false;
  function emit(event: AgentEvent): void {
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
    subscribe(callback) {
      listeners.add(callback);
      return () => { listeners.delete(callback); };
    },
    async submit(input) {
      // Do not interleave status events or launch duplicate actions while busy.
      if (busy) return { success: false, error: "An action is already running. Please wait." };
      busy = true;
      try {
        emit({ type: "thinking" });
        const intent = routeIntent(input);
        if (intent === "UNKNOWN") return fail('Try “Open Canvas”, “Show me dog photos”, or “Make text bigger”.');
        const skill = skills[intent];
        emit({ type: "acting", message: skill.actingMessage });
        const result = await computer.execute(structuredClone(skill.action));
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

import type { Agent } from "../../shared/src/types.js";
import { createAgent, type AgentOptions } from "./agent.js";
import { MockComputerController } from "./mock-controller.js";
import type { Skill } from "./skills.js";

/** Accepted only by the dedicated mock demo server; production routing is unchanged. */
export const CONFIRMATION_DEMO_INTENT = "TEST_ONLY_DELETE";

const simulatedDestructiveSkill: Skill = {
  action: { type: "launch_app", app: "Mock deletion executor" },
  effect: "deletion",
  actingMessage: "Simulate deleting a disposable example item",
  doneMessage: "Simulation completed. No real data was changed.",
};

export interface ConfirmationDemoSession {
  agent: Agent;
  computer: MockComputerController;
}

/**
 * Creates an isolated, mock-only confirmation session. The simulated intent and
 * action are never registered with the production server or native controller.
 */
export function createConfirmationDemoSession(
  options: Pick<AgentOptions, "now"> = {},
): ConfirmationDemoSession {
  const computer = new MockComputerController();
  const agent = createAgent(computer, {
    ...options,
    resolveSkill: input => input.source === "aac" && input.intent === CONFIRMATION_DEMO_INTENT
      ? simulatedDestructiveSkill
      : undefined,
  });
  return { agent, computer };
}

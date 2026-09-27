import { setTimeout as delay } from "node:timers/promises";
import type { ActionResult, ComputerAction, ComputerController, ComputerState } from "../../shared/src/types.js";
import type { JevDecision, JevDecisionInput, NextActionChooser } from "./jev.js";

export interface ModelActionContext {
  goal: string;
  state: ComputerState;
  confidence: number;
}

export interface ComputerLoopOptions {
  maxActions?: number;
  maxObservations?: number;
  maxUnchangedObservations?: number;
  wait?: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  observationDelayMs?: number;
  onObservation?: (state: ComputerState, observation: number) => void;
  onDecision?: (decision: JevDecision, observation: number) => void;
  validateState?: (state: ComputerState) => string | undefined;
}

export type ComputerLoopResult = ActionResult & { message?: string };

const fail = (error: string): ComputerLoopResult => ({ success: false, error });

function stateFingerprint(state: ComputerState): string {
  return JSON.stringify({
    activeApp: state.activeApp,
    activeWindow: state.activeWindow,
    accessibilityTrusted: state.accessibilityTrusted,
    truncated: state.truncated,
    elements: state.elements.map(({ role, label, enabled, actions }) => ({ role, label, enabled, actions })),
  });
}

function validateSelectedAction(action: ComputerAction, state: ComputerState): string | undefined {
  if (action.type !== "click") return "Jev selected an unsupported action; no action was executed.";
  const target = state.elements.find(element => element.id === action.target);
  if (!target?.enabled || !target.actions.includes("AXPress")) {
    return "Jev selected an unavailable or stale control; no action was executed.";
  }
  if (state.snapshotGeneration && action.snapshotGeneration !== state.snapshotGeneration) {
    return "Jev selected a control from a stale snapshot; no action was executed.";
  }
  return undefined;
}

/**
 * Mock-first bounded computer-use loop. The caller-supplied executor must route
 * model-selected actions through the normal safety and history boundary.
 */
export async function runComputerLoop(
  goal: string,
  computer: Pick<ComputerController, "getState">,
  chooser: NextActionChooser,
  executeModelAction: (action: ComputerAction, context: ModelActionContext) => Promise<ActionResult>,
  signal: AbortSignal,
  options: ComputerLoopOptions = {},
): Promise<ComputerLoopResult> {
  const maxActions = options.maxActions ?? 5;
  const maxObservations = options.maxObservations ?? 15;
  const maxUnchanged = options.maxUnchangedObservations ?? 3;
  const wait = options.wait ?? ((milliseconds, waitSignal) => delay(milliseconds, undefined, { signal: waitSignal }));
  const observationDelayMs = options.observationDelayMs ?? 300;
  if (!Number.isInteger(maxActions) || maxActions < 1 || maxActions > 10
    || !Number.isInteger(maxObservations) || maxObservations < 2 || maxObservations > 50
    || !Number.isInteger(maxUnchanged) || maxUnchanged < 1 || maxUnchanged > 10
    || !Number.isFinite(observationDelayMs) || observationDelayMs < 0 || observationDelayMs > 5_000) {
    throw new RangeError("Invalid bounded computer-loop options.");
  }

  let actionsTaken = 0;
  let observations = 0;
  let expectedApp: string | undefined;
  let awaitingChange: string | undefined;
  let unchangedObservations = 0;
  try {
    while (observations < maxObservations) {
      signal.throwIfAborted();
      const state = await computer.getState();
      observations++;
      signal.throwIfAborted();
      options.onObservation?.(structuredClone(state), observations);
      if (!state.accessibilityTrusted) return fail("Accessibility permission is required before Jev can inspect controls.");
      if (state.truncated) return fail("The accessibility snapshot is incomplete; no action was executed.");
      const stateProblem = options.validateState?.(structuredClone(state));
      if (stateProblem) return fail(stateProblem);
      if (expectedApp === undefined) expectedApp = state.activeApp;
      else if (state.activeApp !== expectedApp) return fail("The active application changed during the Jev task; no further action was executed.");

      const fingerprint = stateFingerprint(state);
      if (awaitingChange === fingerprint) {
        unchangedObservations++;
        if (unchangedObservations >= maxUnchanged) {
          return fail("The screen did not change after the last action. Check the application and try again.");
        }
        await wait(observationDelayMs, signal);
        continue;
      }
      awaitingChange = undefined;
      unchangedObservations = 0;

      const decision = await chooser.choose({ goal, state } satisfies JevDecisionInput, signal);
      signal.throwIfAborted();
      options.onDecision?.(structuredClone(decision), observations);
      if (decision.type === "done") return { success: true, message: "The visible state satisfies the goal." };
      if (decision.type === "ask_user") return fail(decision.reason === "low_confidence"
        ? "Jev was not confident enough to act. Clarify the goal and try again."
        : "Jev needs a user choice before it can continue.");
      if (decision.type === "blocked") return fail("No visible control can safely advance this task.");
      if (decision.type !== "action") return fail("Jev returned an unsupported decision; no action was executed.");
      if (actionsTaken >= maxActions) return fail("The Jev task reached its action limit before completion.");
      const invalid = validateSelectedAction(decision.action, state);
      if (invalid) return fail(invalid);
      const result = await executeModelAction(structuredClone(decision.action), {
        goal,
        state: structuredClone(state),
        confidence: decision.confidence,
      });
      signal.throwIfAborted();
      if (!result.success) return fail(result.error);
      actionsTaken++;
      awaitingChange = fingerprint;
      if (observations < maxObservations) await wait(observationDelayMs, signal);
    }
    return fail("The Jev task reached its observation limit before completion.");
  } catch (error) {
    return fail(signal.aborted
      ? "The Jev task was cancelled."
      : error instanceof Error ? error.message : "The Jev task could not inspect the computer.");
  }
}

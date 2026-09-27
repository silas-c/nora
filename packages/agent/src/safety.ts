import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentResult, ComputerAction, ComputerController, ComputerState, RiskLevel } from "../../shared/src/types.js";

export type ActionEffect = "navigation" | "zoom" | "input" | "text_entry" | "submission" | "deletion" | "unknown";
export interface ActionProposal {
  action: ComputerAction;
  effect?: ActionEffect;
  actingMessage: string;
  doneMessage: string;
  /** Trusted state captured when a model selected this target; never accepted over transport. */
  context?: ComputerState;
}

const INPUT_KEYS = new Set(["CMD+L", "CMD+T", "TAB", "SHIFT+TAB", "ESCAPE", "UP", "DOWN", "LEFT", "RIGHT"]);

export function classifyAction(action: ComputerAction, effect: ActionEffect = "unknown"): RiskLevel {
  if (effect === "deletion") return "destructive";
  if (effect === "navigation") {
    if (["launch_app", "focus_app", "click", "scroll"].includes(action.type)) return "safe";
    if (action.type === "open_url") {
      try { if (["http:", "https:"].includes(new URL(action.url).protocol)) return "safe"; } catch { /* confirmation required */ }
    }
  }
  if (effect === "zoom" && action.type === "keypress" && ["+", "-"].includes(action.key)
    && action.modifiers?.length === 1 && action.modifiers[0] === "CMD") return "safe";
  // One step of operating an app like a person: typing into a chosen field, clicking, scrolling, or a key that
  // moves around. Return is only pressed inside typed text, and the caller asks first when that could commit something.
  if (effect === "input") {
    if (["click", "scroll"].includes(action.type)) return "safe";
    if (action.type === "type_text" && action.target) return "safe";
    if (action.type === "keypress" && INPUT_KEYS.has([...(action.modifiers ?? []), action.key].join("+").toUpperCase())) return "safe";
  }
  return "sensitive";
}

const targetOf = (action: ComputerAction) => action.type === "click" || action.type === "type_text" ? action.target : undefined;
const failure = (error: string): AgentResult => ({ success: false, error });

/** Enforces one immutable, single-use approval. Only trusted skills supply effect metadata. */
export class ActionGate {
  private pending?: {
    id: string; proposal: ActionProposal; context?: ComputerState;
    expiresAt: number; timer: NodeJS.Timeout;
  };
  constructor(
    private readonly computer: ComputerController,
    private readonly emit: (event: AgentEvent) => void,
    private readonly signal: AbortSignal,
    private readonly now: () => number = Date.now,
  ) {}

  hasPending(): boolean { this.expire(); return !!this.pending; }

  private clear(reason: "approved" | "cancelled" | "expired" | "invalidated"): void {
    if (!this.pending) return;
    const { id, timer } = this.pending;
    this.pending = undefined;
    clearTimeout(timer);
    this.emit({ type: "confirmation_resolved", confirmationId: id, reason });
  }

  private expire(): void {
    if (this.pending && this.now() >= this.pending.expiresAt) this.clear("expired");
  }

  dispose(): void { this.clear("invalidated"); }

  async run(proposal: ActionProposal): Promise<AgentResult> {
    if (this.signal.aborted) return failure("Agent session is closed.");
    if (this.hasPending()) return failure("Confirm or cancel the pending action first.");
    // Freeze by ownership: no caller or event subscriber receives this private copy.
    const frozen = structuredClone(proposal);
    const risk = classifyAction(frozen.action, frozen.effect);
    if (risk === "safe") return this.execute(frozen);
    let context: ComputerState | undefined = frozen.context;
    const action = frozen.action;
    if (targetOf(action) || ["keypress", "type_text", "scroll"].includes(action.type)) {
      // Untargeted edits/keyboard events cannot be bound to a specific control with
      // the current helper contract. Fail closed rather than approve a moving focus.
      if (!targetOf(action)) return failure("This input action needs a specific target before it can be confirmed.");
      context ??= await this.computer.getState();
      if (!context.accessibilityTrusted || context.truncated) return failure("A complete accessible snapshot is required before confirmation.");
      const target = context.elements.find(e => e.id === targetOf(action));
      if (!target?.enabled) return failure("The action target is unavailable or stale. Select it again.");
      if (action.type === "click" && context.snapshotGeneration
        && action.snapshotGeneration !== context.snapshotGeneration) {
        return failure("The action target is from a stale snapshot. Select it again.");
      }
    }
    if (this.signal.aborted) return failure("Agent session is closed.");
    const id = randomUUID();
    const expiresAt = this.now() + 60_000;
    const timer = setTimeout(() => this.clear("expired"), 60_000);
    timer.unref();
    this.pending = { id, proposal: frozen, context: context && structuredClone(context), expiresAt, timer };
    const message = `${frozen.actingMessage} Action: ${JSON.stringify(frozen.action)}`;
    this.emit({ type: "confirmation_required", confirmationId: id, action: structuredClone(frozen.action), risk, expiresAt, message });
    return { success: false, requiresConfirmation: true, confirmationId: id, message };
  }

  async confirm(id: string, approved: boolean): Promise<AgentResult> {
    if (typeof approved !== "boolean") return failure("Confirmation requires an explicit boolean decision.");
    if (this.signal.aborted) return failure("Agent session is closed.");
    this.expire();
    const pending = this.pending;
    if (!pending || pending.id !== id) return failure("Confirmation is missing, expired, or already used.");
    if (!approved) {
      this.clear("cancelled");
      return { success: true, message: "Cancelled. No action was executed." };
    }
    // Consume before asynchronous validation/execution; repeated approvals cannot run it twice.
    this.pending = undefined;
    clearTimeout(pending.timer);
    let invalid: string | undefined;
    const atomicContext = pending.context && this.computer.executeValidated ? pending.context : undefined;
    if (pending.context && !atomicContext) {
      try {
        const current = await this.computer.getState();
        const oldTarget = pending.context.elements.find(e => e.id === targetOf(pending.proposal.action));
        const newTarget = current.elements.find(e => e.id === targetOf(pending.proposal.action));
        if (!current.accessibilityTrusted || current.truncated
          || current.activeApp !== pending.context.activeApp || current.activeWindow !== pending.context.activeWindow
          || !newTarget?.enabled || JSON.stringify(oldTarget) !== JSON.stringify(newTarget)) {
          invalid = "The target or window changed. Select the action again; no action was executed.";
        }
      } catch { invalid = "The action context could not be verified. Select the action again."; }
    }
    if (this.now() >= pending.expiresAt) invalid = "Confirmation expired while checking the action. No action was executed.";
    if (this.signal.aborted) invalid = "Agent session is closed.";
    if (invalid) {
      this.emit({ type: "confirmation_resolved", confirmationId: id, reason: "invalidated" });
      return failure(invalid);
    }
    this.emit({ type: "confirmation_resolved", confirmationId: id, reason: "approved" });
    return this.execute(pending.proposal, atomicContext);
  }

  private async execute(proposal: ActionProposal, expected?: ComputerState): Promise<AgentResult> {
    if (this.signal.aborted) return failure("Agent session is closed.");
    if (proposal.actingMessage) this.emit({ type: "acting", message: proposal.actingMessage });
    // A synchronous event subscriber may disconnect the session.
    if (this.signal.aborted) return failure("Agent session is closed.");
    const result = expected && this.computer.executeValidated
      ? await this.computer.executeValidated(structuredClone(proposal.action), structuredClone(expected))
      : await this.computer.execute(structuredClone(proposal.action));
    if (this.signal.aborted) return failure("Agent session is closed.");
    return result.success ? { success: true, message: proposal.doneMessage } : result;
  }
}

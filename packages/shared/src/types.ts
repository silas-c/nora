export type UserInput =
  | { source: "voice" | "text"; text: string }
  | { source: "aac"; intent: string };

export type ComputerAction =
  | { type: "open_url"; url: string; browser?: string }
  | { type: "launch_app" | "focus_app"; app: string }
  | { type: "click"; target: string; snapshotGeneration?: string }
  | { type: "type_text"; target?: string; snapshotGeneration?: string; text: string }
  | { type: "keypress"; key: string; modifiers?: string[] }
  | { type: "scroll"; direction: "up" | "down" | "left" | "right"; amount?: number };

export interface UIElement {
  id: string;
  role: string;
  label?: string;
  enabled: boolean;
  actions: string[];
}

export interface ComputerState {
  /** Required for native targeted actions; synthetic controllers may omit it. */
  snapshotGeneration?: string;
  activeApp: string;
  activeWindow?: string;
  accessibilityTrusted: boolean;
  elements: UIElement[];
  truncated: boolean;
}

export type ActionResult =
  | { success: true }
  | { success: false; error: string };

export interface ComputerController {
  /** Full snapshot; rejects if permission is denied or state is unavailable. */
  getState(): Promise<ComputerState>;
  execute(action: ComputerAction): Promise<ActionResult>;
  /** Atomically revalidates the captured context and executes one targeted action. */
  executeValidated?(action: ComputerAction, expected: ComputerState): Promise<ActionResult>;
}

export type RiskLevel = "safe" | "sensitive" | "destructive";

export type AgentEvent =
  | { type: "listening" }
  | { type: "thinking"; message?: string }
  | { type: "acting"; message: string }
  | { type: "confirmation_required"; message: string; confirmationId: string; action: ComputerAction; risk: RiskLevel; expiresAt: number }
  | { type: "confirmation_resolved"; confirmationId: string; reason: "approved" | "cancelled" | "expired" | "invalidated" }
  | { type: "done"; message?: string }
  | { type: "error"; message: string };

export type PendingConfirmation = { success: false; requiresConfirmation: true; confirmationId: string; message: string };

export type AgentResult =
  | { success: true; message?: string }
  | { success: false; error: string; requiresConfirmation?: false }
  | PendingConfirmation;

export interface AgentHistoryEntry {
  id: number;
  /** Redacted, display-only action summary. Never use it to replay actions. */
  action: ComputerAction;
  success: boolean;
  timestamp: number;
  completedAt: number;
}

export interface Agent {
  getHistory(): AgentHistoryEntry[];
  clearHistory(): void;
  /** Cancels pending work; the session owner also closes its controller. */
  dispose(): void;
  submit(input: UserInput): Promise<AgentResult>;
  confirm(confirmationId: string, approved: boolean): Promise<AgentResult>;
  subscribe(callback: (event: AgentEvent) => void): () => void;
}

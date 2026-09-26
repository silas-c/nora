export type UserInput =
  | { source: "voice" | "text"; text: string }
  | { source: "aac"; intent: string };

export type ComputerAction =
  | { type: "open_url"; url: string; browser?: string }
  | { type: "launch_app" | "focus_app"; app: string }
  | { type: "click"; target: string }
  | { type: "type_text"; target?: string; text: string }
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
}

export type AgentEvent =
  | { type: "listening" }
  | { type: "thinking"; message?: string }
  | { type: "acting"; message: string }
  | { type: "confirmation_required"; message: string; confirmationId: string }
  | { type: "done"; message?: string }
  | { type: "error"; message: string };

export type AgentResult =
  | { success: true; message?: string }
  | { success: false; error: string };

export interface Agent {
  /** Cancels pending work; the session owner also closes its controller. */
  dispose(): void;
  submit(input: UserInput): Promise<AgentResult>;
  subscribe(callback: (event: AgentEvent) => void): () => void;
}

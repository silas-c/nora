export type UserInput =
  | { source: "voice" | "text"; text: string }
  | { source: "aac"; intent: string };

export type ComputerAction = {
  type: "open_url";
  url: string;
  browser?: string;
};

export type ActionResult =
  | { success: true }
  | { success: false; error: string };

export interface ComputerController {
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
  submit(input: UserInput): Promise<AgentResult>;
  subscribe(callback: (event: AgentEvent) => void): () => void;
}

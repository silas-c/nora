import type { ActionResult, AgentHistoryEntry, ComputerAction } from "../../shared/src/types.js";

/** History is display-only: never retain typed content or URL credentials/path/query. */
function redact(action: ComputerAction): ComputerAction {
  const copy = structuredClone(action);
  if (copy.type === "type_text") copy.text = "[redacted]";
  if (copy.type === "open_url") {
    try {
      const url = new URL(copy.url);
      copy.url = ["http:", "https:"].includes(url.protocol) ? url.origin : "[redacted]";
    } catch { copy.url = "[redacted]"; }
  }
  return copy;
}

export class ActionHistory {
  private entries: AgentHistoryEntry[] = [];
  private epoch = 0;
  private nextId = 1;
  private disposed = false;
  constructor(private readonly now: () => number = Date.now) {}

  read(): AgentHistoryEntry[] { return structuredClone(this.entries); }
  clear(): void { this.entries = []; this.epoch++; }
  dispose(): void { this.disposed = true; this.clear(); }

  async record(action: ComputerAction, execute: () => Promise<ActionResult>): Promise<ActionResult> {
    // Sanitize before awaiting so raw values never enter the retained history.
    const summary = redact(action);
    const timestamp = this.now();
    const epoch = this.epoch;
    let success = false;
    try {
      const result = await execute();
      success = result.success;
      return result;
    } finally {
      if (!this.disposed && epoch === this.epoch) {
        this.entries.push({ id: this.nextId++, action: summary, success, timestamp, completedAt: this.now() });
        if (this.entries.length > 100) this.entries.shift();
      }
    }
  }
}

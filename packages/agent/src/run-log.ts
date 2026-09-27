import { appendFileSync, mkdirSync, renameSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export type RunLog = (entry: Record<string, unknown>) => void;

export const RUN_LOG_PATH = join(homedir(), "Library", "Logs", "Nora", "agent-runs.jsonl");

/**
 * A local JSON-lines record of each request: what was asked, what Nora read on screen, which step DeepSeek chose,
 * and how it ended. It stays on this Mac, so a run can be reviewed without opening any window.
 */
export function createRunLog(path = RUN_LOG_PATH, maxBytes = 5_000_000): RunLog {
  return entry => {
    try {
      mkdirSync(dirname(path), { recursive: true });
      if ((statSync(path, { throwIfNoEntry: false })?.size ?? 0) > maxBytes) renameSync(path, `${path}.old`);
      appendFileSync(path, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);
    } catch { /* Logging must never break a request. */ }
  };
}

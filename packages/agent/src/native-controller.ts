import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import type { ActionResult, ComputerAction, ComputerController, ComputerState } from "../../shared/src/types.js";

type Reply = Record<string, unknown> & { success: boolean };
type Pending = { resolve: (reply: Reply) => void; reject: (error: Error) => void; timer: NodeJS.Timeout };
type HelperRequest = ComputerAction | { type: "snapshot" } | { type: "default_browser" } | (ComputerAction & {
  expectedApp: string;
  expectedWindow?: string;
  expectedRole: string;
  expectedLabel?: string;
  expectedActions: string[];
});

function isState(reply: Reply): reply is Reply & ComputerState {
  return typeof reply.activeApp === "string"
    && typeof reply.snapshotGeneration === "string"
    && (reply.activeWindow === undefined || typeof reply.activeWindow === "string")
    && typeof reply.accessibilityTrusted === "boolean"
    && typeof reply.truncated === "boolean"
    && Array.isArray(reply.elements)
    && reply.elements.every((element: unknown) => {
      if (!element || typeof element !== "object") return false;
      const e = element as Record<string, unknown>;
      return typeof e.id === "string" && typeof e.role === "string"
        && (e.label === undefined || typeof e.label === "string")
        && typeof e.enabled === "boolean" && Array.isArray(e.actions)
        && e.actions.every(action => typeof action === "string");
    });
}

/** One serialized JSON-lines session. Never retries an action after transport failure. */
export class NativeComputerController implements ComputerController {
  private child?: ChildProcessWithoutNullStreams;
  private pending?: Pending;
  private queue: Promise<unknown> = Promise.resolve();
  private buffer = "";
  private failure?: Error;
  private closed = false;
  private exited: Promise<void> = Promise.resolve();
  private closing?: Promise<void>;
  private latestSnapshot?: ComputerState;

  constructor(private readonly helperPath: string, private readonly timeoutMs = 10_000) {}

  async execute(action: ComputerAction): Promise<ActionResult> {
    if ((action.type === "click" || (action.type === "type_text" && action.target))) {
      const snapshot = this.latestSnapshot;
      if (!snapshot) return { success: false, error: "A fresh native snapshot is required before a targeted action." };
      return this.executeValidated(action, snapshot);
    }
    this.latestSnapshot = undefined;
    try {
      const reply = await this.request(action);
      return reply.success ? { success: true } : { success: false, error: reply.error as string };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /** The app that opens web addresses, so “my browser” means the person's own browser. */
  async defaultBrowser(): Promise<string | undefined> {
    try {
      const reply = await this.request({ type: "default_browser" });
      return reply.success && typeof reply.activeApp === "string" ? reply.activeApp : undefined;
    } catch { return undefined; }
  }

  async executeValidated(action: ComputerAction, expected: ComputerState): Promise<ActionResult> {
    if (action.type !== "click" && !(action.type === "type_text" && action.target)) {
      return { success: false, error: "Atomic target validation requires a targeted action." };
    }
    const generation = action.snapshotGeneration;
    if (!generation || generation !== expected.snapshotGeneration
      || generation !== this.latestSnapshot?.snapshotGeneration) {
      return { success: false, error: "The native target snapshot is stale. Take a new snapshot and try again." };
    }
    const targetID = action.target;
    const target = expected.elements.find(element => element.id === targetID);
    const cachedTarget = this.latestSnapshot.elements.find(element => element.id === targetID);
    if (!target || JSON.stringify(target) !== JSON.stringify(cachedTarget)
      || expected.activeApp !== this.latestSnapshot.activeApp
      || expected.activeWindow !== this.latestSnapshot.activeWindow) {
      return { success: false, error: "The native target context changed. Take a new snapshot and try again." };
    }
    const request: HelperRequest = {
      ...structuredClone(action),
      expectedApp: expected.activeApp,
      ...(expected.activeWindow === undefined ? {} : { expectedWindow: expected.activeWindow }),
      expectedRole: target.role,
      ...(target.label === undefined ? {} : { expectedLabel: target.label }),
      expectedActions: [...target.actions],
    };
    // The helper consumes a generation before attempting its one atomic action.
    this.latestSnapshot = undefined;
    try {
      const reply = await this.request(request);
      return reply.success ? { success: true } : { success: false, error: reply.error as string };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  async getState(): Promise<ComputerState> {
    // The helper's get_state is app-only; navigation needs its full snapshot command.
    this.latestSnapshot = undefined;
    const reply = await this.request({ type: "snapshot" });
    if (!reply.success) throw new Error(reply.error as string);
    if (!isState(reply)) {
      const error = new Error("macOS helper returned an invalid snapshot.");
      this.abort(error);
      throw error;
    }
    const state: ComputerState = {
      snapshotGeneration: reply.snapshotGeneration,
      activeApp: reply.activeApp,
      ...(reply.activeWindow === undefined ? {} : { activeWindow: reply.activeWindow }),
      accessibilityTrusted: reply.accessibilityTrusted,
      elements: reply.elements,
      truncated: reply.truncated,
    };
    this.latestSnapshot = structuredClone(state);
    return state;
  }

  close(): Promise<void> {
    if (this.closing) return this.closing;
    this.closed = true;
    if (this.pending) this.abort(new Error("macOS helper session closed during a request."));
    this.child?.stdin.end();
    this.closing = (async () => {
      // EOF allows SnapshotReader.stop() to run. Kill only if shutdown stalls.
      const timer = setTimeout(() => this.child?.kill("SIGKILL"), 1_000);
      try { await this.exited; } finally { clearTimeout(timer); }
    })();
    return this.closing;
  }

  private request(request: HelperRequest): Promise<Reply> {
    const line = JSON.stringify(request) + "\n";
    const response = this.queue.then(() => {
      if (this.closed) throw new Error("macOS helper session is closed.");
      if (this.failure) throw this.failure;
      this.start();
      return new Promise<Reply>((resolve, reject) => {
        const timer = setTimeout(() => this.abort(new Error(
          "macOS helper request timed out; its outcome is unknown. Create a new session and snapshot before continuing.",
        )), this.timeoutMs);
        this.pending = { resolve, reject, timer };
        this.child!.stdin.write(line, error => {
          if (error) this.abort(new Error(`Could not write to macOS helper: ${error.message}`));
        });
      });
    });
    this.queue = response.catch(() => {});
    return response;
  }

  private start(): void {
    if (this.child) return;
    const child = this.child = spawn(this.helperPath, [], { stdio: "pipe" });
    this.exited = new Promise(resolve => {
      child.once("close", (code, signal) => {
        if (!this.closed || this.pending) this.abort(new Error(`macOS helper exited (${signal ?? code}); create a new session.`));
        resolve();
      });
    });
    child.on("error", error => this.abort(new Error(`macOS helper failed: ${error.message}`)));
    child.stdin.on("error", error => this.abort(new Error(`macOS helper input failed: ${error.message}`)));
    // Drain diagnostics without storing potentially private UI data or unbounded output.
    child.stderr.resume();
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => this.receive(chunk));
  }

  private receive(chunk: string): void {
    if (this.failure) return;
    this.buffer += chunk;
    if (Buffer.byteLength(this.buffer) > 1024 * 1024) {
      this.abort(new Error("macOS helper response exceeded the 1 MiB limit."));
      return;
    }
    let newline: number;
    while ((newline = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, newline);
      this.buffer = this.buffer.slice(newline + 1);
      try {
        const reply: unknown = JSON.parse(line);
        if (!reply || typeof reply !== "object" || !("success" in reply)
          || typeof reply.success !== "boolean"
          || (!reply.success && (!("error" in reply) || typeof reply.error !== "string"))) {
          throw new Error("Invalid response fields");
        }
        if (!this.pending) throw new Error("Unexpected response");
        const pending = this.pending;
        this.pending = undefined;
        clearTimeout(pending.timer);
        pending.resolve(reply as Reply);
      } catch {
        this.abort(new Error("macOS helper returned an invalid or unexpected JSON response."));
        return;
      }
    }
  }

  private abort(error: Error): void {
    this.failure ??= error;
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(this.failure);
      this.pending = undefined;
    }
    this.buffer = "";
    this.child?.kill("SIGKILL");
  }
}

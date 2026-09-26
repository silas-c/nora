import type { Readable, Writable } from "node:stream";
import type { Agent, AgentEvent, AgentResult, UserInput } from "../../shared/src/types.js";

export type AgentRequest = { type: "submit"; requestId: string; input: UserInput };
export type AgentMessage =
  | { type: "event"; requestId: string; event: AgentEvent }
  | { type: "result"; requestId: string; result: AgentResult }
  | { type: "protocol_error"; requestId: string | null; error: string };

function isInput(value: unknown): value is UserInput {
  if (!value || typeof value !== "object") return false;
  const input = value as Record<string, unknown>;
  return (input.source === "text" || input.source === "voice")
    ? typeof input.text === "string"
    : input.source === "aac" && typeof input.intent === "string";
}

/** One agent/helper session per UI connection. EOF/error cancels outstanding work. */
export function serveAgent(
  input: Readable, output: Writable, agent: Agent, close: () => Promise<void>,
): Promise<void> {
  return new Promise(resolve => {
    let active: string | undefined;
    let buffer = "";
    let closing = false;
    const seen = new Set<string>();
    const send = (message: AgentMessage) => {
      if (!closing && !output.destroyed) output.write(JSON.stringify(message) + "\n");
    };
    const unsubscribe = agent.subscribe(event => {
      if (active) send({ type: "event", requestId: active, event });
    });
    const finish = async () => {
      if (closing) return;
      closing = true;
      unsubscribe();
      input.off("data", onData);
      input.pause();
      try { await close(); } catch { /* Connection is already closed. */ } finally { resolve(); }
    };
    const error = (requestId: string | null, message: string) => send({ type: "protocol_error", requestId, error: message });
    const dispatch = async (line: string) => {
      let request: Record<string, unknown>;
      try {
        const parsed: unknown = JSON.parse(line);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
        request = parsed as Record<string, unknown>;
      } catch { error(null, "Expected a JSON request object."); return; }
      const id = request.requestId;
      if (typeof id !== "string" || !id.trim() || id.length > 128) {
        error(null, "requestId must be a nonempty string of at most 128 characters."); return;
      }
      if (seen.has(id)) { error(id, "requestId has already been used in this session."); return; }
      if (seen.size >= 10_000) { error(id, "Session request limit reached. Reconnect to continue."); return; }
      seen.add(id);
      if (request.type !== "submit" || !isInput(request.input)) {
        error(id, "Expected type submit and a valid text, voice, or AAC input."); return;
      }
      if (active) {
        send({ type: "result", requestId: id, result: { success: false, error: "An action is already running. Please wait." } });
        return;
      }
      active = id;
      try {
        const result = await agent.submit(request.input);
        send({ type: "result", requestId: id, result });
      } catch {
        send({ type: "result", requestId: id, result: { success: false, error: "Agent request failed." } });
      } finally { active = undefined; }
    };
    const onData = (chunk: string) => {
      buffer += chunk;
      let newline: number;
      while (!closing && (newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        if (Buffer.byteLength(line) > 64 * 1024) {
          error(null, "Request exceeds the 64 KiB limit."); void finish(); return;
        }
        void dispatch(line);
      }
      if (Buffer.byteLength(buffer) > 64 * 1024) {
        error(null, "Request exceeds the 64 KiB limit."); void finish();
      }
    };
    input.setEncoding("utf8");
    input.on("data", onData);
    input.once("end", () => {
      if (buffer.trim()) error(null, "Incomplete request: each message must end with a newline.");
      void finish();
    });
    input.once("error", () => { void finish(); });
    input.once("close", () => { void finish(); });
    output.once("error", () => { void finish(); });
    output.once("close", () => { void finish(); });
  });
}

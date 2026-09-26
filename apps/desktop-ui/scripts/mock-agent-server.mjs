// Mock-only agent server for interface development and demos. Run after `npm run build`.
// It serves the real agent and JSON-lines transport against the synthetic Canvas controller,
// plus one simulated destructive request so the confirmation flow can be shown end to end.
// Nothing here launches apps, reads the desktop, or touches files.
import { createAgent, CanvasMockComputerController, serveAgent } from "../../../dist/agent/src/index.js";

const SIMULATED_DELETE_INTENT = "SIMULATE_DELETE_DOWNLOADS";
const simulatedDelete = {
  action: { type: "launch_app", app: "Mock deletion executor" },
  effect: "deletion",
  actingMessage: "Delete everything in your Downloads folder (practice only — no files are touched)",
  doneMessage: "Practice deletion finished. No files were touched.",
};
const deletePhrase = /^(?:please )?delete everything in (?:my )?downloads(?: folder)?[.!]?$/i;

const agent = createAgent(new CanvasMockComputerController(), {
  resolveSkill: input =>
    (input.source === "aac" && input.intent === SIMULATED_DELETE_INTENT)
      || ((input.source === "text" || input.source === "voice") && deletePhrase.test(input.text.trim()))
      ? simulatedDelete
      : undefined,
});

const disconnect = () => process.stdin.destroy();
process.once("SIGINT", disconnect);
process.once("SIGTERM", disconnect);
console.error("Nora mock agent: synthetic Canvas controller plus a practice confirmation. Nothing on this Mac changes.");
await serveAgent(process.stdin, process.stdout, agent, async () => {});

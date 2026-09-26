import { fileURLToPath } from "node:url";
import { createAgent, MockComputerController, NativeComputerController } from "./index.js";
import { serveAgent } from "./transport.js";

const args = process.argv.slice(2);
if (args.some(arg => arg !== "--native")) {
  console.error("Usage: node dist/agent/src/server.js [--native]");
  process.exitCode = 1;
} else {
  const native = args.includes("--native");
  const controller = native
    ? new NativeComputerController(fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url)))
    : new MockComputerController();
  const agent = createAgent(controller);
  const close = async () => {
    if (controller instanceof NativeComputerController) await controller.close();
  };
  const disconnect = () => process.stdin.destroy();
  process.once("SIGINT", disconnect);
  process.once("SIGTERM", disconnect);
  console.error(native ? "Nora agent server: native mode" : "Nora agent server: mock mode");
  try { await serveAgent(process.stdin, process.stdout, agent, close); }
  finally {
    process.off("SIGINT", disconnect);
    process.off("SIGTERM", disconnect);
  }
}

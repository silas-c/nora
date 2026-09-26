import { createConfirmationDemoSession } from "./confirmation-demo.js";
import { serveAgent } from "./transport.js";

if (process.argv.length > 2) {
  console.error("Usage: node dist/agent/src/confirmation-demo-server.js");
  process.exitCode = 1;
} else {
  const { agent } = createConfirmationDemoSession();
  const disconnect = () => process.stdin.destroy();
  process.once("SIGINT", disconnect);
  process.once("SIGTERM", disconnect);
  console.error("Nora confirmation demo server: mock-only mode");
  try {
    await serveAgent(process.stdin, process.stdout, agent, async () => {});
  } finally {
    process.off("SIGINT", disconnect);
    process.off("SIGTERM", disconnect);
  }
}

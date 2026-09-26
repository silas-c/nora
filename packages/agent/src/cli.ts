import { fileURLToPath } from "node:url";
import { createAgent, MockComputerController, NativeComputerController } from "./index.js";

const args = process.argv.slice(2);
const native = args[0] === "--native";
if (native) args.shift();
const aac = args[0] === "--aac";
if (aac) args.shift();
const value = args.join(" ") || (aac ? "OPEN_SCHOOL" : "Open Canvas");
const controller = native
  ? new NativeComputerController(fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url)))
  : new MockComputerController();
console.log(native ? "Native mode: actions run on this Mac." : "Mock mode: no computer actions will run.");
const agent = createAgent(controller);
agent.subscribe(event => console.log(JSON.stringify(event)));
try {
  const result = await agent.submit(aac ? { source: "aac", intent: value } : { source: "text", text: value });
  if (controller instanceof MockComputerController) console.log(JSON.stringify({ actions: controller.actions }));
  if (!result.success) process.exitCode = 1;
} finally {
  agent.dispose();
  if (controller instanceof NativeComputerController) await controller.close();
}

import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline/promises";
import { createAgent, MockComputerController, CanvasMockComputerController, NativeComputerController } from "./index.js";
import { BoundedJevChooser } from "./jev.js";
import { TypeSafeJevClient } from "./typesafe-jev-client.js";
import { runNativeJev } from "./native-jev.js";

const args = process.argv.slice(2);
const showHistory = args[0] === "--history";
if (showHistory) args.shift();
const native = args[0] === "--native";
if (native) args.shift();
const jev = args[0] === "--jev";
if (jev) args.shift();
const aac = args[0] === "--aac";
if (aac) args.shift();
const value = args.join(" ") || (aac ? "OPEN_SCHOOL" : "Open Canvas");
const helperPath = process.env.NORA_HELPER_PATH
  ?? fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url));
const controller = native
  ? new NativeComputerController(helperPath)
  : new CanvasMockComputerController();
if (jev) {
  if (!native || aac || !(controller instanceof NativeComputerController)) {
    console.error('Usage: npm run agent -- --native --jev "Open Courses"');
    process.exitCode = 1;
  } else {
    console.log("Native Jev mode: bounded actions may run on this Mac after policy and confirmation checks.");
    const lifecycle = new AbortController();
    const cancel = () => lifecycle.abort();
    process.once("SIGINT", cancel);
    process.once("SIGTERM", cancel);
    const terminal = createInterface({ input: process.stdin, output: process.stdout });
    try {
      const output = await runNativeJev(
        value,
        controller,
        new BoundedJevChooser(new TypeSafeJevClient()),
        lifecycle.signal,
        {
          confirm: async (_prompt, context) => {
            if (!process.stdin.isTTY || !process.stdout.isTTY) return false;
            const answer = await terminal.question(`Approve this one model-selected action at confidence ${context.confidence.toFixed(2)}? [y/N] `);
            return /^(?:y|yes)$/i.test(answer.trim());
          },
        },
      );
      if (showHistory) console.log(JSON.stringify({ history: output.history }));
      if (!output.result.success) process.exitCode = 1;
    } finally {
      terminal.close();
      lifecycle.abort();
      process.off("SIGINT", cancel);
      process.off("SIGTERM", cancel);
      await controller.close();
    }
  }
} else {
  console.log(native ? "Native mode: actions run on this Mac." : "Mock mode: no computer actions will run.");
  const agent = createAgent(controller);
  agent.subscribe(event => console.log(JSON.stringify(event)));
  try {
    const result = await agent.submit(aac ? { source: "aac", intent: value } : { source: "text", text: value });
    if (controller instanceof MockComputerController) console.log(JSON.stringify({ actions: controller.actions }));
    if (showHistory) console.log(JSON.stringify({ history: agent.getHistory() }));
    if (!result.success) process.exitCode = 1;
  } finally {
    agent.dispose();
    if (controller instanceof NativeComputerController) await controller.close();
  }
}

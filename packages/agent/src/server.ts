import { fileURLToPath } from "node:url";
import { createAgent, MockComputerController, CanvasMockComputerController, NativeComputerController } from "./index.js";
import { serveAgent } from "./transport.js";
import { createJevCourseChooser, createJevIntentResolver } from "./jev-intent.js";
import { createDeepSeekStepChooser } from "./step-agent.js";
import { installedApps } from "./installed-apps.js";
import { createRunLog } from "./run-log.js";

const args = process.argv.slice(2);
if (args.some(arg => arg !== "--native")) {
  console.error("Usage: node dist/agent/src/server.js [--native]");
  process.exitCode = 1;
} else {
  const native = args.includes("--native");
  const controller = native
    ? new NativeComputerController(fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url)))
    : new CanvasMockComputerController();
  const resolveIntent = process.env.TYPESAFE_API_KEY ? createJevIntentResolver()
    : native ? async () => { throw new Error("Jev needs TYPESAFE_API_KEY in .env.local."); } : undefined;
  const chooseCourse = process.env.TYPESAFE_API_KEY ? createJevCourseChooser() : undefined;
  const reasoning = (["none", "low", "high"] as const).find(level => level === process.env.DEEPSEEK_REASONING) ?? "none";
  const deepSeek = process.env.DEEPSEEK_API_KEY
    ? { apiKey: process.env.DEEPSEEK_API_KEY, model: process.env.DEEPSEEK_MODEL || undefined, reasoning }
    : undefined;
  const browser = controller instanceof NativeComputerController ? await controller.defaultBrowser() : undefined;
  const chooseStep = deepSeek && createDeepSeekStepChooser({ ...deepSeek, apps: installedApps(), ...(browser ? { browser } : {}) });
  const log = process.env.NORA_RUN_LOG === "1" ? createRunLog() : () => {};
  const agent = createAgent(controller, { resolveIntent, chooseCourse, chooseStep, trace: log });
  agent.subscribe(event => log({ kind: "event", event }));
  const submit = agent.submit.bind(agent);
  agent.submit = async input => {
    log({ kind: "request", input });
    const result = await submit(input);
    log({ kind: "result", result });
    return result;
  };
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

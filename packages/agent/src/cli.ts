import { createAgent, MockComputerController } from "./index.js";

const args = process.argv.slice(2);
const aac = args[0] === "--aac";
if (aac) args.shift();
const value = args.join(" ") || (aac ? "OPEN_SCHOOL" : "Open Canvas");
const controller = new MockComputerController();
console.log("Mock mode: no computer actions will run.");
const agent = createAgent(controller);
agent.subscribe(event => console.log(JSON.stringify(event)));
const result = await agent.submit(aac ? { source: "aac", intent: value } : { source: "text", text: value });
console.log(JSON.stringify({ actions: controller.actions }));
if (!result.success) process.exitCode = 1;

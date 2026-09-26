/** Explicit desktop test: only a disposable localhost page, no account content. */
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { NativeComputerController } from "./native-controller.js";
import { navigateCourses } from "./navigation.js";

const page = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Nora Courses Smoke</title><h1>Disposable navigation test</h1>
<button onclick="document.title='Courses - Nora Smoke';document.getElementById('result').hidden=false">Courses</button>
<a id="result" href="#courses" hidden>All Courses</a></html>`;
const server = createServer((_request, response) => {
  response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  response.end(page);
});
const controller = new NativeComputerController(fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url)));
const lifecycle = new AbortController();
const cancel = () => lifecycle.abort();
process.once("SIGINT", cancel);
process.once("SIGTERM", cancel);
try {
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Could not start the disposable page.");
  const computer = {
    execute: controller.execute.bind(controller),
    async getState() {
      const state = await controller.getState();
      // Never select controls from the previous page while the test URL loads.
      if (!state.activeWindow?.includes("Nora Smoke") && !state.activeWindow?.includes("Nora Courses Smoke")) {
        return { ...state, activeWindow: "Loading test page", elements: [] };
      }
      return state;
    },
  };
  const result = await navigateCourses(computer, computer.execute, event => console.log(event.type === "acting" ? event.message : event.type), lifecycle.signal, {
    url: `http://127.0.0.1:${address.port}/`,
  });
  if (!result.success) throw new Error(result.error);
  console.log("PASS: real helper opened the disposable page, selected Courses, clicked once, and verified the result.");
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
} finally {
  await controller.close();
  await new Promise<void>(resolve => server.close(() => resolve()));
  process.off("SIGINT", cancel);
  process.off("SIGTERM", cancel);
}

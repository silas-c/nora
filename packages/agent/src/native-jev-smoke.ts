/** Explicit desktop test: real Jev, real helper, disposable localhost page, no account data. */
import { createServer } from "node:http";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { NativeComputerController } from "./native-controller.js";
import { BoundedJevChooser } from "./jev.js";
import { TypeSafeJevClient } from "./typesafe-jev-client.js";
import { runNativeJev } from "./native-jev.js";

const dashboardPage = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Dashboard - Canvas</title><h1>Disposable Canvas dashboard</h1>
<a href="/courses">Courses</a></html>`;
const coursesPage = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Courses - Canvas</title><h1>Courses</h1></html>`;
const server = createServer((request, response) => {
  response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  response.end(request.url === "/courses" ? coursesPage : dashboardPage);
});
const bundledHelper = fileURLToPath(new URL(
  "../../../apps/macos-helper/.build/NoraMacHelper.app/Contents/MacOS/mac-helper", import.meta.url,
));
const debugHelper = fileURLToPath(new URL("../../../apps/macos-helper/.build/debug/mac-helper", import.meta.url));
const defaultHelper = existsSync(bundledHelper) ? bundledHelper : debugHelper;
const controller = new NativeComputerController(process.env.NORA_HELPER_PATH ?? defaultHelper);
const lifecycle = new AbortController();
const cancel = () => lifecycle.abort();
process.once("SIGINT", cancel);
process.once("SIGTERM", cancel);
try {
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Could not start the disposable Jev page.");
  const result = await runNativeJev(
    "Open Courses",
    controller,
    new BoundedJevChooser(new TypeSafeJevClient()),
    lifecycle.signal,
    {
      url: `http://127.0.0.1:${address.port}/`,
      waitAfterOpen: signal => delay(2_000, undefined, { signal }),
    },
  );
  const clicks = result.history.filter(entry => entry.action.type === "click");
  if (clicks.length !== 1 || !clicks[0]?.success) {
    throw new Error(`Expected one successful bounded click; observed ${clicks.length}.`);
  }
  const finalState = await controller.getState();
  if (!finalState.activeWindow?.startsWith("Courses - Canvas")) {
    throw new Error("The disposable page did not expose the expected post-click state.");
  }
  if (!result.result.success) throw new Error(result.result.error);
  console.log("PASS: real Jev selected one disposable Courses control, the atomic native click ran once, and fresh state verified the result.");
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
} finally {
  await controller.close();
  await new Promise<void>(resolve => server.close(() => resolve()));
  process.off("SIGINT", cancel);
  process.off("SIGTERM", cancel);
}

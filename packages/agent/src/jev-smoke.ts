import { BoundedJevChooser } from "./jev.js";
import { TypeSafeJevClient } from "./typesafe-jev-client.js";

if (process.argv.length > 2) {
  console.error("Usage: npm run jev:smoke");
  process.exitCode = 1;
} else {
  const lifecycle = new AbortController();
  const cancel = () => lifecycle.abort();
  process.once("SIGINT", cancel);
  process.once("SIGTERM", cancel);
  try {
    const chooser = new BoundedJevChooser(new TypeSafeJevClient());
    const decision = await chooser.choose({
      goal: "Open Courses",
      state: {
        activeApp: "Microsoft Edge",
        activeWindow: "Synthetic Canvas dashboard",
        accessibilityTrusted: true,
        truncated: false,
        elements: [
          { id: "synthetic-dashboard", role: "AXLink", label: "Dashboard", enabled: true, actions: ["AXPress"] },
          { id: "synthetic-courses", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] },
          { id: "synthetic-calendar", role: "AXLink", label: "Calendar", enabled: true, actions: ["AXPress"] },
        ],
      },
    }, lifecycle.signal);
    console.log(JSON.stringify({ synthetic: true, executed: false, decision }));
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Jev smoke check failed.");
    process.exitCode = 1;
  } finally {
    process.off("SIGINT", cancel);
    process.off("SIGTERM", cancel);
  }
}

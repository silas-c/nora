import { setTimeout as delay } from "node:timers/promises";
import type { ActionResult, AgentEvent, ComputerAction, ComputerController } from "../../shared/src/types.js";

export const CANVAS_URL = "https://canvas.temple.edu";
export const normalizeLabel = (value: string) => value.trim().toLowerCase().replace(/\s+/g, " ");
export interface NavigationOptions {
  /** Dependency injection for deterministic tests; production always uses ten observations. */
  wait?: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  /** Test-only localhost target; the public agent always uses CANVAS_URL. */
  url?: string;
}

export async function navigateCourses(
  computer: ComputerController,
  execute: (action: ComputerAction) => Promise<ActionResult>,
  emit: (event: AgentEvent) => void,
  signal: AbortSignal,
  options: NavigationOptions = {},
): Promise<ActionResult & { message?: string }> {
  const fail = (error: string): ActionResult => ({ success: false, error });
  const wait = options.wait ?? ((ms, signal) => delay(ms, undefined, { signal }));
  let clicked = false;
  let allCoursesBeforeClick = false;
  let lastProblem = "Courses did not appear. Sign in to Canvas, open its dashboard, and try again.";
  try {
    signal.throwIfAborted();
    emit({ type: "acting", message: "Opening Canvas before looking for Courses…" });
    const opened = await execute({ type: "open_url", url: options.url ?? CANVAS_URL, browser: "Microsoft Edge" });
    if (!opened.success) return fail(opened.error);
    for (let step = 0; step < 10; step++) {
      if (step > 0) await wait(300, signal);
      signal.throwIfAborted();
      const state = await computer.getState();
      signal.throwIfAborted();
      if (state.activeApp !== "Microsoft Edge") return fail("Focus changed away from Microsoft Edge. Focus Canvas and try again.");
      if (!state.accessibilityTrusted) return fail("Accessibility permission is required to read Canvas controls.");
      const allCourses = state.elements.some(e => normalizeLabel(e.label ?? "") === "all courses" && e.enabled);
      const coursesTitle = /^courses(?:\s*[-|—:]|$)/.test(normalizeLabel(state.activeWindow ?? ""));
      if (coursesTitle || (clicked && allCourses && !allCoursesBeforeClick)) {
        return { success: true, message: "Courses is visible in Canvas." };
      }
      if (clicked) continue; // Never click again while waiting for the outcome.
      if (state.truncated) return fail("The Canvas snapshot is incomplete. Open Courses manually or try again with fewer controls visible.");
      const matches = state.elements.filter(e => normalizeLabel(e.label ?? "") === "courses");
      const candidates = matches.filter(e => e.enabled && e.actions.includes("AXPress") && ["AXLink", "AXButton", "AXTab", "AXMenuItem"].includes(e.role));
      if (candidates.length > 1) return fail("More than one Courses control is available. Select Courses manually, then try again.");
      if (candidates.length === 0) {
        if (matches.length) lastProblem = "Courses is disabled or cannot be pressed. Open it manually or try again after the page finishes loading.";
        continue;
      }
      signal.throwIfAborted();
      emit({ type: "acting", message: "Opening the visible Courses control…" });
      allCoursesBeforeClick = allCourses;
      const result = await execute({
        type: "click",
        target: candidates[0].id,
        ...(state.snapshotGeneration ? { snapshotGeneration: state.snapshotGeneration } : {}),
      });
      if (!result.success) return fail(result.error);
      clicked = true;
    }
    return fail(clicked
      ? "The Courses control was clicked, but its result could not be verified. Check Canvas before trying again."
      : lastProblem);
  } catch (error) {
    return fail(signal.aborted ? "Navigation was cancelled." : error instanceof Error ? error.message : "Could not inspect Canvas.");
  }
}

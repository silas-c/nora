import { setTimeout as delay } from "node:timers/promises";
import type { ActionResult, AgentEvent, ComputerAction, ComputerController, ComputerState } from "../../shared/src/types.js";

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

/** Picks the index of the one listed course the request names, or undefined when none clearly matches. */
export type CourseChooser = (request: string, courses: string[], signal: AbortSignal) => Promise<number | undefined>;

// Canvas navigation and page chrome that is never a class, plus anything that could change data.
const NOT_A_COURSE = new Set(["dashboard", "courses", "all courses", "account", "calendar", "inbox", "history", "help",
  "groups", "commons", "studio", "home", "skip to content", "view all courses", "start a new course"]);
const UNSAFE_LABEL = /\b(delete|remove|submit|send|save|purchase|buy|checkout|download|upload|password|pay|post|publish|sign\s*out|log\s*out|unenroll|drop)\b/i;
const MAX_COURSES = 100;

export async function navigateClass(
  computer: ComputerController,
  execute: (action: ComputerAction) => Promise<ActionResult>,
  emit: (event: AgentEvent) => void,
  signal: AbortSignal,
  request: string,
  chooseCourse: CourseChooser,
  options: NavigationOptions = {},
): Promise<ActionResult & { message?: string }> {
  const fail = (error: string): ActionResult => ({ success: false, error });
  const wait = options.wait ?? ((ms, signal) => delay(ms, undefined, { signal }));
  const courses = await navigateCourses(computer, execute, emit, signal, options);
  if (!courses.success) return courses;
  try {
    // The Canvas Courses tray fills in asynchronously; choose only from a list that stopped changing.
    let state;
    let candidates: ComputerState["elements"] = [];
    let previous = "";
    for (let step = 0; step < 15; step++) {
      if (step > 0) await wait(300, signal);
      signal.throwIfAborted();
      state = await computer.getState();
      signal.throwIfAborted();
      if (state.activeApp !== "Microsoft Edge") return fail("Focus changed away from Microsoft Edge. Focus Canvas and try again.");
      if (state.truncated) return fail("The Canvas snapshot is incomplete. Open the class manually or try again with fewer controls visible.");
      const seen = new Set<string>();
      candidates = state.elements.filter(e => {
        const label = normalizeLabel(e.label ?? "");
        if (!label || seen.has(label) || NOT_A_COURSE.has(label) || UNSAFE_LABEL.test(label)) return false;
        if (e.role !== "AXLink" || !e.enabled || !e.actions.includes("AXPress")) return false;
        seen.add(label);
        return true;
      }).slice(0, MAX_COURSES);
      const current = candidates.map(e => normalizeLabel(e.label ?? "")).join("\n");
      if (current && current === previous) break;
      previous = current;
    }
    if (!state || candidates.length === 0) return fail("Courses is open, but no classes are visible. Pick the class manually.");
    emit({ type: "thinking", message: "Finding the class you named…" });
    const labels = candidates.map(e => (e.label ?? "").trim());
    const index = await chooseCourse(request, labels, signal);
    signal.throwIfAborted();
    const target = index === undefined ? undefined : candidates[index];
    if (!target) {
      const shown = labels.slice(0, 5).join("; ");
      return fail(`Courses is open, but I couldn’t tell which class you meant. Visible classes include: ${shown}.`);
    }
    const label = (target.label ?? "").trim();
    const before = state.activeWindow;
    emit({ type: "acting", message: `Opening ${label}…` });
    const result = await execute({
      type: "click",
      target: target.id,
      ...(state.snapshotGeneration ? { snapshotGeneration: state.snapshotGeneration } : {}),
    });
    if (!result.success) return fail(result.error);
    for (let step = 0; step < 10; step++) {
      await wait(300, signal);
      signal.throwIfAborted();
      const after = await computer.getState();
      if (after.activeApp !== "Microsoft Edge") return fail("Focus changed away from Microsoft Edge before the class page could be checked.");
      const title = normalizeLabel(after.activeWindow ?? "");
      const courseName = normalizeLabel(label);
      const heading = after.elements.some(element => element.role === "AXStaticText" && normalizeLabel(element.label ?? "") === courseName);
      if ((after.activeWindow !== before && title.includes(courseName)) || heading) {
        return { success: true, message: `${label} is open in Canvas.` };
      }
    }
    return fail(`${label} was clicked, but its page could not be verified. Check Canvas before trying again.`);
  } catch (error) {
    return fail(signal.aborted ? "Navigation was cancelled." : error instanceof Error ? error.message : "Could not open the class.");
  }
}

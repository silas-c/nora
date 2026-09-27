import dashboard from "../test/fixtures/canvas-dashboard.json" with { type: "json" };
import courses from "../test/fixtures/canvas-courses.json" with { type: "json" };
import login from "../test/fixtures/canvas-login.json" with { type: "json" };
import type { ActionResult, ComputerAction, ComputerState } from "../../shared/src/types.js";
import { MockComputerController } from "./mock-controller.js";

/** Synthetic Canvas state machine. It never launches apps or reads the desktop. */
export class CanvasMockComputerController extends MockComputerController {
  private stage: "dashboard" | "courses" | "login" | "other";
  private generation = 0;
  private latest?: ComputerState;
  private activeApp = "Microsoft Edge";

  constructor(private readonly startAt: "dashboard" | "login" = "dashboard") {
    super();
    this.stage = startAt;
  }

  async getState(): Promise<ComputerState> {
    const fixture = this.stage === "courses" ? courses : this.stage === "login" ? login : dashboard;
    const state: ComputerState = structuredClone(fixture);
    state.activeApp = this.activeApp;
    if (this.stage === "courses") state.activeWindow = "Courses - Canvas";
    if (this.stage === "other") { state.activeWindow = "Mock browser"; state.elements = []; }
    this.generation++;
    state.elements.forEach((element, index) => { element.id = `mock-${this.generation}-${index + 1}`; });
    this.latest = structuredClone(state);
    return state;
  }

  async execute(action: ComputerAction): Promise<ActionResult> {
    // Keep the same observable action recording as the basic mock.
    await super.execute(action);
    if (action.type === "open_url") {
      this.activeApp = action.browser ?? "Microsoft Edge";
      this.stage = action.url === "https://canvas.temple.edu" ? this.startAt : "other";
      this.latest = undefined;
    } else if (action.type === "launch_app" || action.type === "focus_app") {
      this.activeApp = action.app;
      this.latest = undefined;
    } else if (action.type === "click") {
      const target = this.latest?.elements.find(e => e.id === action.target);
      if (!target) return { success: false, error: "Mock target is stale. Take a new snapshot." };
      if (!target.enabled || !target.actions.includes("AXPress")) return { success: false, error: "Mock target cannot be pressed." };
      if (this.stage !== "dashboard" || target.label !== "Courses") return { success: false, error: "This mock only simulates the dashboard Courses action." };
      this.stage = "courses";
      this.latest = undefined;
    }
    return { success: true };
  }
}

import type { ActionResult, ComputerAction, ComputerController, ComputerState } from "../../shared/src/types.js";

export class MockComputerController implements ComputerController {
  readonly actions: ComputerAction[] = [];
  constructor(
    private readonly result: ActionResult = { success: true },
    private readonly state: ComputerState = {
      activeApp: "Microsoft Edge", activeWindow: "Canvas", accessibilityTrusted: true,
      elements: [{ id: "e1", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] }],
      truncated: false,
    },
  ) {}

  async getState(): Promise<ComputerState> {
    return structuredClone(this.state);
  }

  async execute(action: ComputerAction): Promise<ActionResult> {
    this.actions.push(structuredClone(action));
    return { ...this.result };
  }
}

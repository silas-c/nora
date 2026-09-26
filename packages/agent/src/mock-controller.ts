import type { ActionResult, ComputerAction, ComputerController } from "../../shared/src/types.js";

export class MockComputerController implements ComputerController {
  readonly actions: ComputerAction[] = [];
  constructor(private readonly result: ActionResult = { success: true }) {}
  async execute(action: ComputerAction): Promise<ActionResult> {
    this.actions.push(structuredClone(action));
    return { ...this.result };
  }
}

import type { ComputerAction } from "../../shared/src/types.js";
import type { Intent } from "./router.js";

export interface Skill {
  action: ComputerAction;
  actingMessage: string;
  doneMessage: string;
}

export const skills: Record<Exclude<Intent, "UNKNOWN">, Skill> = {
  OPEN_CANVAS: {
    action: { type: "open_url", url: "https://canvas.temple.edu", browser: "Microsoft Edge" },
    actingMessage: "Opening Canvas in Microsoft Edge…",
    doneMessage: "Canvas open request sent to Microsoft Edge.",
  },
};

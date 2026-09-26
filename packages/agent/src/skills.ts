import type { ComputerAction } from "../../shared/src/types.js";
import type { Intent } from "./router.js";

export interface Skill {
  action: ComputerAction;
  actingMessage: string;
  doneMessage: string;
}

export const skills: Record<Exclude<Intent, "UNKNOWN">, Skill> = {
  OPEN_DOG_PHOTOS: {
    action: {
      type: "open_url",
      url: "https://www.google.com/search?tbm=isch&q=dogs",
      browser: "Microsoft Edge",
    },
    actingMessage: "Opening public dog photos on Google Images…",
    doneMessage: "Dog photo search sent to Microsoft Edge.",
  },
  OPEN_CANVAS: {
    action: {
      type: "open_url",
      url: "https://canvas.temple.edu",
      browser: "Microsoft Edge",
    },
    actingMessage: "Opening Canvas in Microsoft Edge…",
    doneMessage: "Canvas open request sent to Microsoft Edge.",
  },
  OPEN_PHOTOS: {
    action: { type: "launch_app", app: "Photos" },
    actingMessage: "Opening Photos…",
    doneMessage: "Photos launch request sent.",
  },
  OPEN_EDGE: {
    action: { type: "launch_app", app: "Microsoft Edge" },
    actingMessage: "Opening Microsoft Edge…",
    doneMessage: "Microsoft Edge launch request sent.",
  },
  OPEN_FINDER: {
    action: { type: "launch_app", app: "Finder" },
    actingMessage: "Opening Finder…",
    doneMessage: "Finder launch request sent.",
  },
  ZOOM_IN: {
    action: { type: "keypress", key: "+", modifiers: ["CMD"] },
    actingMessage: "Sending zoom-in shortcut to the active app…",
    doneMessage: "Zoom-in shortcut sent to the active app.",
  },
  ZOOM_OUT: {
    action: { type: "keypress", key: "-", modifiers: ["CMD"] },
    actingMessage: "Sending zoom-out shortcut to the active app…",
    doneMessage: "Zoom-out shortcut sent to the active app.",
  },
};

import type { ComputerAction } from "../../shared/src/types.js";
import type { ActionEffect } from "./safety.js";
import type { Intent } from "./router.js";

export interface Skill {
  action: ComputerAction;
  /** Trusted implementation metadata, never accepted from user input. */
  effect?: ActionEffect;
  actingMessage: string;
  doneMessage: string;
}

export const skills: Record<Exclude<Intent, "UNKNOWN" | "OPEN_COURSES">, Skill> = {
  OPEN_DOG_PHOTOS: {
    effect: "navigation",
    action: {
      type: "open_url",
      url: "https://www.google.com/search?tbm=isch&q=dogs",
      browser: "Microsoft Edge",
    },
    actingMessage: "Opening public dog photos on Google Images…",
    doneMessage: "Dog photo search sent to Microsoft Edge.",
  },
  OPEN_CANVAS: {
    effect: "navigation",
    action: {
      type: "open_url",
      url: "https://canvas.temple.edu",
      browser: "Microsoft Edge",
    },
    actingMessage: "Opening Canvas in Microsoft Edge…",
    doneMessage: "Canvas open request sent to Microsoft Edge.",
  },
  OPEN_PHOTOS: {
    effect: "navigation",
    action: { type: "launch_app", app: "Photos" },
    actingMessage: "Opening Photos…",
    doneMessage: "Photos launch request sent.",
  },
  OPEN_EDGE: {
    effect: "navigation",
    action: { type: "launch_app", app: "Microsoft Edge" },
    actingMessage: "Opening Microsoft Edge…",
    doneMessage: "Microsoft Edge launch request sent.",
  },
  OPEN_FINDER: {
    effect: "navigation",
    action: { type: "launch_app", app: "Finder" },
    actingMessage: "Opening Finder…",
    doneMessage: "Finder launch request sent.",
  },
  ZOOM_IN: {
    effect: "zoom",
    action: { type: "keypress", key: "+", modifiers: ["CMD"] },
    actingMessage: "Sending zoom-in shortcut to the active app…",
    doneMessage: "Zoom-in shortcut sent to the active app.",
  },
  ZOOM_OUT: {
    effect: "zoom",
    action: { type: "keypress", key: "-", modifiers: ["CMD"] },
    actingMessage: "Sending zoom-out shortcut to the active app…",
    doneMessage: "Zoom-out shortcut sent to the active app.",
  },
};

import type { UserInput } from "../../shared/src/types.js";

export type Intent = "OPEN_CANVAS" | "OPEN_COURSES" | "OPEN_DOG_PHOTOS" | "OPEN_PHOTOS" | "OPEN_EDGE" | "OPEN_FINDER" | "ZOOM_IN" | "ZOOM_OUT" | "UNKNOWN";

export function routeIntent(input: UserInput): Intent {
  if (input.source === "aac") {
    switch (input.intent) {
      case "OPEN_SCHOOL": case "OPEN_CANVAS": return "OPEN_CANVAS";
      case "OPEN_COURSES": case "OPEN_DOG_PHOTOS": case "OPEN_PHOTOS": case "OPEN_EDGE": case "OPEN_FINDER":
      case "ZOOM_IN": case "ZOOM_OUT": return input.intent;
      case "OPEN_INTERNET": return "OPEN_EDGE";
      default: return "UNKNOWN";
    }
  }
  const text = input.text.trim().toLowerCase().replace(/[.!?]+$/, "").replace(/\s+/g, " ");
  // Match whole requests so unrelated or compound instructions cannot trigger an action.
  const request = text.replace(/^please /, "").replace(/ please$/, "");
  if (/^open canvas and go to (?:my )?courses$/.test(request)) return "OPEN_COURSES";
  if (/^open (?:canvas|(?:my )?school(?:work| thing)?)(?: (?:in|on) (?:microsoft )?edge)?$/.test(request)) return "OPEN_CANVAS";
  if (/^(?:show(?: me)?|open|find) dog (?:photos|pictures)(?: on google)?$/.test(request)) return "OPEN_DOG_PHOTOS";
  if (/^open photos$/.test(request)) return "OPEN_PHOTOS";
  if (/^open (?:microsoft )?edge$/.test(request)) return "OPEN_EDGE";
  if (/^open finder$/.test(request)) return "OPEN_FINDER";
  if (/^(?:zoom in|make (?:the )?text bigger)$/.test(request)) return "ZOOM_IN";
  if (/^(?:zoom out|make (?:the )?text smaller)$/.test(request)) return "ZOOM_OUT";
  return "UNKNOWN";
}

import type { UserInput } from "../../shared/src/types.js";

export type Intent = "OPEN_CANVAS" | "UNKNOWN";

export function routeIntent(input: UserInput): Intent {
  if (input.source === "aac") {
    return ["OPEN_SCHOOL", "OPEN_CANVAS"].includes(input.intent) ? "OPEN_CANVAS" : "UNKNOWN";
  }
  const text = input.text.trim().toLowerCase().replace(/[.!?]+$/, "").replace(/\s+/g, " ");
  return /^(?:please )?open (?:canvas|(?:my )?school(?:work| thing)?)(?: in (?:microsoft )?edge)?(?: please)?$/.test(text)
    ? "OPEN_CANVAS" : "UNKNOWN";
}

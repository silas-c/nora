import { readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const FOLDERS = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", join(homedir(), "Applications")];

/** Names of the apps in the usual folders, such as “GitHub Copilot”, for matching what the person says to a real app. */
export function installedApps(folders: readonly string[] = FOLDERS): string[] {
  const names = new Set<string>();
  for (const folder of folders) {
    try {
      for (const entry of readdirSync(folder)) if (entry.endsWith(".app")) names.add(entry.slice(0, -".app".length));
    } catch { /* A missing folder has no apps. */ }
  }
  return [...names].sort();
}

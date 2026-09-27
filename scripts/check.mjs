// Runs the typecheck and the Bun test suite concurrently and fails if either does.
// They are independent, so overlapping them costs about as long as the slower one.
import { spawn } from "node:child_process";

const tasks = [
  ["typecheck", process.execPath, ["node_modules/typescript/bin/tsc", "-p", "tsconfig.json", "--noEmit"]],
  ["test", process.execPath, ["test", "packages/agent/test/"]],
];

const children = tasks.map(([name, command, args]) => {
  const child = spawn(command, args, { stdio: ["ignore", "inherit", "inherit"] });
  return new Promise((resolve, reject) => {
    child.once("error", error => reject(new Error(`${name} (${command}): ${error.message}`)));
    child.once("close", code => resolve({ name, code: code ?? 1 }));
  });
});

const results = await Promise.all(children);
const failed = results.filter(result => result.code !== 0);
for (const { name, code } of results) if (code !== 0) console.error(`\n${name} failed (exit ${code}).`);
process.exitCode = failed.length ? 1 : 0;

// Run after npm run build. Add --native to open Canvas from both input modes.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const server = fileURLToPath(new URL('../dist/agent/src/server.js', import.meta.url));
const child = spawn(process.execPath, [server, ...process.argv.slice(2)], { stdio: ['pipe', 'pipe', 'inherit'] });
const exited = new Promise((resolve, reject) => {
  child.once('error', reject);
  child.once('close', code => code === 0 ? resolve() : reject(new Error(`Server exited: ${code}`)));
});
// Register immediately so startup failures are never unhandled.
exited.catch(() => {});
const requests = [
  { type: 'submit', requestId: 'text-1', input: { source: 'text', text: 'Open Canvas' } },
  { type: 'submit', requestId: 'school-1', input: { source: 'aac', intent: 'OPEN_SCHOOL' } },
];
const timer = setTimeout(() => child.kill('SIGTERM'), 30_000);
try {
  let index = 0;
  child.stdin.write(JSON.stringify(requests[index]) + '\n');
  for await (const line of createInterface({ input: child.stdout })) {
    const message = JSON.parse(line);
    console.log(message);
    if (message.type === 'protocol_error') throw new Error(message.error);
    if (message.type === 'result') {
      if (!message.result.success) throw new Error(message.result.error ?? message.result.message);
      index++;
      if (index === requests.length) { child.stdin.end(); break; }
      child.stdin.write(JSON.stringify(requests[index]) + '\n');
    }
  }
  await exited;
  if (index !== requests.length) throw new Error('Server closed without all results.');
} finally {
  clearTimeout(timer);
  child.stdin.end();
  if (child.exitCode === null) child.kill('SIGTERM');
}

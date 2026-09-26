// Mock only: no native helper, file deletion, personal data, or model connection.
import { createInterface } from 'node:readline/promises';
import { createConfirmationDemoSession, CONFIRMATION_DEMO_INTENT } from '../dist/agent/src/confirmation-demo.js';

const { agent, computer } = createConfirmationDemoSession();
const terminal = createInterface({ input: process.stdin, output: process.stdout });
agent.subscribe(event => console.log(event));
try {
  const pending = await agent.submit({ source: 'aac', intent: CONFIRMATION_DEMO_INTENT });
  if (pending.success || !pending.requiresConfirmation) throw new Error('Expected confirmation.');
  console.log('Recorded actions before confirmation:', computer.actions.length);
  const answer = await terminal.question('Confirm simulation? Type yes; anything else cancels: ');
  console.log(await agent.confirm(pending.confirmationId, answer.trim().toLowerCase() === 'yes'));
  console.log('Recorded mock actions after confirmation:', computer.actions.length);
  console.log('Reused approval (must fail):', await agent.confirm(pending.confirmationId, true));
} finally {
  terminal.close();
  agent.dispose();
}

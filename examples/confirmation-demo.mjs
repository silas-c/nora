// Mock only: no native helper, file deletion, personal data, or model connection.
import { createInterface } from 'node:readline/promises';
import { createAgent, MockComputerController } from '../dist/agent/src/index.js';

const computer = new MockComputerController();
const agent = createAgent(computer, {
  resolveSkill: input => input.source === 'aac' && input.intent === 'TEST_ONLY_DELETE' ? {
    action: { type: 'launch_app', app: 'Mock deletion executor' },
    effect: 'deletion',
    actingMessage: 'Simulate deleting a disposable example item',
    doneMessage: 'Simulation completed. No real data was changed.',
  } : undefined,
});
const terminal = createInterface({ input: process.stdin, output: process.stdout });
agent.subscribe(event => console.log(event));
try {
  const pending = await agent.submit({ source: 'aac', intent: 'TEST_ONLY_DELETE' });
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

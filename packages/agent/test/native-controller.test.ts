import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { NativeComputerController } from "../src/native-controller.js";

const action = { type: "open_url" as const, url: "https://canvas.temple.edu", browser: "Microsoft Edge" };
const state = { activeApp: "Microsoft Edge", activeWindow: "Canvas", accessibilityTrusted: true,
  elements: [{ id: "e1", role: "AXLink", label: "Courses", enabled: true, actions: ["AXPress"] }], truncated: false };
const lines = 'import { createInterface } from "node:readline"; const lines = createInterface({input:process.stdin});';

async function withHelper(source: string, run: (controller: NativeComputerController) => Promise<void>, timeout = 2_000): Promise<void> {
  const directory = await mkdtemp(join(tmpdir(), "nora-helper-test-"));
  const path = join(directory, "helper.mjs");
  const controller = new NativeComputerController(path, timeout);
  try {
    await writeFile(path, "#!/usr/bin/env node\n" + source, { mode: 0o755 });
    await run(controller);
  } finally {
    await controller.close();
    await rm(directory, { recursive: true, force: true });
  }
}

test("snapshot then click share the same helper process and preserve IDs", async () => {
  await withHelper(`${lines}
    let snapshotTaken = false;
    for await (const line of lines) {
      const request = JSON.parse(line);
      if (request.type === 'snapshot') {
        snapshotTaken = true;
        console.log(JSON.stringify({ success:true, ...${JSON.stringify(state)} }));
      } else {
        const valid = snapshotTaken && request.type === 'click' && request.target === 'e1';
        console.log(JSON.stringify(valid ? {success:true} : {success:false,error:'Stale target'}));
      }
    }`, async controller => {
    const snapshot = await controller.getState();
    assert.deepEqual(snapshot, state);
    assert.deepEqual(await controller.execute({ type: "click", target: snapshot.elements[0].id }), { success: true });
  });
});

test("concurrent calls serialize and recover after ordinary action errors", async () => {
  await withHelper(`${lines}
    let count = 0;
    lines.on('line', line => {
      const request = JSON.parse(line);
      count++;
      if (count === 1) setTimeout(() => console.log(JSON.stringify({success:false,error:'First action failed'})), 60);
      else console.log(JSON.stringify({success:request.type === 'open_url' && request.browser === 'Microsoft Edge'}));
    });`, async controller => {
    const results = await Promise.all([controller.execute(action), controller.execute(action)]);
    assert.deepEqual(results, [{ success: false, error: "First action failed" }, { success: true }]);
  });
});

test("response framing handles partial UTF-8 and newline chunks", async () => {
  await withHelper(`${lines}
    lines.on('line', () => {
      const data = Buffer.from(JSON.stringify({success:false,error:'échec'}) + '\\n');
      const split = data.indexOf(Buffer.from('é')) + 1;
      process.stdout.write(data.subarray(0,split));
      setTimeout(() => process.stdout.write(data.subarray(split)), 10);
    });`, async controller => {
    assert.deepEqual(await controller.execute(action), { success: false, error: "échec" });
  });
});

test("malformed responses end the session without retrying", async () => {
  for (const response of ['not json', '{"success":"true"}', '{"success":false}', '']) {
    await withHelper(`${lines} lines.on('line', () => console.log(${JSON.stringify(response)}));`, async controller => {
      const result = await controller.execute(action);
      assert.equal(result.success, false);
      assert.deepEqual(await controller.execute(action), result);
    });
  }
});

test("snapshot validation rejects missing fields and invalid elements", async () => {
  for (const snapshot of [{ success: true }, { success: true, ...state, elements: [{ id: "e1" }] }]) {
    await withHelper(`${lines} lines.on('line', () => console.log(${JSON.stringify(JSON.stringify(snapshot))}));`, async controller => {
      await assert.rejects(controller.getState(), /invalid snapshot/);
      assert.equal((await controller.execute(action)).success, false);
    });
  }
});

test("permission failures are surfaced without closing a healthy session", async () => {
  await withHelper(`${lines} lines.on('line', line => console.log(JSON.stringify(
    JSON.parse(line).type === 'snapshot' ? {success:false,error:'Accessibility permission required'} : {success:true}
  )));`, async controller => {
    await assert.rejects(controller.getState(), /Accessibility permission/);
    assert.deepEqual(await controller.execute(action), { success: true });
  });
});

test("missing helper and helper exit fail pending and queued actions", async () => {
  const missing = new NativeComputerController("/nonexistent/nora-helper");
  try { assert.equal((await missing.execute(action)).success, false); } finally { await missing.close(); }
  await withHelper("process.exit(1);", async controller => {
    const results = await Promise.all([controller.execute(action), controller.execute(action)]);
    assert.ok(results.every(result => !result.success));
  });
});

test("timeout terminates the session and fails queued requests without retry", async () => {
  await withHelper("process.stdin.resume(); setInterval(() => {}, 1000);", async controller => {
    const results = await Promise.all([controller.execute(action), controller.execute(action)]);
    for (const result of results) {
      assert.equal(result.success, false);
      if (!result.success) assert.match(result.error, /timed out/);
    }
  }, 200);
});

test("close cancels in-flight and queued requests and is idempotent", async () => {
  await withHelper("process.stdin.resume();", async controller => {
    const first = controller.execute(action);
    const second = controller.execute(action);
    await new Promise(resolve => setImmediate(resolve));
    await controller.close();
    await controller.close();
    assert.equal((await first).success, false);
    assert.equal((await second).success, false);
    assert.equal((await controller.execute(action)).success, false);
  });
});

test("close sends EOF for graceful helper cleanup", async () => {
  await withHelper(`${lines} lines.on('line', () => console.log('{"success":true}'));`, async controller => {
    assert.equal((await controller.execute(action)).success, true);
    await controller.close();
    assert.equal((await controller.execute(action)).success, false);
  });
});

test("oversized helper output terminates the session", async () => {
  await withHelper(`${lines} lines.on('line', () => process.stdout.write('x'.repeat(1024 * 1024 + 1)));`, async controller => {
    const result = await controller.execute(action);
    assert.equal(result.success, false);
    if (!result.success) assert.match(result.error, /1 MiB/);
  });
});

test("snapshots larger than the former 64 KiB limit remain intact", async () => {
  await withHelper(`${lines} lines.on('line', () => console.log(JSON.stringify({
    success:true, ...${JSON.stringify(state)},
    elements:Array.from({length:1500}, (_, i) => ({id:'e'+i,role:'AXLink',label:'Course '+i,enabled:true,actions:['AXPress']}))
  })));`, async controller => {
    const snapshot = await controller.getState();
    assert.equal(snapshot.elements.length, 1500);
    assert.equal(snapshot.elements[1499].id, "e1499");
  });
});

test("closing before use never starts the helper", async () => {
  const controller = new NativeComputerController("/nonexistent/nora-helper");
  await controller.close();
  const result = await controller.execute(action);
  assert.deepEqual(result, { success: false, error: "macOS helper session is closed." });
});

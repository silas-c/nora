# Nora agent — Daniel / Person 2

The deterministic router selects a skill, executes it through `ComputerController`,
and emits `thinking`, `acting`, then `done` or `error`.

| Text / voice transcript | AAC intent | Action |
| --- | --- | --- |
| Open Canvas / Open my schoolwork | `OPEN_SCHOOL`, `OPEN_CANVAS` | Open Temple Canvas in Edge |
| Show me dog photos / Open dog pictures | `OPEN_DOG_PHOTOS` | Open a public Google Images search in Edge |
| Open Photos | `OPEN_PHOTOS` | Launch Photos |
| Open Edge / Open Microsoft Edge | `OPEN_EDGE`, `OPEN_INTERNET` | Launch Edge |
| Open Finder | `OPEN_FINDER` | Launch Finder |
| Make text bigger / Zoom in | `ZOOM_IN` | Send Cmd + Plus to the active app |
| Make text smaller / Zoom out | `ZOOM_OUT` | Send Cmd + Minus to the active app |

App launch is limited to these known names. Zoom requires Accessibility permission
and depends on the active app supporting the shortcut. A native command launched
from a terminal sends the shortcut to the app active at execution time, which may
be that terminal. The future overlay must restore focus to the intended app.

## Run from the repository root

Install Node.js with npm, then:

```sh
npm ci
npm test
npm run agent -- "Open Canvas"
npm run agent -- --aac OPEN_SCHOOL
npm run agent -- "Show me dog photos"
npm run agent -- --aac ZOOM_IN
```

The CLI defaults to a mock controller and prints events plus recorded actions.
It does not open a browser in mock mode.

For real actions on macOS, build Silas's helper first:

```sh
swift build --package-path apps/macos-helper
npm run agent -- --native "Open Canvas"
```

Native mode keeps one helper process alive for the controller's lifetime and
serializes JSON-line requests. Each request has a 10-second timeout and a 1 MiB
response limit. Call `await controller.close()` when finished; the CLI does this
automatically. Microsoft Edge must be installed for the Canvas skill.
Success means the helper accepted the open request; page loading and login
are not verified.

## Public dog-photo demo

Run this to open a Google Images search for dogs in Edge:

```sh
npm run agent -- --native "Show me dog photos"
```

You should see `thinking`, `acting`, and `done` in the terminal, followed by dog
image results in Edge. This sends only the search term `dogs`; it does not use
the Photos app, your camera, or local images. It opens results without downloading
an image or taking a screenshot. Google may display a consent page first.

To try the same action as an AAC tile:

```sh
npm run agent -- --native --aac OPEN_DOG_PHOTOS
```

Omit `--native` to preview the action in mock mode. This demo exercises intent
routing, events, and native URL opening; it does not test snapshot/click navigation
or use an AI model.

## UI integration

```ts
import { createAgent, MockComputerController } from "./packages/agent/src/index.js";

const agent = createAgent(new MockComputerController());
const unsubscribe = agent.subscribe(event => console.log(event));
await agent.submit({ source: "aac", intent: "OPEN_SCHOOL" });
unsubscribe();
```

Use `NativeComputerController(absoluteHelperPath)` from a Node process for native
execution. The desktop UI's cross-process transport is a separate integration step.
Unknown requests fail without acting. Concurrent submissions return a busy result
without changing the running request's event stream; callers should handle that
result and disable duplicate submissions while acting.

## Snapshots and native sessions

The shared contract now includes all current helper actions and `ComputerState`.
`controller.getState()` sends `snapshot`, not the helper's app-only `get_state`.
It returns the active app/window, Accessibility permission, elements, and truncation
flag. Permission and snapshot errors reject the promise; action errors are returned
as `{ success: false, error }`.

```ts
const controller = new NativeComputerController(absoluteHelperPath);
try {
  const state = await controller.getState();
  // A decision layer can select an enabled element from state.elements here,
  // then call controller.execute({ type: "click", target: element.id }).
} finally {
  await controller.close();
}
```

Snapshot IDs only work in the same session and become stale after another snapshot
or window change. Transport failures, invalid responses, and timeouts end the
session; queued requests fail. Actions are never automatically retried because
they may already have run. Create a new controller and take a new snapshot before
resuming navigation. Ordinary helper errors do not end the session.

`MockComputerController(result?, state?)` accepts a custom snapshot and returns
independent copies. It records actions but does not simulate UI transitions.

## Next milestones

- Verify snapshots and targeted actions against a controlled native test window.
- Add state fixtures and Jev decisions for Canvas navigation.
- Add bounded navigation, confirmation handling, and optional planning afterward.

The shared `confirmation_required` event is reserved; the current agent does not
implement a confirmation workflow. No model SDK or API key is needed yet.

## Desktop transport — issue #6

Build with `npm run build`. The desktop application should spawn
`node dist/agent/src/server.js --native` directly, using an absolute script path
and pipes for stdin/stdout. Omit `--native` for mock development. Do not spawn
through `npm run`: npm's status banners are not protocol messages.

One UI connection owns one agent and helper session. Send newline-terminated JSON:

```json
{"type":"submit","requestId":"school-1","input":{"source":"aac","intent":"OPEN_SCHOOL"}}
{"type":"submit","requestId":"text-1","input":{"source":"text","text":"Open Canvas"}}
```

Wait for a result before submitting the next action. Responses are:

```json
{"type":"event","requestId":"school-1","event":{"type":"acting","message":"Opening Canvas in Microsoft Edge…"}}
{"type":"result","requestId":"school-1","result":{"success":true,"message":"Canvas open request sent to Microsoft Edge."}}
{"type":"protocol_error","requestId":null,"error":"Expected a JSON request object."}
```

Events preserve the shared `AgentEvent` shape. Request IDs must be unique in the
session, nonempty, and at most 128 characters. Requests are limited to 64 KiB and
10,000 IDs per session. Invalid requests get protocol errors; overlapping requests
get a failed result without interfering with the active request's events.
Diagnostics go to stderr only. Close stdin or terminate the server when the UI
closes; this cancels active work and closes the helper. Keep stdin open until the
result arrives: EOF means disconnect, not “execute everything then exit”.

Runnable client demonstrating both input modes over one connection:

```sh
npm run build
node examples/agent-client.mjs
# Explicit native check; opens Canvas twice:
node examples/agent-client.mjs --native
```

Daniel owns this transport and the controller. The interface teammate owns spawning
it, mapping the School tile/text input to messages, rendering statuses, and closing
the session. Issue #6 remains open until both inputs pass from the actual UI.

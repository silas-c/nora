# Nora agent — Daniel / Person 2

The deterministic router selects a skill, executes it through `ComputerController`,
and emits `thinking`, `acting`, then `done` or `error`.

| Text / voice transcript | AAC intent | Action |
| --- | --- | --- |
| Open Canvas and go to Courses | `OPEN_COURSES` | Open Canvas, inspect controls, and verify Courses |
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

Use Node.js 22 or newer with npm, then:

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

- Verify the Courses workflow on the target Canvas account.
- Complete the teammate-owned UI connection, including its Cancel/Confirm controls,
  using the production and mock-only server commands below.
- Consider Jev only after deterministic navigation and safety are reliable.

The agent supports confirmation through `agent.confirm()` and the desktop transport.
No model SDK or API key is needed.

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

UI acceptance checklist:

1. Start exactly one `server.js --native` child for the desktop session and keep
   its stdin open between requests.
2. Send the School tile as `{"source":"aac","intent":"OPEN_SCHOOL"}` and typed
   commands as `{"source":"text","text":"..."}` with unique request IDs.
3. Render `thinking`, `acting`, `done`, and `error` events by request ID. Do not
   show completion until the successful result arrives.
4. Disable or reject overlapping controls while a request is active and render
   helper failures from the result. Never parse stderr as protocol data.
5. Close stdin when the UI disconnects and wait for the child to exit. The server
   disposes the agent and closes the persistent native helper on EOF.

## Courses navigation — issue #7

```sh
npm run agent -- --native "Open Canvas and go to Courses"
# Same request through the AAC path:
npm run agent -- --native --aac OPEN_COURSES
```

Sign in to Canvas yourself first. Grant Accessibility permission to the application
running the helper, then keep Edge active while the workflow runs. The router is
still deterministic; it uses no AI model. It observes at most ten snapshots, waits
300 ms between observations, chooses one enabled Courses control by its exact
normalized label and `AXPress` action, and clicks at most once. It verifies a
Courses window title or a newly visible All Courses control before emitting done.
Missing/disabled/ambiguous controls, incomplete snapshots, stale IDs, permission
errors, changed focus, and unverified results stop with an actionable error.

Native regression check using disposable content (opens and interacts with Edge):

```sh
swift build --package-path apps/macos-helper
npm run build
node dist/agent/src/native-navigation-smoke.js
```

The localhost smoke check exercises the real TypeScript controller and navigation
function against a synthetic page; it does not establish that a particular Canvas
account exposes the same controls. Verify the live command manually before closing
#7. Mock fixtures contain no account data. Call `agent.dispose()` on session
shutdown to stop observation loops, then close the native controller.

## Confirmations — agent side of issue #9

Every action emitted by the agent passes one gate. Trusted skill implementation
metadata describes the intended effect: known navigation and zoom are safe;
submission, editing, and unknown effects are sensitive; deletion effects are
destructive. Both sensitive and destructive actions pause. A low-level `click`
is not automatically safe, and clients cannot submit action/risk metadata over
stdin to bypass the router. No real deletion action or user-facing deletion route
has been added.

`AgentResult` now has three outcomes:

- `{ success: true, message? }`: completed (or explicitly cancelled).
- `{ success: false, error, requiresConfirmation?: false }`: failed.
- `{ success: false, requiresConfirmation: true, confirmationId, message }`: paused.

Handle the pending branch before reading `error`. A pending result is not an
execution failure or permission to proceed. The corresponding event includes the
exact frozen `action`, `risk`, `expiresAt` timestamp, message, and confirmation ID.
The UI must display those details and explicit Cancel/Confirm controls, then send:

```json
{"type":"confirm","requestId":"decision-1","confirmationId":"ID_FROM_PROMPT","approved":false}
```

Use `approved:true` only for explicit confirmation, and give the decision its own
unique request ID. `agent.confirm(id, approved)` is the equivalent in-process API.
Each ID expires after 60 seconds and is consumed before approved execution begins.
Cancellation, expiry, disconnect, changed context, and reused IDs never execute.
Submissions are rejected while an approval is pending. A failed approved action
cannot be retried with the same ID.

`confirmation_resolved` events identify the confirmation and a reason: `approved`,
`cancelled`, `expired`, or `invalidated`. The transport associates these with the
original submission's request ID, including asynchronous expiry. Execution events
and the decision result carry the decision request ID. Remove the prompt when
resolved; wait for the decision result before claiming execution succeeded.
On disconnect, dismiss all prompts locally; the server cancels their approvals.

Targeted approvals require a complete snapshot and validate app, window, ID,
label, role, enabled state, and actions again before execution. The current Swift
helper changes IDs on every snapshot, so native targeted approvals conservatively
invalidate rather than guess a replacement target. Untargeted sensitive keyboard
or text edits are refused because their focus cannot be bound safely with the
current contract. These limitations do not affect known safe navigation. Extend
stable target validation with Silas before exposing sensitive native editing.

Mock-only interactive terminal demonstration; no helper, Photos library, or
filesystem changes:

```sh
npm run build
node examples/confirmation-demo.mjs
```

For the actual desktop confirmation UI, use the separate JSON-lines demo server:

```sh
npm run build
npm run agent:confirmation-demo-server
```

It uses the same request/event/result protocol as the production server. Submit
only this mock AAC input to display a destructive confirmation safely:

```json
{"type":"submit","requestId":"demo-1","input":{"source":"aac","intent":"TEST_ONLY_DELETE"}}
```

The UI must render the exact `action`, `risk`, message, and expiry from the
`confirmation_required` event, with separate Cancel and Confirm controls. Each
control sends a `confirm` request with a fresh request ID. Dismiss the prompt on
every `confirmation_resolved` event and on disconnect. The mock server records
one inert `launch_app` action after approval; it does not launch an app or delete
anything. Cancellation, expiry, replay, changed context, and disconnect execute
nothing. Automated coverage verifies cancellation, one approval, and replay
rejection through the real child-process entry point; the gate/transport suite
covers expiry, changed context, and disconnect.

The production `server.js` neither imports this mock entry point nor recognizes
`TEST_ONLY_DELETE`; its accepted inputs and native behavior remain unchanged.
Never map untrusted request fields to skill effects or executable actions.

## Delivery status

- #2: implemented, tested, and committed; Canvas opening was verified manually.
- #6: native adapter, persistent transport, protocol documentation, and runnable
  client are implemented. Actual School tile/text UI integration remains with the
  interface teammate; the issue is not complete until both UI paths pass.
- #7: deterministic navigation and synthetic fixtures pass automated checks. The
  native localhost run from Codex reached the helper but failed with Accessibility
  permission denied. Run the documented smoke command from an authorized terminal,
  then verify the real Canvas account manually before considering the issue done.
- #9: agent gate and transport are implemented and tested with simulated actions.
  A separate mock-only JSON-lines server is available for the teammate-owned
  Cancel/Confirm UI. Full UI acceptance remains pending until that UI is present.

The shipped code remains deterministic. AI integration and infrastructure work
are deferred. Generated files in `dist/` are build artifacts; edit `packages/agent/src`.

## Action history — Person 2 task P2-5

`agent.getHistory()` returns independent copies of the latest 100 completed
controller attempts, in order. Entries include `id`, `action`, `success`,
`timestamp`, and `completedAt` (milliseconds since the Unix epoch). A failed
outcome records what the controller reported; it does not prove an interrupted
action had no side effects. In-flight actions are absent until they settle.

History is in-memory only. Typed text is replaced with `[redacted]`; URLs retain
only their HTTP(S) origin, without credentials, paths, query strings, or fragments.
Raw user input, snapshots, and error text are not retained. History is display-only
and must never be used to replay actions. There is no unredacted history endpoint.

Pending, cancelled, expired, and rejected approvals are not controller attempts.
An approved action is recorded once, including controller failure. Unknown inputs
and busy requests do not add entries. `agent.clearHistory()` clears existing
entries and suppresses late records from currently running attempts without
cancelling those actions. `agent.dispose()` clears history and prevents late writes.

The desktop debug view may send these requests without interrupting active work:

```json
{"type":"get_history","requestId":"history-1"}
{"type":"clear_history","requestId":"history-2"}
```

Both respond with `{ "type": "history", "requestId": "...", "entries": [...] }`;
clearing returns an empty list. No history is emitted automatically on the protocol.
For a local preview using a mock controller:

```sh
npm run agent -- --history "Show me dog photos"
```

Place `--history` before other flags, for example `--history --native --aac OPEN_SCHOOL`.
See the [Person 2 checklist](../../docs/person-2-progress.md) for implemented,
unverified, deferred, and optional work from the broader engineering plan.

## Repeatable mock Courses workflow — Person 2 tasks P2-1 / P2-2

The CLI and server default to `CanvasMockComputerController`, which uses the
synthetic dashboard, Courses, and login fixtures. Opening Canvas resets the mock
dashboard; a valid Courses click reveals All Courses. Every snapshot replaces
its element IDs, and stale IDs fail, matching the native session constraint.

```sh
npm run agent -- --history "Open Canvas and go to Courses"
```

Expect `thinking`, two `acting` events, `done`, and history containing one URL-open
and one click. This command does not open a browser or require Accessibility
permission. It proves routing and state transitions against fixtures, not live
Canvas behavior. The same mock is available through `agent:server`. Other existing
mock skills still record actions; only Canvas navigation has simulated UI changes.

For a login/missing-control scenario, use
`new CanvasMockComputerController("login")`; the agent must return a sign-in/help
message without clicking. The basic `MockComputerController(result?, state?)`
remains available for custom static state and failure tests.

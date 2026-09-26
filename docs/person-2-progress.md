# Daniel — Person 2 progress

This tracks Daniel's responsibilities from the engineering plan previously supplied
in this session, alongside the assigned GitHub issues. The original Desktop copy
was unavailable when this checklist was created; it is not copied into the repo.
"Implemented" means code exists and is tested, not that the complete team demo or
GitHub issue has passed acceptance. Continue using deterministic behavior first.

## Assigned issues

| Issue | Agent-side status | Remaining acceptance |
| --- | --- | --- |
| [#2: Canvas skill](https://github.com/silas-c/nora/issues/2) | Implemented and published; text/AAC mock checks pass. Canvas opening was manually verified. | Team review/issue bookkeeping. |
| [#6: UI integration](https://github.com/silas-c/nora/issues/6) | Persistent helper, JSON-lines transport, request IDs, lifecycle cleanup, client example, protocol documentation, and UI acceptance checklist are implemented. | The UI is not present in this checkout or any fetched remote branch. Interface teammate connects School/text controls and verifies both UI paths. |
| [#7: Courses navigation](https://github.com/silas-c/nora/issues/7) | Deterministic selection, bounded observations, single click, post-action verification, three synthetic fixtures, and error tests are implemented. On 2026-09-26 the existing helper reached the disposable smoke workflow, then returned its actionable Accessibility-permission error. | Enable Accessibility for the helper's host and rerun localhost smoke, then verify both text and AAC against live Canvas. A fresh helper build is also blocked locally by a mismatched Swift compiler/macOS SDK toolchain. |
| [#9: Confirmation](https://github.com/silas-c/nora/issues/9) | Risk gate, immutable single-use approvals, expiry/cancel/disconnect handling, protocol, interactive demo, and separate mock-only JSON-lines server are implemented. The child-process regression proves cancel = 0 actions, approval = 1, replay = 0 additional actions. | Interface teammate connects exact-action Cancel/Confirm UI to the demo server and validates expiry/disconnect rendering. Native sensitive targeted actions remain limited by temporary IDs; do not claim them verified. |

## Engineering-plan tasks

| Task | Status and boundary |
| --- | --- |
| P2-1: Mock controller | Implemented; basic injectable snapshots plus a fixture-backed Canvas state machine used by the CLI/server. Models successful Courses navigation, login, and stale IDs without a native helper. |
| P2-2: Intent router | Implemented for Canvas/Courses, public dog images, known app launches, and zoom. Generic OPEN_APP/OPEN_WEBSITE routing, volume, COMPUTER_USE, and REASON routes remain future work. Unknown requests fail without executing. |
| P2-3: Skill registry | Implemented as a typed deterministic registry plus trusted injection for mock tests. OPEN_CANVAS and ZOOM_IN work; known app launches cover Edge, Finder, and Photos. This is not a generalized natural-language skill matcher. |
| P2-4: Jev / chooseNextAction | **Not implemented.** Deferred by Daniel's deterministic-first decision until native navigation and confirmations are reliable. No SDK, model calls, or credentials are currently used. |
| P2-5: Action history | Implemented: timestamps and controller outcomes, up to 100 redacted in-memory entries; API, JSON-lines access, and optional CLI display. No raw input, state snapshots, or local log files. |
| P2-6: Confirmations | Agent portion implemented; UI portion and full integration remain pending under #9. |
| P2-7: Optional planner | Not started; intentionally deferred. |

The initial TypeScript package, Agent interface, event subscriptions, three mock
state fixtures, and maximum-step protection are implemented. Logging/debug support
is currently the structured event stream and redacted history, not a debug UI.

## Still optional / later

- Personalized alias configuration/resolution (current phrases are fixed synonyms).
- Jev confidence thresholds and bounded model-output validation, once Jev is added.
- Adaptive recovery beyond stopping with actionable errors; never blindly retry an
  action after a timeout or ambiguous result.
- Larger-model planning/DeepSeek, only after core navigation works.

## Work order

1. Enable the native test context's Accessibility permission and run the disposable
   smoke test from the [agent guide](../packages/agent/README.md); then verify Canvas.
2. Finish #6 and #9 acceptance with the interface teammate using the existing
   transport, shared types, client example, and `agent:confirmation-demo-server`.
3. Add Jev only after those prerequisites are reliable; implement against synthetic
   states before allowing live control. No larger-model planner is needed for #7.
4. Revisit aliases and recovery if the demo needs them. Keep infrastructure and new
   demo skills off the critical path.

Daniel owns `packages/agent` and coordinating its shared contract. Silas owns the
native helper. The interface teammate owns controls, speech capture, alias editing,
status display, and confirmation dialogs. Do not close shared issues on agent-only
verification, and do not add real file deletion to the simulated safety demo.

## Acceptance run — 2026-09-26

- `npm test`: 62/62 pass, including the mock confirmation child-process entry.
- `swift build --package-path apps/macos-helper`: blocked before compiling Nora by
  installed Swift compiler/macOS SDK version mismatch. The sandbox-local cache
  restriction is secondary; the reported toolchain versions do not match.
- `node dist/agent/src/native-navigation-smoke.js`: existing helper opened the
  workflow and returned the documented Accessibility permission error. No
  screenshot or account content was recorded.
- Git remote: fetched successfully; local `main` matches `origin/main`. No desktop
  UI branch is available, so UI-owned acceptance cannot be performed in this
  checkout without inventing or taking over the teammate's interface.

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
| [#6: UI integration](https://github.com/silas-c/nora/issues/6) | Persistent helper, JSON-lines transport, request IDs, lifecycle cleanup, client example, and protocol documentation are implemented. | Interface teammate connects School/text controls and verifies both UI paths. |
| [#7: Courses navigation](https://github.com/silas-c/nora/issues/7) | Deterministic selection, bounded observations, single click, post-action verification, three synthetic fixtures, and error tests are implemented. | Native localhost smoke and live Canvas verification. Helper still reports Accessibility permission disabled in the assistant's execution context. |
| [#9: Confirmation](https://github.com/silas-c/nora/issues/9) | Risk gate, immutable single-use approvals, expiry/cancel/disconnect handling, protocol, and mock demonstration are implemented. Approval/reuse behavior was manually verified. | Interface teammate connects Cancel/Confirm and validates the complete flow. Native sensitive targeted actions remain limited by temporary IDs; do not claim them verified. |

## Engineering-plan tasks

| Task | Status and boundary |
| --- | --- |
| P2-1: Mock controller | Implemented; injectable static snapshots and navigation scenario tests. No native helper required for tests. |
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
   transport, shared types, client example, and mock confirmation example.
3. Add Jev only after those prerequisites are reliable; implement against synthetic
   states before allowing live control. No larger-model planner is needed for #7.
4. Revisit aliases and recovery if the demo needs them. Keep infrastructure and new
   demo skills off the critical path.

Daniel owns `packages/agent` and coordinating its shared contract. Silas owns the
native helper. The interface teammate owns controls, speech capture, alias editing,
status display, and confirmation dialogs. Do not close shared issues on agent-only
verification, and do not add real file deletion to the simulated safety demo.

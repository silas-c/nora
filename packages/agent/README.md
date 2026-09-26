# Nora agent — Daniel / Person 2

Deterministic Canvas routing for issue #2. No AI model or API key is required.
The agent accepts text or voice transcripts (“Open Canvas”) and the AAC intent
`OPEN_SCHOOL`, then executes the Canvas skill through an injected controller.
The mock controller records actions without opening a browser.

From the repository root, with Node.js and npm installed:

```sh
npm ci
npm test
npm run agent -- "Open Canvas"
npm run agent -- --aac OPEN_SCHOOL
```

Both inputs produce `open_url` for `https://canvas.temple.edu` in Microsoft Edge.
Subscribers receive `thinking`, `acting`, then `done` or `error`. Unknown inputs
execute nothing. Overlapping requests return a busy result without interrupting
the running request's events. Use `subscribe()`'s returned function to unsubscribe.

Native helper and UI integration follow in issue #6. `done` means the controller
reported success, not that a page load or login was verified.

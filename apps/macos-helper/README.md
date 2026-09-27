# macOS helper

Run with `swift run mac-helper` from this directory. The process reads one JSON request per line from standard input and writes one JSON response per line to standard output.

For Accessibility-backed development, package the built executable with a stable
app identity, then add the resulting app—not the raw build product—to System
Settings > Privacy & Security > Accessibility:

```sh
swift build
sh scripts/package_app.sh
```

The bundle is `.build/NoraMacHelper.app` with identifier `ai.nora.mac-helper`.
The agent and native smoke command prefer its embedded helper automatically. The
first snapshot also asks macOS to display its Accessibility authorization prompt.

Supported requests:

```json
{"type":"open_url","url":"https://canvas.temple.edu","browser":"Microsoft Edge"}
{"type":"launch_app","app":"Microsoft Edge"}
{"type":"focus_app","app":"Microsoft Edge"}
{"type":"get_state"}
{"type":"snapshot"}
{"type":"click","target":"e1","snapshotGeneration":"GENERATION_FROM_SNAPSHOT"}
{"type":"type_text","target":"e2","snapshotGeneration":"GENERATION_FROM_SNAPSHOT","text":"hello"}
{"type":"type_text","text":"hello"}
{"type":"keypress","key":"ENTER","modifiers":["CMD"]}
{"type":"scroll","direction":"down","amount":3}
```

`browser` is optional; without it, `open_url` uses the default browser. URLs must use `http` or `https`. The app name must match an installed app.

Successful actions return `{"success":true}`. `get_state` reports `activeApp` and `accessibilityTrusted`. `snapshot` adds a unique `snapshotGeneration`, `activeWindow`, `elements`, and `truncated`. Each element has a temporary `id`, `role`, optional `label`, `enabled`, and available `actions`.

`snapshot` requires macOS Accessibility permission. If it is denied, the JSON error explains where to grant it. For Edge, the helper briefly waits for webpage controls to appear; if they remain unavailable, the error points to `edge://accessibility`. Any failed request returns `{"success":false,"error":"..."}`. The active app is reported at the moment the request runs, so callers should request state after app activation completes.

`click` and targeted `type_text` require both an ID and generation from the latest snapshot in the same helper process. The helper atomically checks the generation, active app/window, enabled state, and—when the native controller supplies them—the expected role, label, and action list. It consumes the generation before attempting the action, so the request cannot be replayed; take a fresh snapshot before another targeted action. `type_text` replaces the value of the target field, or the focused text field when no target is supplied. `keypress` accepts Enter, Tab, Space, Backspace, Escape, arrow keys, `+`, `=`, `-`, and the letters A, C, L, R, T, V, W; modifiers may be CMD, SHIFT, ALT, or CTRL. IDs also become stale after another snapshot or a window change.

`focus_app` brings an already running app to the front. `scroll` acts on the active app; direction is up, down, left, or right. The optional `amount` defaults to 3 lines and is capped at 20 lines per request.

Quick check without launching an app:

```sh
printf '%s\n' '{"type":"launch_app"}' '{"type":"get_state"}' | swift run mac-helper
```

To check native actions end to end, install Microsoft Edge, grant Accessibility permission to the terminal running the helper, then run `python3 scripts/smoke.py` from this directory. The script serves a disposable page on localhost, opens it in Edge, exercises the helper, and prints `PASS` when the observed page behavior matches the actions. It uses the active desktop while running.

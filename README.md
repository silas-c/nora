# Nora

Nora is a macOS accessibility layer that turns voice, text, and AAC inputs into bounded computer actions. The first team integration target is **Open Canvas in Microsoft Edge**.

## Team starting points

- **macOS controller (Silas):** maintain `apps/macos-helper`, which now provides app launch/focus, URL opening, accessibility snapshots, click, text, keypress, and scroll actions.
- **Agent (Daniel):** `packages/agent` provides deterministic skills, bounded Courses navigation, a persistent helper connection, UI JSON-lines transport, and confirmation enforcement. See the [agent guide](packages/agent/README.md) for setup, protocol, tests, and remaining UI/native verification.
- **HCI / interface:** send `UserInput` to the agent and render its `AgentEvent` updates. Start with one large School button and clear acting/done/error feedback.

## Helper protocol

The Swift helper reads one JSON request per line from standard input and writes one JSON response per line to standard output. It keeps running until input closes. Errors are returned as responses so the caller can continue.

Request:

```json
{"type":"open_url","url":"https://canvas.temple.edu","browser":"Microsoft Edge"}
```

Response:

```json
{"success":true}
```

On failure:

```json
{"success":false,"error":"A useful error message"}
```

The helper accepts `http` and `https` URLs. Omit `browser` to use the default browser. See [the helper README](apps/macos-helper/README.md) for all actions and the snapshot response. `get_state` reports the active app and Accessibility permission; `snapshot` provides a one-shot generation token plus temporary element IDs for `click` and targeted `type_text`. Native targeted actions are atomically rejected if the generation, app, window, or selected control changed.

## Build and run on macOS

```sh
cd apps/macos-helper
swift build
swift run mac-helper
```

Enter the request JSON above and press Return. The helper opens the URL and prints its response. Xcode can also open `apps/macos-helper/Package.swift`.

To check the protocol without opening a browser:

```sh
printf '%s\n' '{"type":"open_url","url":"ftp://example.com"}' | swift run mac-helper
```

This should return a JSON error about requiring an `http` or `https` URL.

The [LICENSE](LICENSE) reserves rights in the project materials. Team members authorized by Silas Carvalho may work on the project for development and hackathon presentation.

An optional bounded Jev adapter is under development in issues #15–#17. It is not
part of the normal deterministic routes. Native model-selected navigation is
available only through the constrained `--native --jev` developer command.

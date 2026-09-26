# Nora

Nora is a macOS accessibility layer that turns voice, text, and AAC inputs into bounded computer actions. The first working path is **Open Canvas in Microsoft Edge**.

## Team starting points

- **macOS controller (Silas):** extend `apps/macos-helper` with native computer actions. The first action is `open_url`.
- **Agent:** use the types in `packages/shared/src/types.ts` to route “Open Canvas” to `open_url`. Start with a mock controller, then connect to the Swift helper.
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

Only `open_url` is implemented in the first version. The helper accepts `http` and `https` URLs. Omit `browser` to use the default browser.

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

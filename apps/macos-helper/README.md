# macOS helper

Run with `swift run mac-helper` from this directory. The process reads one JSON request per line from standard input and writes one JSON response per line to standard output.

Supported requests:

```json
{"type":"open_url","url":"https://canvas.temple.edu","browser":"Microsoft Edge"}
{"type":"launch_app","app":"Microsoft Edge"}
{"type":"get_state"}
```

`browser` is optional; without it, `open_url` uses the default browser. URLs must use `http` or `https`. The app name must match an installed app.

Successful actions return `{"success":true}`. `get_state` returns `{"success":true,"activeApp":"Microsoft Edge"}` when Edge is frontmost. Any failed request returns `{"success":false,"error":"..."}`. The active app is reported at the moment `get_state` runs, so callers should request state after app activation completes.

Quick check without launching an app:

```sh
printf '%s\n' '{"type":"launch_app"}' '{"type":"get_state"}' | swift run mac-helper
```

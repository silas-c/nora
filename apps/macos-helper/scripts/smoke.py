#!/usr/bin/env python3
"""Exercise the Swift helper against a disposable page in Microsoft Edge."""

import json
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


PAGE = b"""<!doctype html><html lang="en"><meta charset="utf-8">
<title>Nora Smoke</title>
<input id="input" aria-label="Test input">
<button id="show" onclick="this.textContent='Typed: '+document.getElementById('input').value">Show typed value</button>
<button id="click" onclick="this.textContent='Clicked'">Click me</button>
<button id="key">Key: none</button>
<button disabled>Disabled button</button>
<a href="/next">Next page</a>
<div style="width:3000px;height:3000px"></div>
<script>
document.addEventListener('keydown', e => document.getElementById('key').textContent='Key: '+(e.metaKey?'CMD+':'')+e.key);
addEventListener('scroll', () => document.title=`Nora Smoke ${scrollX} ${scrollY}`);
</script></html>"""


class PageHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = PAGE if self.path == "/" else b'<title>Nora Next Page</title><p>Navigation worked.</p>'
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def main():
    helper_dir = Path(__file__).resolve().parents[1]
    subprocess.run(["swift", "build"], cwd=helper_dir, check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), PageHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    process = subprocess.Popen(
        [str(helper_dir / ".build/debug/mac-helper")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    )

    def call(request):
        process.stdin.write(json.dumps(request) + "\n")
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise AssertionError("Helper exited without a response")
        return json.loads(line)

    def ok(request):
        response = call(request)
        assert response["success"], (request, response)
        return response

    def find(state, label):
        return next(item for item in state["elements"] if item.get("label") == label)

    def wait_for(label):
        for _ in range(15):
            state = call({"type": "snapshot"})
            if not state["success"]:
                assert any(message in state["error"] for message in (
                    "no accessible window", "did not expose webpage controls"
                )), state
                time.sleep(0.2)
                continue
            if any(item.get("label") == label for item in state["elements"]):
                return state
            time.sleep(0.2)
        raise AssertionError(f"Element did not appear: {label}")

    try:
        url = f"http://127.0.0.1:{server.server_port}/"
        ok({"type": "open_url", "url": url, "browser": "Microsoft Edge"})
        for _ in range(15):
            response = call({"type": "focus_app", "app": "Microsoft Edge"})
            if response["success"]:
                break
            assert response["error"] == "App is not running: Microsoft Edge", response
            time.sleep(0.2)
        else:
            raise AssertionError("Microsoft Edge did not launch")
        state = wait_for("Test input")
        assert state["activeApp"] == "Microsoft Edge", state["activeApp"]
        field = find(state, "Test input")["id"]
        show = find(state, "Show typed value")["id"]
        disabled = find(state, "Disabled button")["id"]
        assert "disabled" in call({"type": "click", "target": disabled})["error"]
        ok({"type": "type_text", "target": field, "text": "hello"})
        ok({"type": "click", "target": show})
        state = wait_for("Typed: hello")
        assert "stale" in call({"type": "click", "target": show})["error"]

        ok({"type": "click", "target": find(state, "Test input")["id"]})
        for _ in range(10):
            response = call({"type": "type_text", "text": "keyboard"})
            if response["success"]:
                break
            assert response["error"] == "Focused control is not a text input", response
            time.sleep(0.1)
        else:
            raise AssertionError("Text input did not receive focus")
        ok({"type": "click", "target": find(state, "Typed: hello")["id"]})
        state = wait_for("Typed: keyboard")
        ok({"type": "click", "target": find(state, "Test input")["id"]})
        ok({"type": "keypress", "key": "A", "modifiers": ["CMD"]})
        state = wait_for("Key: CMD+a")
        ok({"type": "click", "target": find(state, "Click me")["id"]})
        wait_for("Clicked")

        ok({"type": "scroll", "direction": "down", "amount": 4})
        ok({"type": "scroll", "direction": "right", "amount": 4})
        for _ in range(15):
            state = ok({"type": "snapshot"})
            position = re.search(r"Nora Smoke (\d+) (\d+)", state["activeWindow"] or "")
            if position and all(int(value) > 0 for value in position.groups()):
                break
            time.sleep(0.2)
        else:
            raise AssertionError("Page did not scroll down and right")

        next_id = find(state, "Next page")["id"]
        ok({"type": "click", "target": next_id})
        for _ in range(15):
            state = ok({"type": "snapshot"})
            if state["activeWindow"].startswith("Nora Next Page"):
                break
            time.sleep(0.2)
        else:
            raise AssertionError("Navigation did not complete")
        assert "stale" in call({"type": "click", "target": next_id})["error"]
        print("PASS: snapshot, click, text, keypress, scroll, navigation, and errors")
    finally:
        process.stdin.close()
        process.wait(timeout=5)
        server.shutdown()


if __name__ == "__main__":
    main()

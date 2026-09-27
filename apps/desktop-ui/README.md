# Nora desktop UI

The human-facing layer for Nora: a floating macOS panel for AAC tiles, typed requests, and spoken feedback. It never becomes the active app, so shortcuts such as zoom still reach the app the person is using.

## Run

From the repository root, Node and the Swift helper are built automatically:

```sh
apps/desktop-ui/scripts/run.sh
```

That opens Nora in **practice mode**. The real agent runs against a synthetic computer, so nothing on this Mac changes. Use it to demo the School tile, typed requests, repair choices, and the confirmation prompt.

Live control of this Mac:

```sh
apps/desktop-ui/scripts/run.sh --live
```

Put `TYPESAFE_API_KEY` in the repository's `.env.local` before launching. Exact built-in phrases run locally; Nora uses Jev to interpret other typed and spoken requests against its supported actions, including requests such as “open Edge and Canvas and my data structures class”, where Jev also picks the matching class from the ones Canvas shows. Without the key, exact built-in phrases and tiles still work. Practice mode uses the same routing.

Add `DEEPSEEK_API_KEY` to `.env.local` for requests no built-in task covers, such as “check Hacker News in Edge” or “open GitHub Copilot and pick a project”. Nora then works like a person at the keyboard, one step at a time: it reads the front window, DeepSeek V4.1 Flash (`deepseek-flash`) picks one step (open an app, click a control, type into a field, press a key, or scroll), Nora takes it, and reads the screen again. The model receives actionable control labels and up to 30 short read-only text snippets from the front window so it can verify results. It only reports done when the screen shows the request finished, and stops after 12 steps. Every step goes through the same safety gate as the tiles; typing in a terminal, pressing Return in a field that isn't a search or address bar, and buttons labeled with words like Subscribe, Buy, Send, Delete, or Sign in ask first. “My browser” means your default browser. Thinking is off by default for faster steps; set `DEEPSEEK_REASONING=low` or `high` for harder tasks.

Set `NORA_RUN_LOG=1` in `.env.local` to record detailed runs locally in `~/Library/Logs/Nora/agent-runs.jsonl`. This debugging log includes requests and text chosen for typing; leave it off for private tasks. It rolls over at 5 MB.

Grant Accessibility permission to Nora when macOS asks. The build signs Nora with a local certificate (`scripts/sign.sh`, created on first run in its own keychain), so the permission survives rebuilds. Opening apps and websites can work before that; zoom and Canvas navigation need it. Double-tap **Command** to show a small listening notch: say the request and Nora runs it when you pause. The notch shows your words on the `SpeechAnalyzer` path, then Nora's current action. The full panel stays hidden while a task runs; use the notch's expand button to open it. Confirmations open the full panel automatically. Double-tap again or press **Control-H** to hide Nora. Nora stays out of the Dock (`LSUIElement`).

## What the panel does

- **School** and the other tiles submit AAC intents the agent already accepts (`OPEN_SCHOOL`, `OPEN_COURSES`, `OPEN_INTERNET`, `OPEN_PHOTOS`, `OPEN_DOG_PHOTOS`, `OPEN_FINDER`, `ZOOM_IN`, `ZOOM_OUT`).
- The text field submits a `text` input. Press `/` to jump to it.
- Status shows idle, working, done, and error, and announces each change to VoiceOver without moving focus.
- An unknown request offers tappable “Did you mean” choices instead of a dead end.
- Destructive actions wait for Cancel or Confirm. The agent enforces that pause; the panel only renders it.
- Tiles stay in fixed positions and pair a symbol with a text label. The compact panel keeps every target large enough for pointer, keyboard, and switch scanning.
- The floating panel uses the Mac's behind-window material, with native Liquid Glass on its controls where supported. Reduce Transparency makes the background opaque.

## Speech

Spoken status uses ElevenLabs Flash (`eleven_flash_v2_5`) when a key is available, then the Mac voice if the key or network is missing. Known phrases are cached under `~/Library/Caches/Nora/speech` after the first synthesis, so later playback does not wait on the network. Speech never blocks an action.

Set the key in the environment or paste it in Settings (stored in the login keychain):

```sh
ELEVENLABS_API_KEY=... apps/desktop-ui/scripts/run.sh
```

Do not commit the key. Push-to-talk uses ElevenLabs Scribe (`scribe_v2`) when a key is set. Without a key, it uses Apple's on-device `SpeechAnalyzer` on macOS 26 or later, with the older Mac speech recognizer as a fallback. The notch below the menu bar shows listening, transcription, and task progress; its buttons open the full panel or hide Nora.

## Checks

```sh
apps/desktop-ui/scripts/test.sh
apps/desktop-ui/scripts/bundle.sh
# Practice-mode walkthrough; writes a JSON report and panel images:
open "$(pwd)/apps/desktop-ui/.build/Nora.app" --args --mock --self-test /tmp/nora-self-test
```

`--diagnose` writes `~/Library/Logs/Nora/permission-check.json`, which records whether macOS charges the Nora → node → helper chain to Nora.

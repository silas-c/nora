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

Grant Accessibility permission to Nora when macOS asks. Opening apps and websites can work before that; zoom and Canvas navigation need it. Press **Option-Space** to bring the panel forward. Nora stays out of the Dock (`LSUIElement`).

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

Do not commit the key. Push-to-talk uses ElevenLabs Scribe (`scribe_v2`) when a key is set, and the Mac speech recognizer otherwise.

## Checks

```sh
apps/desktop-ui/scripts/test.sh
apps/desktop-ui/scripts/bundle.sh
# Practice-mode walkthrough; writes a JSON report and panel images:
open "$(pwd)/apps/desktop-ui/.build/Nora.app" --args --mock --self-test /tmp/nora-self-test
```

`--diagnose` writes `~/Library/Logs/Nora/permission-check.json`, which records whether macOS charges the Nora → node → helper chain to Nora.

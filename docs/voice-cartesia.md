# Voice with Cartesia

LifeTwin's onboarding is a conversation with the mascot, built for adults 65+. Voice is the main way through it: the mascot asks each question out loud, the person answers by speaking, and every answer is read back before it is saved. Typing is the fallback for people who can't or don't want to talk.

## What Cartesia does

| Part | Cartesia product | How LifeTwin uses it |
|---|---|---|
| The mascot's voice | **Sonic** text-to-speech (`sonic-3.6`, WebSocket) | Speaks every question, follow-up and read-back. Voice "Jameson", speed 0.9 and a calm emotion, so it is slower and easier to follow. Audio plays through the phone's loudspeaker. |
| Hearing the answer | **Ink** speech-to-text (`ink-2`, WebSocket) | Streams the microphone in 100 ms pieces while the Talk button is held or tapped on, and shows the words on screen as they arrive. When the person pauses, the app sends `finalize` so the sentence completes on screen without waiting for Stop. |
| Keeping the key safe | **Access tokens** (`POST /access-token`) | The server mints a 5-minute token (`POST /api/voice/token`). The phone connects to Cartesia directly with it; the API key never leaves the server. |

What Cartesia does **not** do: understanding answers. Ink's transcript goes to the LifeTwin server, whose deterministic parser (and, only with separate consent, an AI helper) turns it into a value. The value is always read back ("Height: 5 feet 10 inches. Is that right?") and saved only after a yes.

## Responsible use

- Nothing is recorded before consent. The first screen says that speech is sent to Cartesia only while the Talk button is on, and offers "Type instead".
- The AI helper (a separate LLM) is its own opt-in, and can only point at words the person actually said.
- No health values are logged by the server; the access log has method, path and status only.

## Setup

For the hosted backend, plain `flutter run` from `app/` loads the optional local
public `assets/config/backend.json` at startup. See [iOS testing](ios-testing.md)
for its one-time setup. Alternatively, use `bash scripts/run-app.sh -d "iPhone 18 Pro"` from
the repository root (or `scripts/ios-device.sh` for a connected phone). The
helper loads the ignored `.env.deploy/flutter.json`, including the public
Supabase gateway key. See [iOS testing](ios-testing.md) for configuration.
Provider credentials stay on the backend.

For a local Python server:

1. Put `CARTESIA_API_KEY` and `CARTESIA_VOICE_ID` in `.env` (see `.env.example`).
2. Run the server: `uv run uvicorn lifetwin.app:app --host 0.0.0.0 --port 8000`.
3. Build the app with the server address, for example `--dart-define=API_BASE_URL=http://<usb-link-ip>:8000,http://<mac>.local:8000`. Several addresses, separated by commas, are checked at once and the first one that answers is used. See [ios-testing.md](ios-testing.md).

Without a Cartesia key, `/api/voice/token` returns 503 and the app switches to typing.

## Known limitations

- Ink holds back the last word or two until it hears more. The pause detector covers the common case, but in a very noisy room the pause may not be noticed until Stop.
- To interrupt the mascot, the person presses Talk, which stops playback. Simply talking over it does not stop it. This has not been confirmed on a phone yet.
- English only for now.
- A voice usability test with older adults is planned (issue #13) and has not been run yet.

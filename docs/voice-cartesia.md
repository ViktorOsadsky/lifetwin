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

## Background noise and other voices

### Browser playback

Web builds select a Web Audio PCM player through a conditional import. Native
builds retain `FlutterPcmSoundPlayer` and its existing audio-session behavior.
The browser player converts Cartesia's mono PCM16 little-endian stream to float
samples, retaining split sample bytes across chunks. It schedules one-shot
sources against the audio context clock at the supplied sample rate; the browser
resamples for its output device. Completion follows source `ended` events.
Stop cancels queued sources and releases waiters; replay uses the existing
in-memory Cartesia audio cache. The audio queue is bounded to 60 seconds.

One audio context is shared per page. Pointer, click and keyboard gestures unlock
it before asynchronous voice requests; unlocking alone plays no sound, accesses
no microphone and sends no data. Existing voice consent still controls Cartesia
traffic. If browser audio stays suspended, startup times out and the existing
caption/typing fallback remains available. See [AudioContext resume](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume)
and [scheduled audio sources](https://developer.mozilla.org/en-US/docs/Web/API/AudioBufferSourceNode/start).

For a provider-free manual browser test, build from `app/`:

```sh
flutter build web --target tool/browser_pcm_smoke.dart \
  --output build/browser-pcm-smoke --release --no-web-resources-cdn
```

Serve that output locally, click **Play test tone**, wait for **Playback finished**,
then test Stop and playing again. This checks actual Web Audio but does not
establish microphone, Cartesia-provider, Safari or iOS-browser acceptance.

### Phone input filtering

- **Phone front end.** The recorder (record_ios 2.1, `echoCancel: true`) turns on Apple's voice-processing I/O on the microphone (`setVoiceProcessingEnabled`: echo cancel and noise suppression; `autoGain` is its AGC) on a `playAndRecord` + `defaultToSpeaker` session. Mochi's voice plays on a separate `playback` session, set up again after every listen, so voice processing never quiets it. Nothing in the app ducks other audio; both sessions are non-mixable, so other apps' audio stops instead.
- **Voice Isolation.** While the microphone is open, a "Reduce background noise" link under "Mochi listens only on this screen." opens the iPhone's Mic Mode menu (`AVCaptureDevice.showSystemUserInterface(.microphoneModes)`, channel `lifetwin/mic_mode`). iOS remembers the choice for the app. Voice Isolation is the strongest filter for a TV or other people.
- **Gate** (`lib/voice/heard_gate.dart`, inside the STT input). The first 300 ms after the microphone opens, and sound already going when it opened (up to 1 s, until the first quiet moment), go to Ink as silence. A caption counts only after about 200 ms of voice-level audio and only with a real word: sound labels like `[noise]` and hesitations like "um" alone never start the end-of-turn wait. An unchanged caption does not restart that wait. A transcript piece with `confidence` under 0.4 is dropped; Ink's documented transcript has no confidence (only optional `words` timings), so that check is a no-op today. Hands-free, a turn is sent after 30 s even if new words keep coming.
- **Someone else talking.** Whether a heard reply is the person or a TV is a model decision on the server. The app already handles a reply field **`off_topic: true`** on `/api/onboarding/turn` and `/api/checkin/turn`: nothing new is shown as the question, the screen shows "Sorry, I think I heard someone else. Could you say that again?", Mochi says it once per question and listens again (a repeat just listens again). The server should send the same `state` back unchanged, record nothing, and may leave `message` as the open question. The server does not send it yet.
- The levels (onset 600, voice 300 RMS of 32768) are not measured on a phone yet; `stt gated` lines in the voice log show what was held back.

## Known limitations

- Ink holds back the last word or two until it hears more. The pause detector covers the common case, but in a very noisy room the pause may not be noticed until Stop.
- To interrupt the mascot, the person presses Talk, which stops playback. Simply talking over it does not stop it. This has not been confirmed on a phone yet.
- English only for now.
- A voice usability test with older adults is planned (issue #13) and has not been run yet.

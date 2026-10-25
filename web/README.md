# LifeTwin web

Two static pages, no build step:

- `index.html`: the public landing page.
- `demo/`: **Try to trick Pip**, the judge booth for a laptop at the table. Judges type everyday answers; the real keyless parser understands them, asks again, or asks for a unit, and nothing is kept without a yes. Then a fortune scene (placeholder numbers, labeled) and the reviewed quiz, whose wrong answers change only game health.

`shared/` holds the art kit (`art.js`: twin, Pip, habitat, magic ball, icons, ported from the Flutter painters on the design branch), tokens and the two OFL fonts. `shared/art-preview.html` renders every variant for QA.

## Run the booth

From the repository root, start the backend with this page's origin allowed:

```sh
CORS_ORIGINS="http://127.0.0.1:5173" uv run uvicorn lifetwin.app:app --host 127.0.0.1 --port 8000 --no-access-log
python3 -m http.server 5173 --bind 127.0.0.1 --directory web
```

Open <http://127.0.0.1:5173/demo/> full screen. It starts in an attract loop that sends a short script to the live parser; any key or click hands control to the judge, and 60 seconds idle returns to the loop.

- `?api=https://…` points at another backend (add that page origin to its `CORS_ORIGINS`).
- `?replay` forces the offline mode. It also starts automatically when `/health` can't be reached, or when the connection drops mid-demo; the badge then reads "Offline · recorded run" and typing is disabled.
- The recording and the quiz bank for offline mode are in `demo/replay.json`, captured from the keyless backend at `main` 8a8c6d2. Re-record after parser changes, so the replay shows current behavior.

## What is real

| Part | Status |
| --- | --- |
| Intake wording, read-back, unit questions, corrections, skip | Live `POST /api/onboarding/turn` (guided mode, no LLM) |
| "Kept without your yes" counter | Computed in the page from each real response: a value counts if it became confirmed without having been read back first. It should stay 0. |
| Quiz questions, answers, sources, game-health effects | Live `GET /api/quiz/questions`; scored locally |
| Outlook numbers and curve | Placeholders. Prediction is deferred; nothing is computed |
| Voice | Phone app only |

Judges' text goes to our server only. The server keeps no conversation state and the page keeps it in memory. The input says not to type real details.

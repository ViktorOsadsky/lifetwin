# Browser Cartesia playback

Track C. Owner requested a browser-only player; native audio and all health/model
contracts remain unchanged. `CartesiaSpeechOutput` conditionally selects the
Web Audio adapter on JS/Wasm builds and retains the native plugin elsewhere.
`PcmPlayer` is re-exported at its existing import path for callers and test fakes.
The already-locked `web` 1.1.2 package is now an explicit dependency.

The player handles PCM16 little-endian chunk boundaries, device-clock scheduling,
source drain, cancellation, stale completion events and a bounded queue. Shared
gesture listeners resume one page audio context before asynchronous requests.
Captions, voice consent, token minting, provider keys and the existing replay
cache are preserved. Player feed failures now reach the bounded voice error path
instead of becoming unhandled asynchronous stream errors.

Validation: focused PCM/Cartesia/controller tests and release web builds; the
manual browser smoke played a three-second synthetic tone, reached source drain,
stopped immediately, and played again after cancellation. Browser error/warning
logs were empty. See the [voice guide](../voice-cartesia.md#browser-playback) for
the repeatable provider-free smoke command. This is not a physical speaker,
microphone, Safari or full hands-free acceptance claim.

PR / merge / deployment state: the browser-audio PR records the final checks and
Vercel deployment result. Deploy only compiled `app/build/web/`, excluding the
separate manual smoke build. Keep the existing verified public domains, exact
Supabase CORS origins, provider settings and Vercel access controls.

Next dependency: verify live browser Cartesia speech, then device/browser-specific
microphone permission and interruption behavior. Native screen and model owners
are unchanged.

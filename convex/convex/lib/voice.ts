// Port of server/lifetwin/voice/: mint a short-lived Cartesia access token so
// the phone never sees the API key. No audio passes through this backend.

import { type Settings, voiceConfigured } from "./config";

export const TOKEN_URL = "https://api.cartesia.ai/access-token";
export const UNAVAILABLE_MESSAGE = "Voice isn't available right now. You can keep going by typing.";

/** Voice cannot be offered; carries no provider detail by design. */
export class VoiceUnavailable extends Error {}

export async function mintToken(settings: Settings) {
  if (!voiceConfigured(settings)) throw new VoiceUnavailable();
  let token: unknown;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), settings.providerTimeoutSeconds * 1000);
  try {
    const response = await fetch(TOKEN_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${settings.cartesiaApiKey}`,
        "Cartesia-Version": settings.cartesiaVersion,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ grants: { tts: true, stt: true }, expires_in: settings.cartesiaTokenTtlSeconds }),
      redirect: "manual",
      signal: controller.signal,
    });
    if (response.status < 200 || response.status >= 300) throw new Error("HTTPStatusError");
    token = ((await response.json()) as any).token;
    if (typeof token !== "string" || !token) throw new Error("empty token");
  } catch (error) {
    // Log only the exception type: messages and bodies may echo secrets.
    console.warn(`Cartesia token request failed: ${error instanceof Error ? error.name : "Error"}`);
    throw new VoiceUnavailable();
  } finally {
    clearTimeout(timer);
  }
  return {
    schema_version: "1.0",
    token,
    expires_in: settings.cartesiaTokenTtlSeconds,
    cartesia_version: settings.cartesiaVersion,
    stt: {
      model: settings.cartesiaSttModel,
      encoding: "pcm_s16le",
      sample_rate: 16000,
      url: "wss://api.cartesia.ai/stt/websocket",
    },
    tts: {
      model: settings.cartesiaTtsModel,
      voice_id: settings.cartesiaVoiceId,
      encoding: "pcm_s16le",
      sample_rate: 24000,
      speed: settings.cartesiaTtsSpeed,
      emotion: "calm",
      url: "wss://api.cartesia.ai/tts/websocket",
    },
  };
}

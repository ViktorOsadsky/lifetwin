// Blank-by-default provider settings from Convex environment variables
// (`npx convex env set NAME value`). No credential is ever required to serve.
// FastAPI refuses to start on an invalid value; a Convex deployment cannot,
// so every non-probe route answers a redacted 500 until it is fixed.

export class ConfigError extends Error {
  constructor(readonly variable: string) {
    super(`invalid configuration: ${variable}`);
  }
}

export type Env = Record<string, string | undefined>;

export interface Settings {
  llmProvider: "openai" | "chat_completions";
  llmEndpoint: string;
  llmModel: string;
  llmApiKey: string;
  llmReasoningEffort: string;
  llmConfigured: boolean;
  tavilyApiKey: string;
  cartesiaApiKey: string;
  cartesiaVersion: string;
  cartesiaTtsModel: string;
  cartesiaSttModel: string;
  cartesiaVoiceId: string;
  cartesiaTtsSpeed: number;
  cartesiaTokenTtlSeconds: number;
  providerTimeoutSeconds: number;
  requestTimeoutSeconds: number;
  maxBodyBytes: number;
  corsOrigins: string[];
  sessionsEnabled: boolean;
}

const strip = (value: string) => value.trim();

function numberSetting(env: Env, name: string, fallback: number, check: (value: number) => boolean, integer = false): number {
  const raw = env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number(strip(raw));
  if (!strip(raw) || !Number.isFinite(value) || (integer && !Number.isInteger(value)) || !check(value)) {
    throw new ConfigError(name);
  }
  return value;
}

/** Port of Settings.exact_origins_only: explicit HTTP(S) origins only. */
export function canonicalOrigins(value: string): string[] {
  const normalized: string[] = [];
  for (const part of value.split(",")) {
    const origin = part.replace(/^ +| +$/g, "");
    if (!origin) continue;
    if (/[\s\x00-\x1f\x7f]/.test(origin)) throw new ConfigError("CORS_ORIGINS");
    const match = /^(https?):\/\/([^/?#@]+)(\/?)$/i.exec(origin);
    if (!match || origin.includes("*")) throw new ConfigError("CORS_ORIGINS");
    let url: URL;
    try {
      url = new URL(`${match[1].toLowerCase()}://${match[2]}`);
    } catch {
      throw new ConfigError("CORS_ORIGINS");
    }
    const hostPort = /^(\[[^\]]+\]|[^:]+)(?::(\d*))?$/.exec(match[2]);
    if (!hostPort || hostPort[2] === "" || (hostPort[2] !== undefined && (Number(hostPort[2]) === 0 || Number(hostPort[2]) > 65535))) {
      throw new ConfigError("CORS_ORIGINS");
    }
    // WHATWG URL canonicalizes case, IDNs (punycode) and default ports.
    const canonical = url.origin;
    if (!normalized.includes(canonical)) normalized.push(canonical);
  }
  return normalized;
}

export function loadSettings(env: Env): Settings {
  const get = (name: string, fallback = "") => env[name] ?? fallback;
  const providerRaw = strip(get("LLM_PROVIDER"));
  const llmProvider = providerRaw === "" ? "openai" : providerRaw;
  if (llmProvider !== "openai" && llmProvider !== "chat_completions") throw new ConfigError("LLM_PROVIDER");
  const effort = env.LLM_REASONING_EFFORT === undefined ? "minimal" : env.LLM_REASONING_EFFORT;
  if (!["", "minimal", "low", "medium", "high"].includes(effort)) throw new ConfigError("LLM_REASONING_EFFORT");
  const llmEndpoint = llmProvider === "chat_completions" ? strip(get("LLM_BASE_URL")) || "https://api.meta.ai/v1" : "";
  const llmModel = get("LLM_MODEL");
  const llmApiKey = get("LLM_API_KEY");
  const sessionStore = strip(get("SESSION_STORE"));
  if (sessionStore !== "" && sessionStore !== "ephemeral") throw new ConfigError("SESSION_STORE");
  return {
    llmProvider,
    llmEndpoint,
    llmModel,
    llmApiKey,
    llmReasoningEffort: effort,
    // The OpenAI Responses adapter (LLM_PROVIDER=openai) is not ported, so it
    // is never configured here: blank or "openai" means keyless guided mode.
    llmConfigured: llmProvider === "chat_completions" && Boolean(strip(llmApiKey) && strip(llmModel) && llmEndpoint),
    tavilyApiKey: get("TAVILY_API_KEY"),
    cartesiaApiKey: get("CARTESIA_API_KEY"),
    cartesiaVersion: get("CARTESIA_VERSION", "2026-08-14"),
    cartesiaTtsModel: get("CARTESIA_TTS_MODEL", "sonic-3.6"),
    cartesiaSttModel: get("CARTESIA_STT_MODEL", "ink-2"),
    cartesiaVoiceId: get("CARTESIA_VOICE_ID"),
    cartesiaTtsSpeed: numberSetting(env, "CARTESIA_TTS_SPEED", 0.9, (v) => v >= 0.6 && v <= 1.5),
    cartesiaTokenTtlSeconds: numberSetting(env, "CARTESIA_TOKEN_TTL_SECONDS", 300, (v) => v >= 60 && v <= 900, true),
    providerTimeoutSeconds: numberSetting(env, "API_PROVIDER_TIMEOUT_SECONDS", 12, (v) => v > 0 && v <= 30),
    requestTimeoutSeconds: numberSetting(env, "API_REQUEST_TIMEOUT_SECONDS", 25, (v) => v > 0 && v <= 60),
    maxBodyBytes: numberSetting(env, "API_MAX_BODY_BYTES", 32768, (v) => v >= 128 && v <= 1048576, true),
    corsOrigins: canonicalOrigins(get("CORS_ORIGINS")),
    sessionsEnabled: sessionStore === "ephemeral",
  };
}

export function voiceConfigured(settings: Settings): boolean {
  return Boolean(strip(settings.cartesiaApiKey) && strip(settings.cartesiaVoiceId));
}

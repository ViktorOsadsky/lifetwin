import type { Config } from "./providers.ts";

export const SETTING_NAMES = [
  "LLM_PROVIDER",
  "LLM_BASE_URL",
  "LLM_MODEL",
  "LLM_API_KEY",
  "LLM_ALLOW_CONTRIBUTOR",
  "LLM_REASONING_EFFORT",
  "PERSONALIZE_PROVIDER",
  "ANTHROPIC_API_KEY",
  "CLAUDE_MODEL",
  "CARTESIA_API_KEY",
  "CARTESIA_VOICE_ID",
  "CARTESIA_VERSION",
  "CARTESIA_TTS_MODEL",
  "CARTESIA_STT_MODEL",
  "CARTESIA_TTS_SPEED",
  "CARTESIA_TOKEN_TTL_SECONDS",
  "ONBOARDING_DEMO",
  "DOCUMENT_MUSE_ENABLED",
  "LIFETWIN_CORS_ORIGINS",
] as const;
let cached: { value: Config; expires: number } | undefined;

/** Prefer managed function secrets; Vault supports Bridge-only provisioning. */
export async function loadConfig(): Promise<Config> {
  if (cached && cached.expires > Date.now()) return cached.value;
  const config: Config = {};
  for (const name of SETTING_NAMES) {
    const value = Deno.env.get(name);
    if (value !== undefined) config[name] = value;
  }
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return config;
  if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)) {
    throw new Error("Invalid project configuration");
  }
  config.SUPABASE_URL = url;
  config.SUPABASE_SERVICE_ROLE_KEY = key;
  const response = await fetch(`${url}/rest/v1/rpc/lifetwin_provider_config`, {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(4000),
    headers: {
      "authorization": `Bearer ${key}`,
      "apikey": key,
      "content-type": "application/json",
    },
    body: "{}",
  });
  if (!response.ok) throw new Error("Server configuration unavailable");
  const raw = await response.text();
  if (raw.length > 65536) throw new Error("Configuration limit");
  const stored = JSON.parse(raw);
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) {
    throw new Error("Invalid server configuration");
  }
  for (const name of SETTING_NAMES) {
    if (typeof stored[name] === "string" && !config[name]) {
      config[name] = stored[name];
    }
  }
  cached = { value: config, expires: Date.now() + 60_000 };
  return config;
}

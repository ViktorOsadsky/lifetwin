/** Fixed provider destinations. Keys, prompts and responses never enter logs. */
export type Config = Record<string, string>;
export type Fetcher = typeof fetch;

/** Global project budgets count only calls, never people or health inputs. */
export async function takeBudget(
  config: Config,
  kind: "llm" | "voice",
  fetcher: Fetcher = fetch,
): Promise<boolean> {
  if (!config.SUPABASE_URL && !config.SUPABASE_SERVICE_ROLE_KEY) return true; // local tests/development
  if (
    !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(config.SUPABASE_URL || "") ||
    !config.SUPABASE_SERVICE_ROLE_KEY
  ) return false;
  try {
    const response = await fetcher(
      `${config.SUPABASE_URL}/rest/v1/rpc/lifetwin_take_provider_budget`,
      {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(3000),
        headers: {
          "content-type": "application/json",
          "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
          "authorization": `Bearer ${config.SUPABASE_SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({ provider_kind: kind }),
      },
    );
    return response.ok && await response.text() === "true";
  } catch {
    return false;
  }
}

export function selectedProvider(config: Config): "muse" | "claude" {
  return config.PERSONALIZE_PROVIDER === "claude" ||
      (!config.PERSONALIZE_PROVIDER && Boolean(config.ANTHROPIC_API_KEY))
    ? "claude"
    : "muse";
}

export function providerInfo(config: Config) {
  const provider = selectedProvider(config);
  const contributor = provider === "muse" &&
    /contributor/i.test(config.LLM_MODEL ?? "");
  const configured = provider === "claude"
    ? Boolean(
      config.ANTHROPIC_API_KEY && (config.CLAUDE_MODEL ?? "claude-haiku-5-5"),
    )
    : Boolean(
      config.LLM_API_KEY && config.LLM_MODEL &&
        (!contributor ||
          /^(true|1)$/i.test(config.LLM_ALLOW_CONTRIBUTOR ?? "false")),
    );
  return {
    provider,
    display_name: provider === "claude"
      ? "Claude by Anthropic"
      : "Muse by Meta",
    company: provider === "claude" ? "Anthropic" : "Meta",
    configured,
    may_train_on_content: contributor,
  };
}

export function consentFor(
  consent: unknown,
  provider: "muse" | "claude",
): boolean {
  if (consent === true) return provider === "muse";
  return typeof consent === "object" && consent !== null &&
    (consent as Record<string, unknown>)[provider] === true;
}

async function boundedJSON(
  response: Response,
  limit = 65536,
): Promise<unknown> {
  if (!response.ok || !response.body) throw new Error("Provider unavailable");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) throw new Error("Provider response limit");
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

function claudeSchema(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(claudeSchema);
  if (!value || typeof value !== "object") return value;
  const unsupported = new Set([
    "minLength",
    "maxLength",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "multipleOf",
    "minItems",
    "maxItems",
    "uniqueItems",
  ]);
  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    if (unsupported.has(key)) continue;
    result[key] = ["properties", "$defs"].includes(key) && child &&
        typeof child === "object"
      ? Object.fromEntries(
        Object.entries(child).map((
          [name, schema],
        ) => [name, claudeSchema(schema)]),
      )
      : claudeSchema(child);
  }
  if (result.type === "object") result.additionalProperties = false;
  return result;
}

/** Caller must gate consent and validate/ground the result before using it. */
export async function completeJSON(
  config: Config,
  system: string,
  user: string,
  schema: Record<string, unknown>,
  fetcher: Fetcher = fetch,
): Promise<unknown | null> {
  const info = providerInfo(config);
  if (!info.configured) return null;
  try {
    const claude = info.provider === "claude";
    // Arbitrary LLM_BASE_URL destinations are deliberately unsupported on this host.
    if (
      !claude && config.LLM_BASE_URL &&
      config.LLM_BASE_URL.replace(/\/$/, "") !== "https://api.meta.ai/v1"
    ) return null;
    if (!await takeBudget(config, "llm", fetcher)) return null;
    const response = await fetcher(
      claude
        ? "https://api.anthropic.com/v1/messages"
        : "https://api.meta.ai/v1/chat/completions",
      {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(6000),
        headers: claude
          ? {
            "content-type": "application/json",
            "x-api-key": config.ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
          }
          : {
            "content-type": "application/json",
            "authorization": `Bearer ${config.LLM_API_KEY}`,
          },
        body: JSON.stringify(
          claude
            ? {
              model: config.CLAUDE_MODEL || "claude-haiku-5-5",
              max_tokens: 800,
              system: [{
                type: "text",
                text: system,
                cache_control: { type: "ephemeral" },
              }],
              messages: [{ role: "user", content: user }],
              thinking: { type: "disabled" },
              output_config: {
                effort: "low",
                format: { type: "json_schema", schema: claudeSchema(schema) },
              },
            }
            : {
              model: config.LLM_MODEL,
              max_completion_tokens: 800,
              messages: [{ role: "system", content: system }, {
                role: "user",
                content: user,
              }],
              reasoning_effort: config.LLM_REASONING_EFFORT || "minimal",
              response_format: {
                type: "json_schema",
                json_schema: { name: "lifetwin_reply", strict: true, schema },
              },
            },
        ),
      },
    );
    const data = await boundedJSON(response) as Record<string, unknown>;
    if (claude) {
      if (
        data.stop_reason !== "end_turn" || !Array.isArray(data.content) ||
        data.content.length !== 1
      ) return null;
      const block = data.content[0];
      return block?.type === "text" && typeof block.text === "string"
        ? JSON.parse(block.text)
        : null;
    }
    const choices = data.choices as {
      finish_reason?: string;
      message?: { content?: string; refusal?: string };
    }[];
    return choices?.length === 1 && choices[0].finish_reason === "stop" &&
        !choices[0].message?.refusal &&
        typeof choices[0].message?.content === "string"
      ? JSON.parse(choices[0].message.content)
      : null;
  } catch {
    return null;
  }
}

/** Single-line opaque transport values; reject whitespace rather than trimming it. */
function transportValue(value: unknown, maxLength: number): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.length <= maxLength &&
    /^[\x21-\x7e]+$/.test(value);
}

export async function voiceToken(config: Config, fetcher: Fetcher = fetch) {
  const voiceId = config.CARTESIA_VOICE_ID;
  const sttModel = config.CARTESIA_STT_MODEL ?? "ink-2";
  const ttsModel = config.CARTESIA_TTS_MODEL ?? "sonic-3.6";
  const version = config.CARTESIA_VERSION ?? "2026-08-14";
  const rawTtl = config.CARTESIA_TOKEN_TTL_SECONDS ?? "300";
  const rawSpeed = config.CARTESIA_TTS_SPEED ?? "0.9";
  const requestedTtl = Number(rawTtl);
  const speed = Number(rawSpeed);
  if (
    !transportValue(config.CARTESIA_API_KEY, 16384) ||
    !transportValue(voiceId, 128) || !transportValue(sttModel, 128) ||
    !transportValue(ttsModel, 128) || !transportValue(version, 128) ||
    !/^[+-]?\d+$/.test(rawTtl) || !Number.isSafeInteger(requestedTtl) ||
    rawSpeed.trim() !== rawSpeed || !rawSpeed || !Number.isFinite(speed) ||
    speed < 0.6 || speed > 1.5
  ) return null;
  const ttl = Math.max(60, Math.min(900, requestedTtl));
  try {
    if (!await takeBudget(config, "voice", fetcher)) return null;
    const response = await fetcher("https://api.cartesia.ai/access-token", {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(12000),
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${config.CARTESIA_API_KEY}`,
        "Cartesia-Version": version,
      },
      body: JSON.stringify({
        grants: { tts: true, stt: true },
        expires_in: ttl,
      }),
    });
    const data = await boundedJSON(response) as { token?: unknown };
    if (
      !transportValue(data.token, 16384) ||
      data.token === config.CARTESIA_API_KEY
    ) return null;
    return {
      schema_version: "1.0",
      token: data.token,
      expires_in: ttl,
      cartesia_version: version,
      stt: {
        model: sttModel,
        encoding: "pcm_s16le",
        sample_rate: 16000,
        url: "wss://api.cartesia.ai/stt/websocket",
      },
      tts: {
        model: ttsModel,
        voice_id: voiceId,
        encoding: "pcm_s16le",
        sample_rate: 24000,
        speed,
        emotion: "calm",
        url: "wss://api.cartesia.ai/tts/websocket",
      },
    };
  } catch {
    return null;
  }
}

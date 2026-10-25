import assert from "node:assert/strict";
import {
  completeJSON,
  type Config,
  consentFor,
  type Fetcher,
  providerInfo,
  selectedProvider,
  voiceToken,
} from "./providers.ts";

// Entirely invented credentials and responses. Fetch is always injected: these
// tests require no network or provider credentials.
const muse: Config = {
  PERSONALIZE_PROVIDER: "muse",
  LLM_API_KEY: "invented-meta-server-key",
  LLM_MODEL: "test-model",
};
const claude: Config = {
  PERSONALIZE_PROVIDER: "claude",
  ANTHROPIC_API_KEY: "invented-anthropic-server-key",
  CLAUDE_MODEL: "test-claude-model",
};
const cartesia: Config = {
  CARTESIA_API_KEY: "invented-cartesia-server-key",
  CARTESIA_VOICE_ID: "invented-voice-id",
};
const schema = {
  type: "object",
  properties: {
    reply: { type: "string", minLength: 1, maxLength: 100 },
    count: { type: "integer", minimum: 0, maximum: 3 },
  },
  required: ["reply"],
  additionalProperties: false,
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}
function museAnswer(content = '{"reply":"grounded"}') {
  return { choices: [{ finish_reason: "stop", message: { content } }] };
}
function claudeAnswer(text = '{"reply":"grounded"}') {
  return { stop_reason: "end_turn", content: [{ type: "text", text }] };
}
function noCalls(): Fetcher {
  return () => {
    assert.fail(
      "Unconfigured, disallowed, or unconsented work must not call a provider",
    );
  };
}

Deno.test("provider selection and metadata expose no API credentials", () => {
  assert.equal(selectedProvider({}), "muse");
  assert.equal(selectedProvider({ ANTHROPIC_API_KEY: "fake" }), "claude");
  assert.equal(
    selectedProvider({ ...claude, PERSONALIZE_PROVIDER: "muse" }),
    "muse",
  );
  assert.equal(providerInfo(muse).configured, true);
  assert.equal(providerInfo(claude).configured, true);
  const contributor = providerInfo({ ...muse, LLM_MODEL: "demo-contributor" });
  assert.equal(contributor.configured, false);
  assert.equal(contributor.may_train_on_content, true);
  assert.equal(
    providerInfo({
      ...muse,
      LLM_MODEL: "demo-contributor",
      LLM_ALLOW_CONTRIBUTOR: "true",
    }).configured,
    true,
  );
  for (const config of [muse, claude]) {
    const metadata = JSON.stringify(providerInfo(config));
    assert.ok(!metadata.includes("invented-"));
  }
});

Deno.test("consent stays specific to the selected outside AI provider", () => {
  assert.equal(consentFor(true, "muse"), true); // legacy Muse-only choice
  assert.equal(consentFor(true, "claude"), false);
  assert.equal(consentFor({ muse: true }, "claude"), false);
  assert.equal(consentFor({ claude: true }, "muse"), false);
  assert.equal(consentFor({ claude: true }, "claude"), true);
  assert.equal(consentFor({ muse: true, claude: false }, "muse"), true);
  for (
    const value of [false, null, undefined, "true", 1, {}, { muse: "true" }]
  ) {
    assert.equal(consentFor(value, "muse"), false);
    assert.equal(consentFor(value, "claude"), false);
  }
});

Deno.test("missing credentials, blocked contributor models, and foreign LLM URLs make no calls", async () => {
  for (
    const config of [
      {},
      { ...muse, LLM_API_KEY: "" },
      { ...muse, LLM_MODEL: "" },
      { ...claude, ANTHROPIC_API_KEY: "" },
      { ...claude, CLAUDE_MODEL: "" },
      { ...muse, LLM_MODEL: "demo-CONTRIBUTOR" },
      { ...muse, LLM_BASE_URL: "http://api.meta.ai/v1" },
      { ...muse, LLM_BASE_URL: "https://api.meta.ai.evil.test/v1" },
      { ...muse, LLM_BASE_URL: "https://unrelated.test/v1" },
      { ...muse, LLM_BASE_URL: "https://api.meta.ai/v1?forward=elsewhere" },
    ]
  ) {
    assert.equal(
      await completeJSON(config, "system", "synthetic", schema, noCalls()),
      null,
    );
  }
});

Deno.test("Muse uses a fixed endpoint, server bearer key, strict schema and bounded request", async () => {
  const fetcher: Fetcher = async (input, init) => {
    assert.equal(input, "https://api.meta.ai/v1/chat/completions");
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    assert.ok(init?.signal instanceof AbortSignal);
    const headers = new Headers(init.headers);
    assert.equal(headers.get("authorization"), `Bearer ${muse.LLM_API_KEY}`);
    assert.equal(headers.get("x-api-key"), null);
    const body = JSON.parse(String(init.body));
    assert.equal(body.max_completion_tokens, 800);
    assert.equal(body.reasoning_effort, "minimal");
    assert.equal(body.model, muse.LLM_MODEL);
    assert.deepEqual(body.messages, [
      { role: "system", content: "approved instruction" },
      { role: "user", content: "synthetic user context" },
    ]);
    assert.deepEqual(body.response_format.json_schema.schema, schema);
    assert.equal(body.response_format.json_schema.strict, true);
    assert.ok(!String(init.body).includes(muse.LLM_API_KEY));
    return json(museAnswer());
  };
  assert.deepEqual(
    await completeJSON(
      { ...muse, LLM_BASE_URL: "https://api.meta.ai/v1/" },
      "approved instruction",
      "synthetic user context",
      schema,
      fetcher,
    ),
    { reply: "grounded" },
  );
});

Deno.test("Claude uses its fixed endpoint and sanitizes schema while retaining property names", async () => {
  const original = {
    ...schema,
    properties: {
      ...schema.properties,
      minimum: { type: "string", maxLength: 12 },
      items: {
        type: "array",
        minItems: 1,
        maxItems: 3,
        items: { type: "number", minimum: 1 },
      },
      nested: {
        type: "object",
        properties: { value: { type: "string", minLength: 1 } },
        required: ["value"],
      },
    },
  };
  const before = JSON.stringify(original);
  const fetcher: Fetcher = async (input, init) => {
    assert.equal(input, "https://api.anthropic.com/v1/messages");
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("x-api-key"), claude.ANTHROPIC_API_KEY);
    assert.equal(headers.get("authorization"), null);
    assert.equal(headers.get("anthropic-version"), "2023-06-01");
    const body = JSON.parse(String(init?.body));
    assert.equal(body.model, claude.CLAUDE_MODEL);
    assert.equal(body.max_tokens, 800);
    assert.deepEqual(body.thinking, { type: "disabled" });
    assert.equal(body.system[0].cache_control.type, "ephemeral");
    const target = body.output_config.format.schema;
    assert.deepEqual(target.properties.reply, { type: "string" });
    assert.deepEqual(target.properties.minimum, { type: "string" });
    assert.deepEqual(target.properties.items, {
      type: "array",
      items: { type: "number" },
    });
    assert.equal(target.properties.nested.additionalProperties, false);
    assert.ok(!String(init?.body).includes(claude.ANTHROPIC_API_KEY));
    return json(claudeAnswer());
  };
  assert.deepEqual(
    await completeJSON(
      { ...claude, LLM_BASE_URL: "https://unrelated.test" },
      "system",
      "synthetic",
      original,
      fetcher,
    ),
    { reply: "grounded" },
  );
  assert.equal(JSON.stringify(original), before);
});

const rejectedMuse = [
  { choices: [] },
  { choices: [museAnswer().choices[0], museAnswer().choices[0]] },
  {
    choices: [{
      finish_reason: "length",
      message: { content: '{"reply":"truncated"}' },
    }],
  },
  {
    choices: [{
      finish_reason: "stop",
      message: { content: "{}", refusal: "No" },
    }],
  },
  {
    choices: [{
      finish_reason: "stop",
      message: { content: { reply: "wrong wire type" } },
    }],
  },
  museAnswer("not JSON"),
  null,
];
for (const [index, response] of rejectedMuse.entries()) {
  Deno.test(`Muse refusal or malformed completion ${index + 1} is unavailable`, async () => {
    assert.equal(
      await completeJSON(
        muse,
        "system",
        "synthetic",
        schema,
        async () => json(response),
      ),
      null,
    );
  });
}
const rejectedClaude = [
  { stop_reason: "refusal", content: [{ type: "text", text: "{}" }] },
  { stop_reason: "max_tokens", content: [{ type: "text", text: "{}" }] },
  { stop_reason: "end_turn", content: [] },
  { stop_reason: "end_turn", content: [{ type: "tool_use", text: "{}" }] },
  {
    stop_reason: "end_turn",
    content: [{ type: "text", text: "{}" }, { type: "text", text: "{}" }],
  },
  claudeAnswer("not JSON"),
  null,
];
for (const [index, response] of rejectedClaude.entries()) {
  Deno.test(`Claude refusal or malformed completion ${index + 1} is unavailable`, async () => {
    assert.equal(
      await completeJSON(
        claude,
        "system",
        "synthetic",
        schema,
        async () => json(response),
      ),
      null,
    );
  });
}

Deno.test("network, HTTP, and outer JSON failures degrade without returning provider error details", async () => {
  const secretDetail = "invented-private-provider-error-detail";
  const failures: Fetcher[] = [
    async () => {
      throw new Error(secretDetail);
    },
    async () => new Response(secretDetail, { status: 401 }),
    async () => new Response(secretDetail, { status: 429 }),
    async () => new Response(secretDetail, { status: 503 }),
    async () => new Response(secretDetail),
    async () => new Response(null),
  ];
  for (const fetcher of failures) {
    assert.equal(
      await completeJSON(muse, "system", "synthetic", schema, fetcher),
      null,
    );
    assert.equal(
      await completeJSON(claude, "system", "synthetic", schema, fetcher),
      null,
    );
    assert.equal(await voiceToken(cartesia, fetcher), null);
  }
});

Deno.test("oversized streamed provider responses are cancelled before acceptance", async () => {
  for (
    const operation of [
      (fetcher: Fetcher) =>
        completeJSON(muse, "system", "synthetic", schema, fetcher),
      (fetcher: Fetcher) =>
        completeJSON(claude, "system", "synthetic", schema, fetcher),
      (fetcher: Fetcher) => voiceToken(cartesia, fetcher),
    ]
  ) {
    let cancelled = false;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(65536));
        controller.enqueue(new Uint8Array(1));
      },
      cancel() {
        cancelled = true;
      },
    });
    assert.equal(await operation(async () => new Response(stream)), null);
    assert.equal(cancelled, true);
  }
});

Deno.test("requests provide explicit deadlines and abort failures safely degrade", async () => {
  const realTimeout = AbortSignal.timeout;
  const deadlines: number[] = [];
  try {
    AbortSignal.timeout = (milliseconds: number) => {
      deadlines.push(milliseconds);
      return AbortSignal.abort(
        new DOMException("Synthetic deadline", "TimeoutError"),
      );
    };
    const fetcher: Fetcher = (_input, init) => {
      assert.ok(init?.signal);
      init.signal.throwIfAborted();
      assert.fail("An aborted request must not proceed");
    };
    assert.equal(
      await completeJSON(muse, "system", "synthetic", schema, fetcher),
      null,
    );
    assert.equal(
      await completeJSON(claude, "system", "synthetic", schema, fetcher),
      null,
    );
    assert.equal(await voiceToken(cartesia, fetcher), null);
    assert.deepEqual(deadlines, [6000, 6000, 12000]);
  } finally {
    AbortSignal.timeout = realTimeout;
  }
});

Deno.test("Cartesia returns only a short-lived token and approved transport settings", async () => {
  const shortLived = "invented-short-lived-access-token";
  const fetcher: Fetcher = async (input, init) => {
    assert.equal(input, "https://api.cartesia.ai/access-token");
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    assert.ok(init?.signal instanceof AbortSignal);
    const headers = new Headers(init.headers);
    assert.equal(
      headers.get("authorization"),
      `Bearer ${cartesia.CARTESIA_API_KEY}`,
    );
    const body = JSON.parse(String(init.body));
    assert.deepEqual(body, {
      grants: { tts: true, stt: true },
      expires_in: 300,
    });
    return json({
      token: shortLived,
      ignored_provider_detail: cartesia.CARTESIA_API_KEY,
    });
  };
  const response = await voiceToken(cartesia, fetcher);
  assert.ok(response);
  assert.equal(response.token, shortLived);
  assert.equal(response.expires_in, 300);
  assert.equal(response.stt.url, "wss://api.cartesia.ai/stt/websocket");
  assert.equal(response.tts.url, "wss://api.cartesia.ai/tts/websocket");
  assert.equal(response.tts.voice_id, cartesia.CARTESIA_VOICE_ID);
  assert.ok(!JSON.stringify(response).includes(cartesia.CARTESIA_API_KEY));
});

Deno.test("Cartesia requires both secret and voice ID and rejects raw-secret token echoes", async () => {
  assert.equal(await voiceToken({}, noCalls()), null);
  assert.equal(await voiceToken({ CARTESIA_API_KEY: "fake" }, noCalls()), null);
  assert.equal(
    await voiceToken({ CARTESIA_VOICE_ID: "fake" }, noCalls()),
    null,
  );
  for (
    const value of [null, {}, { token: "" }, { token: 123 }, {
      token: cartesia.CARTESIA_API_KEY,
    }]
  ) {
    assert.equal(await voiceToken(cartesia, async () => json(value)), null);
  }
});

Deno.test("Cartesia TTL remains within the supported short-lived range", async () => {
  for (
    const [configured, expected] of [["1", 60], ["300", 300], [
      "999999",
      900,
    ]] as const
  ) {
    const fetcher: Fetcher = async (_input, init) => {
      assert.equal(JSON.parse(String(init?.body)).expires_in, expected);
      return json({ token: "invented-short-lived-access-token" });
    };
    const response = await voiceToken({
      ...cartesia,
      CARTESIA_TOKEN_TTL_SECONDS: configured,
    }, fetcher);
    assert.equal(response?.expires_in, expected);
  }
});

Deno.test("invalid Cartesia numeric settings fail before spending a token mint", async () => {
  for (
    const raw of [
      "NaN",
      "Infinity",
      "-Infinity",
      "invalid",
      "",
      " ",
      "300.5",
      "3e2",
      "9007199254740992",
    ]
  ) {
    assert.equal(
      await voiceToken(
        { ...cartesia, CARTESIA_TOKEN_TTL_SECONDS: raw },
        noCalls(),
      ),
      null,
    );
  }
  for (
    const raw of [
      "NaN",
      "Infinity",
      "-Infinity",
      "invalid",
      "",
      " ",
      " 0.9",
      "0.9 ",
      "0.59",
      "1.51",
    ]
  ) {
    assert.equal(
      await voiceToken({ ...cartesia, CARTESIA_TTS_SPEED: raw }, noCalls()),
      null,
    );
  }
});

Deno.test("Cartesia identifiers are bounded nonempty transport values", async () => {
  for (
    const setting of [
      "CARTESIA_VOICE_ID",
      "CARTESIA_STT_MODEL",
      "CARTESIA_TTS_MODEL",
      "CARTESIA_VERSION",
    ]
  ) {
    for (
      const value of [
        "",
        " ",
        "with space",
        "trailing ",
        "bad\nvalue",
        "bad\u007fvalue",
        "x".repeat(129),
      ]
    ) {
      assert.equal(
        await voiceToken({ ...cartesia, [setting]: value }, noCalls()),
        null,
      );
    }
  }
  for (const key of [" ", " leading", "with\nline"]) {
    assert.equal(
      await voiceToken({ ...cartesia, CARTESIA_API_KEY: key }, noCalls()),
      null,
    );
  }
});

Deno.test("minted Cartesia credentials reject whitespace, control characters and excess length", async () => {
  for (
    const token of [
      " ",
      " leading",
      "trailing ",
      "inner space",
      "bad\nvalue",
      "bad\u007fvalue",
      "x".repeat(16385),
    ]
  ) {
    assert.equal(await voiceToken(cartesia, async () => json({ token })), null);
  }
});

Deno.test("Cartesia accepted numeric boundaries are finite and preserve configured models", async () => {
  for (const speed of ["0.6", "1.5"]) {
    const result = await voiceToken({
      ...cartesia,
      CARTESIA_TTS_SPEED: speed,
      CARTESIA_TTS_MODEL: "configured-tts-model",
      CARTESIA_STT_MODEL: "configured-stt-model",
      CARTESIA_VERSION: "2026-08-14",
    }, async () => json({ token: "invented-short-lived-access-token" }));
    assert.ok(result);
    assert.equal(result.tts.speed, Number(speed));
    assert.ok(Number.isFinite(result.tts.speed));
    assert.equal(result.tts.model, "configured-tts-model");
    assert.equal(result.stt.model, "configured-stt-model");
  }
});

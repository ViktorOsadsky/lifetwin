// Configured-provider paths, replayed against the FastAPI reference recorded
// with mock upstreams: identical outbound requests (URL, auth, JSON payload)
// and byte-identical API responses for success and every failure mode.

import { afterEach, describe, expect, test, vi } from "vitest";
import fixture from "./fixtures/parity.json";
import { call, fakeUpstream, forbidNetwork, json, mask } from "./helpers";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const llmEnv = (effort: string) => ({
  LLM_PROVIDER: "chat_completions",
  LLM_BASE_URL: "https://llm.example/v1/",
  LLM_MODEL: "muse-test",
  LLM_API_KEY: "test-llm-key",
  LLM_REASONING_EFFORT: effort,
});

describe("Chat Completions conversation guide", () => {
  for (const scenario of fixture.providers.llm) {
    test(`${scenario.name}: same upstream request and same turn responses`, async () => {
      const { seen } = fakeUpstream(scenario.upstream_status, scenario.upstream_body);
      const logs = vi.spyOn(console, "log");
      for (const row of scenario.turns) {
        const { response, text } = await call(llmEnv(scenario.effort), "POST", "/api/onboarding/turn", {
          body: JSON.stringify(row.request),
          contentType: "application/json",
        });
        expect(response.status).toBe(row.status);
        expect(mask(text)).toBe(row.response);
        // Neither the key nor provider text ever reaches the client.
        expect(text).not.toContain("test-llm-key");
        expect(text).not.toContain("sk-secret");
      }
      // Without consent no request is sent: only the consented turn calls out.
      expect(seen.map(({ signal, ...rest }) => rest)).toEqual(scenario.upstream_requests);
      expect(logs).not.toHaveBeenCalled();
    });
  }

  test("reasoning_effort defaults to minimal, is omitted when blank, and max_tokens is 2000", () => {
    const good = fixture.providers.llm.find((item) => item.name === "good-extraction")!;
    const blank = fixture.providers.llm.find((item) => item.name === "good-extraction-no-effort")!;
    const payload = good.upstream_requests[0].json as Record<string, unknown>;
    expect(payload.reasoning_effort).toBe("minimal");
    expect(payload.max_tokens).toBe(2000);
    expect(blank.upstream_requests[0].json).not.toHaveProperty("reasoning_effort");
  });

  test("an answered-but-ungrounded extraction is 'used', not an outage (PR #18)", async () => {
    const ungrounded = fixture.providers.llm.find((item) => item.name === "ungrounded-quote")!;
    const consented = JSON.parse(ungrounded.turns[0].response);
    expect(consented.provider_status).toBe("used");
    expect(consented.guide_mode).toBe("guided");
    expect(consented.message).not.toContain("isn't available");
    const good = JSON.parse(fixture.providers.llm.find((item) => item.name === "good-extraction")!.turns[0].response);
    expect(good).toMatchObject({ provider_status: "used", guide_mode: "llm" });
    expect(good.state.pending_profile.weight_kg).toBe(70);
    expect(good.state.confirmed_profile.weight_kg).toBeNull();
    const failed = JSON.parse(fixture.providers.llm.find((item) => item.name === "http-500")!.turns[0].response);
    expect(failed.provider_status).toBe("unavailable");
    expect(failed.message).toContain("The AI helper isn't available right now");
  });

  test("unset LLM_REASONING_EFFORT sends minimal", async () => {
    const { seen } = fakeUpstream(200, fixture.providers.llm[0].upstream_body);
    const env: Record<string, string> = { ...llmEnv("") };
    delete env.LLM_REASONING_EFFORT;
    await json(env, "POST", "/api/onboarding/turn", {
      action: "reply",
      state: { phase: "asking", current_field: "weight_kg" },
      text: "I think I'm 70 kg",
      provider_consent: true,
    });
    expect((seen[0].json as Record<string, unknown>).reasoning_effort).toBe("minimal");
  });

  test("a provider that never answers hits the deadline and falls back", async () => {
    let aborted = false;
    vi.stubGlobal(
      "fetch",
      vi.fn(
        (_url: unknown, init?: RequestInit) =>
          new Promise((_, reject) => {
            init?.signal?.addEventListener("abort", () => {
              aborted = true;
              reject(new Error("aborted"));
            });
          }),
      ),
    );
    const result = await json({ ...llmEnv("minimal"), API_PROVIDER_TIMEOUT_SECONDS: "0.05" }, "POST", "/api/onboarding/turn", {
      action: "reply",
      state: { phase: "asking", current_field: "weight_kg" },
      text: "I think I'm 70 kg",
      provider_consent: true,
    });
    expect(result.status).toBe(200);
    expect(result.body.provider_status).toBe("unavailable");
    expect(result.body.state.pending_profile.weight_kg).toBeNull();
    expect(aborted).toBe(true);
  });

  test("the unported OpenAI Responses provider stays keyless: no network, llm_configured false", async () => {
    const network = forbidNetwork();
    const env = { OPENAI_API_KEY: "sk-test", OPENAI_MODEL: "gpt-test" };
    const caps = await json(env, "GET", "/api/capabilities");
    expect(caps.body.llm_configured).toBe(false);
    const result = await json(env, "POST", "/api/onboarding/turn", {
      action: "reply",
      state: { phase: "asking", current_field: "weight_kg" },
      text: "I think I'm 70 kg",
      provider_consent: true,
    });
    expect(result.body.provider_status).toBe("not_configured");
    expect(network).not.toHaveBeenCalled();
  });
});

describe("Tavily reviewed-page check", () => {
  for (const scenario of fixture.providers.tavily) {
    test(`${scenario.name}: same extract request and same advisor response`, async () => {
      const { seen } = fakeUpstream(scenario.upstream_status, scenario.upstream_body, { location: "https://elsewhere.example/" });
      const { response, text } = await call({ TAVILY_API_KEY: "tvly-test-key" }, "POST", "/api/advisor", {
        body: JSON.stringify(scenario.request),
        contentType: "application/json",
      });
      expect(response.status).toBe(scenario.status);
      expect(mask(text)).toBe(scenario.response);
      expect(seen.map(({ signal, ...rest }) => rest)).toEqual(scenario.upstream_requests);
      // Only fixed reviewed URLs leave the server: no profile or query text.
      expect(JSON.stringify(seen)).not.toContain("profile");
    });
  }

  test("research is opt-in even when a key is configured", async () => {
    const network = forbidNetwork();
    const result = await json({ TAVILY_API_KEY: "tvly-test-key" }, "POST", "/api/advisor", { topics: ["sleep"] });
    expect(result.body.research.status).toBe("not_requested");
    expect(network).not.toHaveBeenCalled();
  });
});

describe("Cartesia voice token", () => {
  const env = { CARTESIA_API_KEY: "sk_car_test", CARTESIA_VOICE_ID: "voice-123", CARTESIA_TTS_SPEED: "1.0" };
  for (const scenario of fixture.providers.voice) {
    test(`${scenario.name}: same token request and same response`, async () => {
      const { seen } = fakeUpstream(scenario.upstream_status, scenario.upstream_body);
      const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
      const { response, text } = await call(env, "POST", "/api/voice/token", {
        body: JSON.stringify({ voice_consent: true }),
        contentType: "application/json",
      });
      expect(response.status).toBe(scenario.status);
      expect(mask(text)).toBe(scenario.response);
      expect(response.headers.get("cache-control")).toBe("no-store");
      expect(seen.map(({ signal, ...rest }) => rest)).toEqual(scenario.upstream_requests);
      expect(mask((await call(env, "GET", "/api/capabilities")).text)).toBe(scenario.capabilities);
      for (const [message] of warn.mock.calls) expect(String(message)).not.toMatch(/sk_car|short-lived-token|bad key/);
    });
  }

  test("unconfigured voice is 503 without a network call; missing consent is 422", async () => {
    const network = forbidNetwork();
    const unconfigured = await json({}, "POST", "/api/voice/token", { voice_consent: true });
    expect(unconfigured.status).toBe(503);
    expect(unconfigured.body.code).toBe("voice_unavailable");
    const consent = await json(env, "POST", "/api/voice/token", { voice_consent: false });
    expect(consent.status).toBe(422);
    expect(consent.body.message).toBe("Please agree to use your voice first.");
    expect(network).not.toHaveBeenCalled();
  });
});

describe("CORS (Starlette CORSMiddleware semantics)", () => {
  for (const item of fixture.cors.cases) {
    test(`${item.method} ${item.path} ${JSON.stringify(item.headers)}`, async () => {
      forbidNetwork();
      const { response, text } = await call({ CORS_ORIGINS: fixture.cors.origins }, item.method, item.path, {
        headers: item.headers as Record<string, string>,
      });
      expect(response.status).toBe(item.status);
      expect(mask(text)).toBe(item.response);
      const selected: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        if (key.startsWith("access-control-") || ["vary", "content-type", "allow"].includes(key)) selected[key] = value;
      });
      expect(selected).toEqual(item.response_headers);
    });
  }
});

describe("configuration", () => {
  test("an invalid setting gives a redacted 500 on business routes while probes stay up", async () => {
    forbidNetwork();
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const env = { CARTESIA_TTS_SPEED: "9", CARTESIA_API_KEY: "sk_car_secret" };
    expect((await json(env, "GET", "/health")).status).toBe(200);
    const result = await json(env, "GET", "/api/capabilities");
    expect(result.status).toBe(500);
    expect(result.body.code).toBe("internal_error");
    expect(String(error.mock.calls[0][0])).toContain("ConfigError(CARTESIA_TTS_SPEED)");
    expect(String(error.mock.calls[0][0])).not.toContain("sk_car_secret");
  });

  test("the overall request deadline answers 504 request_timeout", async () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => undefined)));
    const result = await json({ TAVILY_API_KEY: "tvly-test-key", API_REQUEST_TIMEOUT_SECONDS: "0.05" }, "POST", "/api/advisor", {
      topics: ["sleep"],
      use_web_research: true,
    });
    expect(result.status).toBe(504);
    expect(result.body).toMatchObject({ code: "request_timeout", message: "This is taking too long. Please try again." });
  });

  test("request bodies over the byte budget are 413", async () => {
    forbidNetwork();
    const { response } = await call({ API_MAX_BODY_BYTES: "128" }, "POST", "/api/advisor", {
      body: JSON.stringify({ topics: ["sleep"], pad: "x".repeat(200) }),
      contentType: "application/json",
    });
    expect(response.status).toBe(413);
  });
});

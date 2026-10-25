import { createHandler } from "./handler.ts";
import { validate } from "./validation.ts";
import cases from "../../../contracts/fixtures/cases.json" with {
  type: "json",
};
function assert(
  condition: unknown,
  label = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(label);
}
function request(
  path: string,
  payload?: unknown,
  method?: string,
  headers: Record<string, string> = {},
) {
  return new Request("https://example.test/functions/v1/lifetwin-api" + path, {
    method: method ?? (payload === undefined ? "GET" : "POST"),
    headers: { "content-type": "application/json", ...headers },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
  });
}
Deno.test("Full Edge handler replays all API fixtures: statuses and response contracts", async () => {
  const handler = createHandler(async () => ({}));
  const failures: string[] = [];
  let count = 0;
  for (const fixture of cases as any[]) {
    const response = await handler(
      request(fixture.path, fixture.request, fixture.method),
    );
    const body = await response.json();
    const expected = fixture.path === "/api/predict" && fixture.status === 200
      ? 501
      : fixture.status;
    if (response.status !== expected) {
      failures.push(
        `${fixture.name}: HTTP ${response.status}, expected ${expected}`,
      );
    }
    const schema = response.status >= 400 && response.status !== 501
      ? "error.schema.json"
      : fixture.path === "/api/predict" && response.status === 501
      ? "compare.schema.json"
      : fixture.response_schema;
    if (!validate(schema, body)) {
      failures.push(fixture.name + ": response contract mismatch");
    }
    if (response.headers.get("cache-control") !== "no-store") {
      failures.push(fixture.name + ": missing no-store");
    }
    if (!/^[a-f0-9]{32}$/.test(response.headers.get("x-request-id") ?? "")) {
      failures.push(fixture.name + ": missing request ID");
    }
    count++;
  }
  assert(count >= 90, "all fixtures exercised");
  assert(failures.length === 0, failures.join("\n"));
});
Deno.test("Liveness survives unavailable config; readiness fails closed without secrets", async () => {
  const handler = createHandler(async () => {
    throw new Error("secret-value-must-not-escape");
  });
  const health = await handler(request("/health"));
  assert(health.status === 200);
  const ready = await handler(request("/ready"));
  assert(ready.status === 503);
  const text = await ready.text();
  assert(!text.includes("secret-value"));
  assert(validate("error.schema.json", JSON.parse(text)));
});
Deno.test("Malformed, oversized and nonobject requests are bounded and redacted", async () => {
  const handler = createHandler(async () => ({}));
  for (const body of ["{", "null", "[]", '"secret-input"']) {
    const response = await handler(
      new Request("https://example.test/lifetwin-api/api/onboarding/turn", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body,
      }),
    );
    assert(response.status === 422, "invalid JSON body rejected");
    assert(!(await response.text()).includes("secret-input"));
  }
  const big = await handler(
    request("/api/onboarding/turn", {
      action: "start",
      text: "private-health-" + "x".repeat(32768),
    }),
  );
  assert(big.status === 413);
  assert(!(await big.text()).includes("private-health"));
  const docs = await handler(
    request("/api/documents/extract", { pages: ["x".repeat(393216)] }),
  );
  assert(docs.status === 413);
});
Deno.test("CORS allows only configured exact HTTPS origins and no wildcard", async () => {
  const handler = createHandler(async () => ({
    LIFETWIN_CORS_ORIGINS: "https://app.example.test",
  }));
  const allowed = await handler(
    request("/api/capabilities", undefined, "GET", {
      origin: "https://app.example.test",
    }),
  );
  assert(
    allowed.headers.get("access-control-allow-origin") ===
      "https://app.example.test",
  );
  assert(allowed.headers.get("vary") === "Origin");
  const blocked = await handler(
    request("/api/capabilities", undefined, "GET", {
      origin: "https://evil.example.test",
    }),
  );
  assert(!blocked.headers.has("access-control-allow-origin"));
  const preflight = await handler(
    request("/api/capabilities", undefined, "OPTIONS", {
      origin: "https://app.example.test",
      "access-control-request-method": "POST",
    }),
  );
  assert(preflight.status === 204);
  assert(await preflight.text() === "");
  const wildcard = createHandler(async () => ({ LIFETWIN_CORS_ORIGINS: "*" }));
  assert(
    !(await wildcard(
      request("/api/capabilities", undefined, "GET", {
        origin: "https://anything.test",
      }),
    )).headers.has("access-control-allow-origin"),
  );
});
Deno.test("Health/readiness/capabilities reveal no provider credentials", async () => {
  const secret = "synthetic-private-provider-key";
  const handler = createHandler(async () => ({
    LLM_PROVIDER: "chat_completions",
    LLM_API_KEY: secret,
    LLM_MODEL: "synthetic-model",
    CARTESIA_API_KEY: secret,
    CARTESIA_VOICE_ID: "synthetic-voice",
  }));
  for (const path of ["/health", "/ready", "/api/capabilities"]) {
    const response = await handler(request(path));
    assert(response.status === 200);
    assert(!(await response.text()).includes(secret));
  }
});
Deno.test("Unknown paths and wrong methods are structured and never redirect", async () => {
  const handler = createHandler(async () => ({}));
  assert((await handler(request("/api/missing"))).status === 404);
  assert((await handler(request("/api/onboarding/turn"))).status === 405);
  const response = await handler(
    new Request("https://example.test/another-app/api/onboarding/turn", {
      method: "POST",
      body: "{}",
    }),
  );
  assert(response.status === 404);
  assert(!response.headers.has("location"));
});
Deno.test("Rate budget rejects surplus work but liveness remains available", async () => {
  const handler = createHandler(async () => ({}));
  for (let i = 0; i < 120; i++) {
    assert((await handler(request("/ready"))).status === 200);
  }
  const limited = await handler(request("/api/capabilities"));
  assert(limited.status === 429);
  assert(limited.headers.get("retry-after") === "60");
  assert((await handler(request("/health"))).status === 200);
});
Deno.test("Slow chunked request is cancelled at the body deadline and releases its slot", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode("{"));
    },
    cancel() {
      cancelled = true;
    },
  });
  const handler = createHandler(async () => ({}));
  const started = Date.now();
  const response = await handler(
    new Request(
      "https://example.test/lifetwin-api/api/onboarding/turn",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: stream,
        duplex: "half",
      } as RequestInit,
    ),
  );
  assert(response.status === 504, "body read deadline");
  assert(cancelled, "body stream cancelled");
  assert(Date.now() - started < 7500, "bounded elapsed time");
  const body = await response.json();
  assert(validate("error.schema.json", body));
  assert(body.code === "request_timeout");
  assert(
    (await handler(request("/api/capabilities"))).status === 200,
    "slot released",
  );
});

Deno.test("PDF upload honors its configured byte budget before opening a document", async () => {
  const handler = createHandler(async () => ({
    API_MAX_PDF_BODY_BYTES: "1024",
  }));
  const response = await handler(
    request("/api/documents/read", { pdf_base64: "a".repeat(1500) }),
  );
  assert(response.status === 413);
  assert((await response.json()).code === "body_too_large");
});

Deno.test("Only one PDF upload occupies an isolate and its slot is released", async () => {
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const stream = new ReadableStream<Uint8Array>({
    start(value) {
      controller = value;
      value.enqueue(new TextEncoder().encode('{"pdf_base64":"'));
    },
  });
  const handler = createHandler(async () => ({}));
  const pending = handler(
    new Request(
      "https://example.test/lifetwin-api/api/documents/read",
      { method: "POST", body: stream, duplex: "half" } as RequestInit,
    ),
  );
  const second = await handler(
    request("/api/documents/read", { pdf_base64: "eA==" }),
  );
  assert(second.status === 429);
  controller.enqueue(new TextEncoder().encode('eA=="}'));
  controller.close();
  assert((await pending).status === 200);
  assert(
    (await handler(request("/api/documents/read", { pdf_base64: "eA==" })))
      .status === 200,
  );
});

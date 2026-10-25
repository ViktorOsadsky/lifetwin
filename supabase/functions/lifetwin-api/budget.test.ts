import {
  completeJSON,
  type Config,
  takeBudget,
  voiceToken,
} from "./providers.ts";

function assert(value: unknown, label = "budget assertion"): asserts value {
  if (!value) throw new Error(label);
}
const project: Config = {
  SUPABASE_URL: "https://plpywefoeepfunptjujc.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-secret",
};

Deno.test("Shared budget uses only the fixed project RPC and backend credential", async () => {
  let calls = 0;
  const fake: typeof fetch = async (input, init) => {
    calls++;
    assert(
      String(input) ===
        project.SUPABASE_URL + "/rest/v1/rpc/lifetwin_take_provider_budget",
    );
    assert(init?.redirect === "error" && Boolean(init.signal));
    assert(
      new Headers(init.headers).get("apikey") ===
        project.SUPABASE_SERVICE_ROLE_KEY,
    );
    assert(JSON.parse(String(init.body)).provider_kind === "llm");
    return new Response("true");
  };
  assert(await takeBudget(project, "llm", fake));
  assert(calls === 1);
});

Deno.test("Unavailable, exhausted or incomplete shared budget fails closed", async () => {
  const missing = async () => {
    throw new Error("must not fetch");
  };
  assert(
    !await takeBudget({ SUPABASE_URL: project.SUPABASE_URL }, "voice", missing),
  );
  assert(
    !await takeBudget(
      { ...project, SUPABASE_URL: "https://foreign.example" },
      "voice",
      missing,
    ),
  );
  for (
    const response of [
      new Response("false"),
      new Response("true", { status: 500 }),
      new Response("{}"),
    ]
  ) {
    assert(!await takeBudget(project, "voice", async () => response));
  }
  assert(
    !await takeBudget(project, "llm", async () => {
      throw new Error("unavailable");
    }),
  );
});

Deno.test("Exhausted budget prevents both paid provider request kinds", async () => {
  const config = {
    ...project,
    LLM_API_KEY: "synthetic",
    LLM_MODEL: "muse-spark-1.3",
    PERSONALIZE_PROVIDER: "muse",
    CARTESIA_API_KEY: "synthetic-cartesia",
    CARTESIA_VOICE_ID: "voice-id",
  };
  let calls = 0;
  const exhausted: typeof fetch = async (input) => {
    calls++;
    assert(
      String(input).endsWith("/rpc/lifetwin_take_provider_budget"),
      "provider request must not occur",
    );
    return new Response("false");
  };
  assert(
    await completeJSON(config, "test", "synthetic", {}, exhausted) === null,
  );
  assert(await voiceToken(config, exhausted) === null);
  assert(calls === 2);
});

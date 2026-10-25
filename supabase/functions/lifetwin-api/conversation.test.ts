import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { conversationRoute, isEmergency, parseAnswer } from "./conversation.ts";

function subset(actual: any, expected: any, path = "response") {
  if (expected && typeof expected === "object" && "$each" in expected) {
    assert.ok(Array.isArray(actual), path);
    for (const item of actual) subset(item, expected.$each, path + "[]");
  } else if (Array.isArray(expected)) {
    assert.ok(Array.isArray(actual), path);
    assert.equal(actual.length, expected.length, path);
    expected.forEach((v, i) => subset(actual[i], v, path + `[${i}]`));
  } else if (expected && typeof expected === "object") {
    assert.ok(actual && typeof actual === "object", path);
    for (const [name, value] of Object.entries(expected)) {
      subset(actual[name], value, path + "." + name);
    }
  } else assert.deepEqual(actual, expected, path);
}

const cases = JSON.parse(
  readFileSync(
    new URL("../../../contracts/fixtures/cases.json", import.meta.url),
    "utf8",
  ),
);
for (
  const c of cases.filter((c: any) =>
    /\/api\/(onboarding|checkin|change)\//.test(c.path) &&
    c.request_schema_valid !== false
  )
) {
  test(c.name, async () => {
    const result = await conversationRoute(c.path, c.request);
    assert.equal(result.status, c.status);
    subset(result.body, c.response_subset);
  });
}

test("ambiguous measurements and other people's values never become candidate values", () => {
  assert.equal(parseAnswer("weight_kg", "70"), null);
  assert.equal(parseAnswer("height_cm", "about 70"), null);
  assert.equal(parseAnswer("age", "my wife is 72"), null);
  assert.equal(parseAnswer("sleep_hours", "6 or 7 hours"), null);
  assert.equal(parseAnswer("hypertension_diagnosed", "140 over 90"), null);
  assert.equal(
    parseAnswer("exercise_minutes_weekly", "if I exercised 150 minutes"),
    null,
  );
  assert.equal(parseAnswer("sleep_hours", "minus 7 hours"), null);
});

test("normal answers remain pending until explicit confirmation and hypothetical wording is rejected", async () => {
  const answered = await conversationRoute("/api/onboarding/turn", {
    action: "reply",
    text: "72",
    state: { phase: "asking", current_field: "age" },
  });
  assert.equal(answered.body.state.confirmed_profile.age, null);
  assert.equal(answered.body.state.pending_profile.age, 72);
  const confirmed = await conversationRoute("/api/onboarding/turn", {
    action: "confirm",
    state: answered.body.state,
  });
  assert.equal(confirmed.body.state.confirmed_profile.age, 72);
  const uncertain = await conversationRoute("/api/onboarding/turn", {
    action: "reply",
    text: "yes, actually 75",
    state: answered.body.state,
  });
  assert.equal(uncertain.body.state.confirmed_profile.age, null);
  assert.equal(uncertain.body.state.pending_profile.age, 75);
});

test("authored emergency rules cover passive/slang danger and distinguish history and idioms", () => {
  for (
    const text of [
      "kms",
      "I don't want to wake up anymore",
      "my family would cope fine without me",
      "I've got pills saved up for when it gets bad",
      "I have saved pills to take all at once",
      "I can't breathe",
      "I had chest pain last year but I have chest pain again now",
    ]
  ) assert.equal(isEmergency(text), true, text);
  for (
    const text of [
      "my heart attack was in 2015",
      "I had chest pain years ago",
      "I'm dying to see my grandkids",
      "this meeting is killing me",
      "I don't want to be here at the gym anymore",
      "I saved my pills in a daily organizer so I remember each dose",
    ]
  ) assert.equal(isEmergency(text), false, text);
});

test("semantic state checks reject unrelated pending health updates", async () => {
  const changed = await conversationRoute("/api/change/turn", {
    action: "confirm",
    state: {
      phase: "confirming",
      field: "weight_kg",
      pending: { weight_kg: 70, diabetes: true },
    },
  });
  assert.equal(changed.status, 422);
  const weekly = await conversationRoute("/api/checkin/turn", {
    action: "confirm",
    state: {
      kind: "weekly",
      phase: "confirming",
      questions: [
        "sleep_hours",
        "vigorous_recreation_min_week",
        "moderate_recreation_min_week",
        "sedentary_min_day",
        "alcohol_drinks_weekly",
        "smoking_status",
        "weight_kg",
        "systolic_bp",
        "wellbeing",
      ],
      current_field: "sleep_hours",
      pending: { sleep_hours: 7, diabetes: true },
    },
  });
  assert.equal(weekly.status, 422);
});

test("outside-AI extraction requires consent and cannot fabricate an unquoted value", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  const config = {
    LLM_PROVIDER: "anthropic",
    ANTHROPIC_API_KEY: "synthetic-test-key",
  };
  globalThis.fetch = async () => {
    calls++;
    return Response.json({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify({ quote: "72 kg" }) }],
    });
  };
  try {
    const request = {
      action: "reply",
      text: "I cannot read the scale",
      state: { phase: "asking", current_field: "weight_kg" },
    };
    const noConsent = await conversationRoute(
      "/api/onboarding/turn",
      request,
      config,
    );
    assert.equal(calls, 0);
    assert.equal(noConsent.body.provider_status, "consent_required");
    // The AI helper's yes alone never reaches Claude: a yes for Claude is needed too.
    const helperOnly = await conversationRoute("/api/onboarding/turn", {
      ...request,
      provider_consent: true,
      outside_ai_consent: { muse: true },
    }, config);
    assert.equal(calls, 0);
    assert.equal(helperOnly.body.provider_status, "consent_required");
    const rejected = await conversationRoute("/api/onboarding/turn", {
      ...request,
      provider_consent: true,
      outside_ai_consent: { claude: true },
    }, config);
    assert.equal(calls, 1);
    assert.equal(rejected.body.state.pending_profile.weight_kg, null);
    assert.equal(rejected.body.state.phase, "asking");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

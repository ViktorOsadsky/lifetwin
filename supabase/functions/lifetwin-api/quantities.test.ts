import assert from "node:assert/strict";
import { conversationRoute, parseAnswer } from "./conversation.ts";
import { readQuantity } from "./quantities.ts";

const test = Deno.test;
const SLEEP = "sleep_hours", VIG = "vigorous_recreation_min_week";
const MOD = "moderate_recreation_min_week", SED = "sedentary_min_day";

// The same spoken matrix as server/tests/test_spoken_math.py: null is "asked again".
const MATRIX: [string, Record<string, number | null>][] = [
  ["2 hours", { [SLEEP]: 2, [VIG]: 120, [MOD]: 120, [SED]: 120 }],
  ["two hours", { [SLEEP]: 2, [VIG]: 120, [MOD]: 120, [SED]: 120 }],
  ["an hour and a half", { [VIG]: 90, [MOD]: 90, [SED]: 90 }],
  ["90 mins", { [VIG]: 90, [SED]: 90, [SLEEP]: null }],
  ["1.5 hrs", { [VIG]: 90, [MOD]: 90, [SED]: 90 }],
  ["half an hour", { [VIG]: 30, [SED]: 30, [SLEEP]: null }],
  ["7 and a half hours of sleep", { [SLEEP]: 7.5, [MOD]: null, [SED]: null }],
  ["about 2 hours a week", { [VIG]: 120, [SLEEP]: null, [SED]: null }],
  ["30 minutes three times a week", { [VIG]: 90, [SLEEP]: null, [SED]: null }],
  ["2 hours a day", { [VIG]: 840, [SED]: 120 }],
  ["5 foot 10", { height_cm: 177.8, [SLEEP]: null, [MOD]: null }],
  ["170 lbs", { weight_kg: 77.11, [SLEEP]: null, [MOD]: null }],
];

test("spoken amounts become the field's unit, and wrong ones are asked again", () => {
  for (const [said, expected] of MATRIX) {
    for (const [field, value] of Object.entries(expected)) {
      const got = parseAnswer(field, said)?.[field] ?? null;
      if (value === null) assert.equal(got, null, `${said} -> ${field}`);
      else {
        assert.ok(
          got !== null && Math.abs(got - value) < 0.01,
          `${said} -> ${field}: ${got}`,
        );
      }
    }
  }
  assert.equal(
    readQuantity("an hour on Mondays and an hour on Thursdays", MOD).value,
    120,
  );
});

function claude(reply: Record<string, unknown>) {
  let calls = 0;
  const original = globalThis.fetch;
  globalThis.fetch = (() => {
    calls++;
    return Promise.resolve(Response.json({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify(reply) }],
    }));
  }) as typeof fetch;
  return { calls: () => calls, restore: () => (globalThis.fetch = original) };
}

const config = {
  ANTHROPIC_API_KEY: "synthetic-test-key",
  LLM_PROVIDER: "chat_completions",
};
const ask = (text: string) => ({
  action: "reply",
  text,
  provider_consent: true,
  outside_ai_consent: { claude: true },
  state: { phase: "asking", current_field: MOD },
});

test("background speech keeps the question open; answers are never off topic", async () => {
  const tv = claude({ quote: "", value: null, off_topic: true });
  try {
    const heard = await conversationRoute(
      "/api/onboarding/turn",
      ask("and now back to the studio for the weekend weather"),
      config,
    );
    assert.equal(tv.calls(), 1); // Claude, although LLM_PROVIDER names Muse
    assert.equal(heard.body.off_topic, true);
    assert.equal(heard.body.state.phase, "asking");
    assert.match(heard.body.message, /^Sorry, I think I heard someone else\./);
    const answer = await conversationRoute(
      "/api/onboarding/turn",
      ask("two hours"),
      config,
    );
    assert.equal(tv.calls(), 1); // read by the rules, no model
    assert.equal(answer.body.off_topic, false);
    assert.equal(answer.body.state.pending_profile[MOD], 120);
  } finally {
    tv.restore();
  }
});

test("the reader never picks one of two heights", () => {
  // The rules read the correction; this reader used to return the first (162.6 cm).
  const two = readQuantity(
    "I'm five foot four, well, five three and a half",
    "height_cm",
  );
  assert.equal(two.status, "ambiguous");
  assert.equal(readQuantity("5 foot 10", "height_cm").value, 177.8);
});

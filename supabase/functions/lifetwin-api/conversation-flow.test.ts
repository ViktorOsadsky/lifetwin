import assert from "node:assert/strict";
import { conversationRoute } from "./conversation.ts";
import { validate } from "./validation.ts";

Deno.test("synthetic 69-year-old completes mascot intake with correction, no Health import and ready model inputs", async () => {
  let state: any;
  async function turn(payload: Record<string, unknown>) {
    const request = { ...payload, ...(state ? { state } : {}) };
    assert.equal(
      validate("conversation.request.schema.json", request),
      true,
      "request schema",
    );
    const result = await conversationRoute("/api/onboarding/turn", request);
    assert.equal(result.status, 200);
    assert.equal(
      validate("conversation.schema.json", result.body),
      true,
      "response schema",
    );
    state = result.body.state;
    return result.body;
  }
  await turn({ action: "start" });
  assert.equal(state.phase, "remembering");
  await turn({ action: "reply", text: "No thanks" });
  assert.equal(state.memory_consent, false);
  for (
    const [field, answer, expected] of [
      ["age", "69", 69],
      ["sex", "female", "female"],
      ["smoking_status", "I never smoked", "never"],
    ]
  ) {
    assert.equal(state.current_field, field);
    await turn({ action: "reply", text: answer });
    assert.equal(state.phase, "confirming");
    assert.equal(state.confirmed_profile[field as string], null);
    assert.equal(state.pending_profile[field as string], expected);
    await turn({ action: "confirm" });
    assert.equal(state.confirmed_profile[field as string], expected);
  }
  assert.equal(state.phase, "offering");
  await turn({ action: "skip" });
  assert.equal(state.health_offered, true);
  assert.equal(state.current_field, "height_cm");
  for (
    const [field, answer, expected] of [
      ["height_cm", "165 cm", 165],
      ["weight_kg", "70 kg", 70],
    ]
  ) {
    assert.equal(state.current_field, field);
    await turn({ action: "reply", text: answer });
    assert.equal(state.confirmed_profile[field as string], null);
    await turn({ action: "confirm" });
    assert.equal(state.confirmed_profile[field as string], expected);
  }
  // Correct a previously confirmed value while the next question is open.
  assert.equal(state.current_field, "sleep_hours");
  await turn({
    action: "correct",
    field: "weight_kg",
    text: "Actually, 72 kg",
  });
  assert.equal(state.confirmed_profile.weight_kg, 70);
  assert.equal(state.pending_profile.weight_kg, 72);
  await turn({ action: "confirm" });
  assert.equal(state.confirmed_profile.weight_kg, 72);
  assert.equal(state.current_field, "sleep_hours");
  for (
    const [field, answer, expected] of [
      ["sleep_hours", "7 hours", 7],
      ["general_health", "fair", "fair"],
      ["hypertension_diagnosed", "No", false],
      ["diabetes", "No", false],
      ["sedentary_min_day", "6 hours", 360],
      ["moderate_recreation_min_week", "150 minutes a week", 150],
      ["vigorous_recreation_min_week", "None", 0],
    ]
  ) {
    assert.equal(state.current_field, field);
    await turn({ action: "reply", text: answer });
    assert.equal(state.phase, "confirming");
    assert.equal(state.pending_profile[field as string], expected);
    await turn({ action: "confirm" });
    assert.equal(state.confirmed_profile[field as string], expected);
  }
  const finished = await turn({ action: "resume" });
  assert.equal(finished.complete, true);
  assert.equal(finished.model_inputs.status, "ready");
  assert.deepEqual(finished.model_inputs.missing, []);
  assert.equal(finished.model_inputs.profile.sex_nhanes, 2);
  assert.equal(finished.model_inputs.profile.weight_kg, 72);
  assert.equal(finished.model_inputs.profile.general_health, 4);
  assert.equal(finished.model_inputs.profile.moderate_recreation_min_week, 150);
  assert.deepEqual(state.habit_notes, []);
  // Non-model intake questions remain absent; no guessed optional measurements.
  assert.equal(state.confirmed_profile.exercise_minutes_weekly, null);
  assert.equal(state.confirmed_profile.alcohol_drinks_weekly, null);
  assert.equal(state.confirmed_profile.systolic_bp, null);
});

Deno.test("future exercise goals never become confirmed health values", async () => {
  for (
    const text of [
      "I want to exercise 150 minutes a week",
      "I will walk 150 minutes",
      "If I exercise 150 minutes",
    ]
  ) {
    const result = await conversationRoute("/api/onboarding/turn", {
      action: "reply",
      text,
      state: { phase: "asking", current_field: "moderate_recreation_min_week" },
    });
    assert.equal(result.status, 200);
    assert.equal(result.body.state.phase, "asking", text);
    assert.equal(
      result.body.state.pending_profile.moderate_recreation_min_week,
      null,
      text,
    );
    assert.equal(
      result.body.state.confirmed_profile.moderate_recreation_min_week,
      null,
      text,
    );
  }
});

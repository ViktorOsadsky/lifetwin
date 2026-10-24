// Named intake behaviors ported from server/tests/test_onboarding.py, so the
// intent is readable here as well as covered by the differential fixture.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { clarify, parseReply, parseValue } from "../convex/lib/parsing";
import { forbidNetwork, json } from "./helpers";

const KEYLESS = {};
let network: ReturnType<typeof forbidNetwork>;
beforeEach(() => {
  network = forbidNetwork();
});
afterEach(() => {
  expect(network).not.toHaveBeenCalled();
  vi.unstubAllGlobals();
});

const turn = async (action: string, state?: unknown, extra: Record<string, unknown> = {}) => {
  const result = await json(KEYLESS, "POST", "/api/onboarding/turn", { action, ...(state ? { state } : {}), ...extra });
  expect(result.status).toBe(200);
  return result.body;
};
const asking = (field: string, extra: Record<string, unknown> = {}) => ({ phase: "asking", current_field: field, ...extra });

describe("older-adult answer forms", () => {
  test.each([
    ["5'10", 177.8],
    ["5'10\"", 177.8],
    ["5’10”", 177.8],
    ["5 foot 8", 172.72],
    ["five foot eight", 172.72],
    ["5 feet, 10 inches", 177.8],
    ["6 feet", 182.88],
    ["178 cm", 178],
    ["1.75 m", 175],
    ["70 inches", 177.8],
  ])("height %s", (text, cm) => {
    expect(parseValue("height_cm", text)).toEqual({ height_cm: cm });
  });

  test("120 over 80 fills both blood pressure numbers", () => {
    expect(parseReply("120 over 80", "systolic_bp")).toEqual({ systolic_bp: 120, diastolic_bp: 80 });
    expect(parseReply("my blood pressure is 130/85 mmhg", "systolic_bp")).toEqual({ systolic_bp: 130, diastolic_bp: 85 });
  });

  test("reversed blood pressure asks to check the reading", () => {
    expect(parseReply("80 over 120", "systolic_bp")).toEqual({});
    expect(clarify("80 over 120", "systolic_bp")).toContain("The top number is usually the bigger one");
  });

  test("curly apostrophes parse and skip like straight ones", async () => {
    expect(parseValue("age", "I’m 72")).toEqual({ age: 72 });
    const result = await turn("reply", asking("age"), { text: "I don’t know" });
    expect(result.state.skipped_fields).toEqual(["age"]);
  });

  test("spoken numbers, fillers, habits and hedges (PR #18)", () => {
    expect(parseValue("age", "seventy two")).toEqual({ age: 72 });
    expect(parseValue("age", "um I'm 72")).toEqual({ age: 72 });
    expect(parseValue("sleep_hours", "I usually sleep 7 hours")).toEqual({ sleep_hours: 7 });
    expect(parseValue("sleep_hours", "I get about 7 hours i think")).toEqual({ sleep_hours: 7 });
    expect(parseValue("weight_kg", "a hundred and seventy pounds")).toEqual({ weight_kg: 77.1107 });
    expect(parseValue("exercise_minutes_weekly", "two hours of walking a week")).toEqual({ exercise_minutes_weekly: 120 });
    expect(parseValue("exercise_minutes_weekly", "half an hour a day 5 days a week")).toEqual({ exercise_minutes_weekly: 150 });
  });

  test("habit verbs only strip for their own field: 'I weigh 70' never answers age", () => {
    expect(parseValue("age", "I weigh 70")).toEqual({});
    expect(parseValue("weight_kg", "I weigh 70 kg")).toEqual({ weight_kg: 70 });
  });

  test("past, hypothetical and uncertain answers are not stripped into values", () => {
    expect(parseReply("I weighed 200 pounds ten years ago", "weight_kg")).toEqual({});
    expect(parseReply("maybe a glass of wine", "alcohol_drinks_weekly")).toEqual({});
    expect(parseReply("if I weighed 70 kg", "weight_kg")).toEqual({});
  });

  test("quitting smoking is a former smoker", () => {
    for (const text of ["I quit smoking back in 1990", "I stopped smoking years ago", "I gave up", "I used to smoke"]) {
      expect(parseValue("smoking_status", text)).toEqual({ smoking_status: "former" });
    }
  });

  test("a bare number only fills the asked field, and unitless numbers get a units follow-up", async () => {
    expect(parseReply("160", "weight_kg")).toEqual({});
    expect(parseReply("72", "age")).toEqual({ age: 72 });
    const weight = await turn("reply", asking("weight_kg"), { text: "160" });
    expect(weight.state.pending_profile.weight_kg).toBeNull();
    expect(weight.message).toBe('Is that 160 pounds or 160 kilograms? Please say the number with the unit, like "160 pounds".');
    const about = await turn("reply", asking("height_cm"), { text: "about 170" });
    expect(about.state.phase).toBe("asking");
    expect(about.message).toContain("inches or centimeters");
  });
});

describe("confirmation state machine", () => {
  test("start, reply, yes confirms, and values move from pending to confirmed", async () => {
    const start = await turn("start");
    expect(start.state.current_field).toBe("age");
    const reply = await turn("reply", start.state, { text: "35 years old" });
    expect(reply.state.phase).toBe("confirming");
    expect(reply.state.pending_profile.age).toBe(35);
    expect(reply.state.confirmed_profile.age).toBeNull();
    const yes = await turn("reply", reply.state, { text: "Yes." });
    expect(yes.message.startsWith("Confirmed!")).toBe(true);
    expect(yes.state.confirmed_profile.age).toBe(35);
    expect(yes.state.current_field).toBe("sex");
  });

  test("'no, ...' corrects the pending value and vague replies change nothing", async () => {
    const pending = (await turn("reply", asking("height_cm"), { text: "5 feet 10 inches" })).state;
    const corrected = await turn("reply", pending, { text: "No, it's 6 ft" });
    expect(corrected.state.pending_profile.height_cm).toBe(182.88);
    const vague = await turn("reply", pending, { text: "maybe" });
    expect(vague.message).toContain("Nothing has changed.");
    expect(vague.state).toEqual(pending);
  });

  test("invalid transitions are 409 with the shared error envelope", async () => {
    const result = await json(KEYLESS, "POST", "/api/onboarding/turn", { action: "confirm" });
    expect(result.status).toBe(409);
    expect(result.body).toMatchObject({ status: "error", code: "invalid_conversation_transition" });
    expect(result.body.request_id).toBe(result.headers.get("x-request-id"));
  });

  test("Apple Health import confirms values and moves the conversation on (PR #20)", async () => {
    const result = await turn("import", asking("weight_kg", { skipped_fields: ["sleep_hours"] }), {
      values: { weight_kg: 68, sleep_hours: 7.5 },
    });
    expect(result.state.confirmed_profile).toMatchObject({ weight_kg: 68, sleep_hours: 7.5 });
    expect(result.state.skipped_fields).toEqual([]);
    expect(result.message).toContain("2 answers you checked from your Health app");
    const empty = await json(KEYLESS, "POST", "/api/onboarding/turn", { action: "import", state: asking("age"), values: {} });
    expect(empty.status).toBe(422);
  });

  test("an import that lacks the asked value stays on that question and says why (PR #22)", async () => {
    const result = await turn("import", asking("weight_kg"), { values: { sleep_hours: 7 } });
    expect(result.state).toMatchObject({ phase: "asking", current_field: "weight_kg" });
    expect(result.message).toContain("Your Health app didn't have your weight, so I still need it.");
  });

  test("float fields keep FastAPI's float formatting on the wire", async () => {
    const { text } = await json(KEYLESS, "POST", "/api/onboarding/turn", {
      action: "reply",
      state: asking("height_cm"),
      text: "178 cm",
    });
    expect(text).toContain('"height_cm":178.0');
  });

  test("errors never echo submitted health values", async () => {
    const result = await json(KEYLESS, "POST", "/api/predict", { age: 121, weight_kg: 654.321 });
    expect(result.status).toBe(422);
    expect(result.text).not.toContain("121");
    expect(result.text).not.toContain("654");
    expect(result.body.message).toBe("Please check these answers: age. Then try again.");
  });
});

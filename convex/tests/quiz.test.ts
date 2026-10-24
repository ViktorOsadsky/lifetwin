// Quiz bank delivery, ported from server/tests/test_quiz.py.

import { afterEach, beforeEach, expect, test, vi } from "vitest";
import convexBank from "../convex/content/questions.json?raw";
import { QUIZ_BANK } from "../convex/lib/quiz";
import serverBank from "../../server/lifetwin/quiz/content/questions.json?raw";
import { forbidNetwork, json } from "./helpers";

beforeEach(() => {
  forbidNetwork();
});
afterEach(() => {
  vi.unstubAllGlobals();
});

test("the Convex bank is a byte-for-byte copy of the server bank", () => {
  expect(convexBank).toBe(serverBank);
});

test("the reviewed bank is coherent: sources, answers and a complete recovery route", () => {
  expect(QUIZ_BANK.total).toBe(QUIZ_BANK.questions.length);
  const ids = QUIZ_BANK.questions.map((question) => question.id);
  expect(new Set(ids).size).toBe(ids.length);
  for (const question of QUIZ_BANK.questions) {
    expect(question.review_status).toBe("reviewed");
    expect(question.options.map((option) => option.id)).toContain(question.correct_option_id);
    expect(question.sources.length).toBeGreaterThan(0);
    for (const source of question.sources) expect(source.url).toMatch(/^https:\/\/www\.(cdc|fda)\.gov\//);
    expect(question.wrong_effect.game_health_delta).toBeLessThan(0);
    expect(question.correct_effect.game_health_delta).toBeGreaterThan(0);
    expect(question.review_effect.game_health_delta).toBeGreaterThanOrEqual(-question.wrong_effect.game_health_delta);
  }
});

test("delivery includes local scoring metadata that never touches health inputs", async () => {
  const result = await json({}, "GET", "/api/quiz/questions");
  expect(result.status).toBe(200);
  expect(result.body.total).toBe(8);
  expect(result.body.local_scoring).toMatchObject({
    state_scope: "game_health_only",
    affects_confirmed_profile: false,
    affects_prediction: false,
  });
});

test("filters, limits, detail lookup and errors", async () => {
  const limited = await json({}, "GET", "/api/quiz/questions?limit=2");
  expect(limited.body.questions).toHaveLength(2);
  expect(limited.body.total).toBe(8);
  expect((await json({}, "GET", "/api/quiz/questions?limit=0")).status).toBe(422);
  expect((await json({}, "GET", "/api/quiz/questions?topic=astrology")).status).toBe(422);
  const detail = await json({}, "GET", "/api/quiz/questions/soup-serving-check.v2");
  expect(detail.body.id).toBe("soup-serving-check.v2");
  const missing = await json({}, "GET", "/api/quiz/questions/missing-question.v1");
  expect(missing.status).toBe(404);
  expect(missing.body.code).toBe("quiz_question_not_found");
  expect((await json({}, "GET", "/api/quiz/questions/BAD")).status).toBe(422);
});

test("a response cannot mutate future deliveries", async () => {
  const first = await json({}, "GET", "/api/quiz/questions");
  first.body.questions[0].correct_option_id = "z";
  const second = await json({}, "GET", "/api/quiz/questions");
  expect(second.body.questions[0].correct_option_id).not.toBe("z");
});

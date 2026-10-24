// Port of server/lifetwin/quiz/: reviewed bank delivery only. Flutter owns
// immediate deterministic local scoring; nothing here touches health inputs.
// content/questions.json is a byte-for-byte copy of the server's bank (a test
// fails if they drift).

import bank from "../content/questions.json";
import { type Issue } from "./models";
import { pyLen, pyStrip } from "./py";

export const QUIZ_TOPICS = ["nutrition", "food_safety", "activity"] as const;
export const QUIZ_DIFFICULTIES = ["moderate", "challenging"] as const;
const QUESTION_ID = /^[a-z][a-z0-9-]{2,60}\.v[1-9][0-9]{0,2}$/;

export const LOCAL_SCORING = {
  state_scope: "game_health_only",
  minimum_game_health: 0,
  maximum_game_health: 100,
  initial_game_health: 100,
  clamp_after_each_effect: true,
  score_once_per_question_version: true,
  review_once_after_wrong_answer: true,
  retry_after_review_is_unscored: true,
  network_failure_is_unscored: true,
  affects_confirmed_profile: false,
  affects_prediction: false,
  answer_metadata: "included_for_local_offline_scoring",
  label: "Game health",
} as const;

type Question = (typeof bank.questions)[number];

function copy<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

/** Pydantic lax int from a query string: "+5", " 5", "05", "1_0", "5.0". */
function laxInt(raw: string): number | null {
  const value = pyStrip(raw);
  const match = /^([+-]?)(\d+(?:_\d+)*)(?:\.0*)?$/.exec(value);
  if (!match) return null;
  const number = Number(match[2].replace(/_/g, ""));
  return match[1] === "-" ? -number : number;
}

/** Starlette keeps the last value of a repeated query parameter. */
function lastParam(params: URLSearchParams, name: string): string | null {
  const values = params.getAll(name);
  return values.length > 0 ? values[values.length - 1] : null;
}

export function listQuestions(params: URLSearchParams, issues: Issue[]) {
  const topic = lastParam(params, "topic");
  const difficulty = lastParam(params, "difficulty");
  const limitText = lastParam(params, "limit");
  if (topic !== null && !(QUIZ_TOPICS as readonly string[]).includes(topic)) issues.push({ loc: ["query", "topic"], msg: "literal_error" });
  if (difficulty !== null && !(QUIZ_DIFFICULTIES as readonly string[]).includes(difficulty)) {
    issues.push({ loc: ["query", "difficulty"], msg: "literal_error" });
  }
  let limit = 20;
  if (limitText !== null) {
    const parsed = laxInt(limitText);
    if (parsed === null || parsed < 1 || parsed > 100) issues.push({ loc: ["query", "limit"], msg: "int" });
    else limit = parsed;
  }
  if (issues.length > 0) return null;
  const matches = bank.questions.filter(
    (question: Question) => (topic === null || question.topic === topic) && (difficulty === null || question.difficulty === difficulty),
  );
  return {
    schema_version: "1.0",
    bank_version: bank.bank_version,
    local_scoring: { ...LOCAL_SCORING },
    total: matches.length,
    questions: copy(matches.slice(0, limit)),
  };
}

export function questionDetail(questionId: string, issues: Issue[]): Question | null | undefined {
  if (pyLen(questionId) < 6 || pyLen(questionId) > 66 || !QUESTION_ID.test(questionId)) {
    issues.push({ loc: ["path", "question_id"], msg: "string_pattern_mismatch" });
    return undefined;
  }
  const question = bank.questions.find((item: Question) => item.id === questionId);
  return question ? copy(question) : null;
}

export const QUIZ_BANK = bank;

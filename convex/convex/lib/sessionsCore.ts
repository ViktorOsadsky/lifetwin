// Opt-in ephemeral session store (SESSION_STORE=ephemeral). Off by default, so
// a default deployment keeps FastAPI's "no server-side health storage" rule.
// When on, a row holds one caller's conversation state and quiz progress for
// at most SESSION_TTL_MS from creation (absolute, never extended), then a
// scheduled function deletes it; a cron sweep and read-time expiry checks
// back that up, and the caller can delete it at any time.

import type { Issue, Loc } from "./models";

export const SESSION_TTL_MS = 30 * 60 * 1000;

export interface SessionRow {
  sessionId: string;
  conversation: string | null;
  quiz: string | null;
  expiresAt: number;
}

export interface SessionStore {
  create(sessionId: string, expiresAt: number): Promise<SessionRow>;
  get(sessionId: string): Promise<SessionRow | null>;
  save(sessionId: string, patch: { conversation?: string; quiz?: string }): Promise<SessionRow | null>;
  remove(sessionId: string): Promise<void>;
}

export function sessionView(row: SessionRow) {
  return {
    schema_version: "1.0",
    status: "active",
    session_id: row.sessionId,
    expires_at: new Date(row.expiresAt).toISOString(),
    conversation_state: row.conversation === null ? null : JSON.parse(row.conversation),
    quiz_progress: row.quiz === null ? null : JSON.parse(row.quiz),
  };
}

const QUESTION_ID = /^[a-z][a-z0-9-]{2,60}\.v[1-9][0-9]{0,2}$/;

/** Game state only: never a health value, never an input to prediction. */
export function validateQuizProgress(value: unknown, loc: Loc, issues: Issue[]) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    issues.push({ loc, msg: "model_type" });
    return null;
  }
  const input = value as Record<string, unknown>;
  const before = issues.length;
  for (const key of Object.keys(input)) {
    if (key !== "game_health" && key !== "scored_question_ids") issues.push({ loc: [...loc, key], msg: "extra_forbidden" });
  }
  const health = input.game_health;
  if (typeof health !== "number" || !Number.isInteger(health) || health < 0 || health > 100) {
    issues.push({ loc: [...loc, "game_health"], msg: "int" });
  }
  const ids = input.scored_question_ids ?? [];
  if (
    !Array.isArray(ids) ||
    ids.length > 100 ||
    new Set(ids).size !== ids.length ||
    ids.some((id) => typeof id !== "string" || !QUESTION_ID.test(id))
  ) {
    issues.push({ loc: [...loc, "scored_question_ids"], msg: "list" });
  }
  if (issues.length > before) return null;
  return { game_health: health as number, scored_question_ids: ids as string[] };
}

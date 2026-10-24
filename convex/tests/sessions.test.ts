// Opt-in ephemeral session store: off by default (FastAPI parity), and when
// on, every row disappears at its 30-minute absolute TTL or on request.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { SESSION_TTL_MS } from "../convex/lib/sessionsCore";
import schema from "../convex/schema";
import { PROVIDER_ENV_PREFIXES, forbidNetwork, modules } from "./helpers";

const saved: Record<string, string | undefined> = {};
beforeEach(() => {
  for (const key of Object.keys(process.env)) {
    if (PROVIDER_ENV_PREFIXES.some((prefix) => key.startsWith(prefix))) {
      saved[key] = process.env[key];
      delete process.env[key];
    }
  }
  forbidNetwork();
});
afterEach(() => {
  delete process.env.SESSION_STORE;
  Object.assign(process.env, saved);
  vi.unstubAllGlobals();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

const post = async (t: ReturnType<typeof convexTest>, path: string, body: unknown) => {
  const response = await t.fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
};
const rows = (t: ReturnType<typeof convexTest>) => t.run((ctx) => ctx.db.query("sessions").collect());

async function confirmingState(t: ReturnType<typeof convexTest>) {
  const result = await post(t, "/api/onboarding/turn", {
    action: "reply",
    state: { phase: "asking", current_field: "weight_kg" },
    text: "160 pounds",
  });
  return result.body.state;
}

describe("default deployment", () => {
  test("the session route does not exist and nothing is stored", async () => {
    const t = convexTest(schema, modules);
    const result = await post(t, "/api/sessions", { action: "create" });
    expect(result.status).toBe(404);
    expect(result.body.code).toBe("not_found");
    const caps = await (await t.fetch("/api/capabilities")).json();
    expect(caps.health_data_storage).toBe("none");
    // A whole keyless conversation writes no rows.
    await confirmingState(t);
    expect(await rows(t)).toEqual([]);
  });
});

describe("SESSION_STORE=ephemeral", () => {
  beforeEach(() => {
    process.env.SESSION_STORE = "ephemeral";
  });

  test("create, save, read (HTTP and reactive query) and delete", async () => {
    const t = convexTest(schema, modules);
    const caps = await (await t.fetch("/api/capabilities")).json();
    expect(caps.health_data_storage).toBe("ephemeral_sessions_30_minutes");
    const created = await post(t, "/api/sessions", { action: "create" });
    expect(created.status).toBe(200);
    const id = created.body.session_id;
    expect(id).toMatch(/^[0-9a-f]{32}$/);
    expect(created.body).toMatchObject({ status: "active", conversation_state: null, quiz_progress: null });

    const state = await confirmingState(t);
    const quiz = { game_health: 85, scored_question_ids: ["soup-serving-check.v2"] };
    const saved = await post(t, "/api/sessions", { action: "save", session_id: id, conversation_state: state, quiz_progress: quiz });
    expect(saved.status).toBe(200);
    expect(saved.body.conversation_state).toEqual(state);

    const read = await post(t, "/api/sessions", { action: "get", session_id: id });
    expect(read.body).toEqual(saved.body);
    // Other Convex clients can subscribe to the same row reactively.
    expect(await t.query(api.sessions.get, { sessionId: id })).toEqual(saved.body);

    const deleted = await post(t, "/api/sessions", { action: "delete", session_id: id });
    expect(deleted.body).toEqual({ schema_version: "1.0", status: "deleted" });
    expect(await rows(t)).toEqual([]);
    expect((await post(t, "/api/sessions", { action: "get", session_id: id })).status).toBe(404);
    expect(await t.query(api.sessions.get, { sessionId: id })).toBeNull();
  });

  test("the scheduled deletion removes the row at the 30-minute TTL", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema, modules);
    const id = (await post(t, "/api/sessions", { action: "create" })).body.session_id;
    await post(t, "/api/sessions", { action: "save", session_id: id, conversation_state: await confirmingState(t) });
    expect(await rows(t)).toHaveLength(1);
    vi.advanceTimersByTime(SESSION_TTL_MS - 1000);
    await t.finishInProgressScheduledFunctions();
    expect(await rows(t)).toHaveLength(1);
    vi.advanceTimersByTime(1000);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await rows(t)).toEqual([]);
  });

  test("expired rows are unreadable even before deletion runs, and saving does not extend the TTL", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema, modules);
    const created = (await post(t, "/api/sessions", { action: "create" })).body;
    vi.advanceTimersByTime(SESSION_TTL_MS / 2);
    const saved = await post(t, "/api/sessions", { action: "save", session_id: created.session_id, quiz_progress: { game_health: 90 } });
    expect(saved.body.expires_at).toBe(created.expires_at);
    vi.setSystemTime(Date.now() + SESSION_TTL_MS);
    expect((await post(t, "/api/sessions", { action: "get", session_id: created.session_id })).status).toBe(404);
    expect(await t.query(api.sessions.get, { sessionId: created.session_id })).toBeNull();
  });

  test("the cron sweep deletes anything past its expiry", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("sessions", { sessionId: "a".repeat(32), conversation: "{}", quiz: null, expiresAt: Date.now() - 1 });
      await ctx.db.insert("sessions", { sessionId: "b".repeat(32), conversation: null, quiz: null, expiresAt: Date.now() + 60_000 });
    });
    expect(await t.mutation(internal.sessions.sweep, {})).toBe(1);
    expect((await rows(t)).map((row) => row.sessionId)).toEqual(["b".repeat(32)]);
  });

  test("inputs are validated like the intake contract and never logged", async () => {
    const t = convexTest(schema, modules);
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((name) => vi.spyOn(console, name));
    const id = (await post(t, "/api/sessions", { action: "create" })).body.session_id;
    const bad = [
      { action: "get", session_id: "not-an-id" },
      { action: "save", session_id: id },
      { action: "save", session_id: id, conversation_state: { phase: "confirming" } },
      { action: "save", session_id: id, quiz_progress: { game_health: 85, weight_kg: 70 } },
      { action: "save", session_id: id, quiz_progress: { game_health: 101 } },
      { action: "create", conversation_state: {} },
      { action: "get", session_id: id, quiz_progress: { game_health: 1 } },
      { action: "dance" },
    ];
    for (const body of bad) {
      const result = await post(t, "/api/sessions", body);
      expect(result.status, JSON.stringify(body)).toBe(422);
      expect(result.body.code).toBe("invalid_request");
    }
    await post(t, "/api/sessions", { action: "save", session_id: id, conversation_state: await confirmingState(t) });
    expect((await post(t, "/api/sessions", { action: "get", session_id: "f".repeat(32) })).status).toBe(404);
    for (const spy of spies) {
      for (const args of spy.mock.calls) expect(JSON.stringify(args)).not.toMatch(/72\.5748|weight|160/);
    }
  });
});

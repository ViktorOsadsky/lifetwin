// Ephemeral session rows (opt-in, SESSION_STORE=ephemeral). The HTTP action in
// lib/api.ts is the only writer; values are never logged.

import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { type MutationCtx, type QueryCtx, internalMutation, internalQuery, query } from "./_generated/server";
import { sessionView } from "./lib/sessionsCore";

const SWEEP_BATCH = 256;

async function live(ctx: QueryCtx | MutationCtx, sessionId: string): Promise<Doc<"sessions"> | null> {
  const row = await ctx.db
    .query("sessions")
    .withIndex("by_session_id", (q) => q.eq("sessionId", sessionId))
    .unique();
  // Expired rows are treated as gone even before the deletion job runs.
  return row && row.expiresAt > Date.now() ? row : null;
}

const plain = (row: Doc<"sessions">) => ({
  sessionId: row.sessionId,
  conversation: row.conversation,
  quiz: row.quiz,
  expiresAt: row.expiresAt,
});

export const create = internalMutation({
  args: { sessionId: v.string(), expiresAt: v.number() },
  handler: async (ctx, { sessionId, expiresAt }) => {
    const id = await ctx.db.insert("sessions", { sessionId, conversation: null, quiz: null, expiresAt });
    // Absolute TTL: the deletion is scheduled once, at creation.
    await ctx.scheduler.runAt(expiresAt, internal.sessions.expire, { id });
    return { sessionId, conversation: null, quiz: null, expiresAt };
  },
});

export const read = internalQuery({
  args: { sessionId: v.string() },
  handler: async (ctx, { sessionId }) => {
    const row = await live(ctx, sessionId);
    return row ? plain(row) : null;
  },
});

export const save = internalMutation({
  args: { sessionId: v.string(), conversation: v.optional(v.string()), quiz: v.optional(v.string()) },
  handler: async (ctx, { sessionId, conversation, quiz }) => {
    const row = await live(ctx, sessionId);
    if (!row) return null;
    const patch: Partial<Doc<"sessions">> = {};
    if (conversation !== undefined) patch.conversation = conversation;
    if (quiz !== undefined) patch.quiz = quiz;
    await ctx.db.patch(row._id, patch);
    return plain({ ...row, ...patch });
  },
});

export const remove = internalMutation({
  args: { sessionId: v.string() },
  handler: async (ctx, { sessionId }) => {
    const row = await ctx.db
      .query("sessions")
      .withIndex("by_session_id", (q) => q.eq("sessionId", sessionId))
      .unique();
    if (row) await ctx.db.delete(row._id);
  },
});

export const expire = internalMutation({
  args: { id: v.id("sessions") },
  handler: async (ctx, { id }) => {
    if (await ctx.db.get(id)) await ctx.db.delete(id);
  },
});

/** Backstop for missed scheduled deletions; runs from crons.ts. */
export const sweep = internalMutation({
  args: {},
  handler: async (ctx) => {
    const expired = await ctx.db
      .query("sessions")
      .withIndex("by_expires_at", (q) => q.lte("expiresAt", Date.now()))
      .take(SWEEP_BATCH);
    for (const row of expired) await ctx.db.delete(row._id);
    if (expired.length === SWEEP_BATCH) await ctx.scheduler.runAfter(0, internal.sessions.sweep, {});
    return expired.length;
  },
});

/**
 * Reactive read for Convex clients (`useQuery(api.sessions.get, {sessionId})`).
 * The 128-bit random session ID is the only credential; it is never placed in
 * a URL, so it does not appear in HTTP access logs.
 */
export const get = query({
  args: { sessionId: v.string() },
  handler: async (ctx, { sessionId }) => {
    if (!/^[0-9a-f]{32}$/.test(sessionId)) return null;
    const row = await live(ctx, sessionId);
    return row ? sessionView(plain(row)) : null;
  },
});

// Every route of the FastAPI contract, served as Convex HTTP actions on the
// deployment's .site URL (local: http://127.0.0.1:3211). Routing, status codes
// and error envelopes live in lib/api.ts so they match FastAPI exactly,
// including 404/405 for unknown paths and methods.

import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { type ActionCtx, httpAction } from "./_generated/server";
import { dispatch } from "./lib/api";
import type { SessionStore } from "./lib/sessionsCore";

function sessionStore(ctx: ActionCtx): SessionStore {
  return {
    create: (sessionId, expiresAt) => ctx.runMutation(internal.sessions.create, { sessionId, expiresAt }),
    get: (sessionId) => ctx.runQuery(internal.sessions.read, { sessionId }),
    save: (sessionId, patch) => ctx.runMutation(internal.sessions.save, { sessionId, ...patch }),
    remove: async (sessionId) => {
      await ctx.runMutation(internal.sessions.remove, { sessionId });
    },
  };
}

const handler = httpAction(async (ctx, request) => dispatch(request, { env: process.env, sessions: sessionStore(ctx) }));

const http = httpRouter();
for (const method of ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"] as const) {
  http.route({ pathPrefix: "/", method, handler });
}
export default http;

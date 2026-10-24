// HTTP dispatcher with FastAPI's public contract: same paths, methods, status
// codes, JSON bodies, ApiError envelope, request IDs and protective headers.
// It is a plain function of (Request, deps) so tests can drive it directly;
// convex/http.ts mounts it for every method under "/".

import { OPENAPI_JSON } from "../content/openapi";
import { buildPlan } from "./advisor";
import { ConfigError, type Env, type Settings, loadSettings, voiceConfigured } from "./config";
import { ApiHttpError, ConversationService } from "./conversation";
import { BodyDecodeError, JsonDecodeError, JsonDepthError, decodeBody, pyJsonLoads } from "./jsonload";
import {
  type Issue,
  ValidationFailed,
  invalidInputMessage,
  validateAdvisor,
  validateCompare,
  validatePredict,
  validateSensitivity,
  validateState,
  validateTurn,
  validateVoiceToken,
} from "./models";
import { ChatCompletionsExtractor } from "./providers";
import { pyJson } from "./py";
import { listQuestions, questionDetail } from "./quiz";
import { SESSION_TTL_MS, type SessionStore, sessionView, validateQuizProgress } from "./sessionsCore";
import { UNAVAILABLE_MESSAGE, VoiceUnavailable, mintToken } from "./voice";

export interface Deps {
  env: Env;
  /** Present only inside Convex; required when SESSION_STORE=ephemeral. */
  sessions?: SessionStore;
}

const DEFERRED = {
  schema_version: "1.0",
  status: "not_implemented",
  code: "prediction_not_implemented",
  message: "Prediction functionality is reserved for a later implementation.",
  prediction: null,
  model_version: null,
};

type Handler = (context: RouteContext) => Promise<Reply>;
interface Reply {
  status: number;
  body?: unknown;
  /** Pre-rendered JSON text, sent verbatim. */
  raw?: string;
  headers?: Record<string, string>;
}
interface RouteContext {
  request: Request;
  url: URL;
  params: string[];
  bytes: Uint8Array;
  settings: () => Settings;
  deps: Deps;
  requestId: string;
}

class BadRequest extends Error {}

function requestId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function apiError(code: string, message: string, id: string | null) {
  return { schema_version: "1.0", status: "error", code, message, request_id: id };
}

/** FastAPI's body handling: JSON only for application/json or application/*+json. */
function jsonBody(context: RouteContext): unknown {
  if (context.bytes.length === 0) throw new ValidationFailed([{ loc: ["body"], msg: "missing" }]);
  const contentType = context.request.headers.get("content-type");
  if (contentType !== null) {
    const essence = contentType.split(";")[0].trim().toLowerCase();
    const [main, subtype = ""] = essence.includes("/") ? essence.split("/", 2) : ["text", "plain"];
    if (main !== "application" || !(subtype === "json" || subtype.endsWith("+json"))) {
      throw new ValidationFailed([{ loc: ["body"], msg: "model_attributes_type" }]);
    }
  }
  let text: string;
  try {
    text = decodeBody(context.bytes);
  } catch (error) {
    if (error instanceof BodyDecodeError) throw new BadRequest();
    throw error;
  }
  try {
    return pyJsonLoads(text);
  } catch (error) {
    if (error instanceof JsonDecodeError) throw new ValidationFailed([{ loc: ["body", 0], msg: "json_invalid" }]);
    // CPython raises RecursionError, which FastAPI reports as a 400.
    if (error instanceof JsonDepthError) throw new BadRequest();
    throw error;
  }
}

function validated<T>(context: RouteContext, check: (value: unknown, issues: Issue[]) => T): T {
  const issues: Issue[] = [];
  const result = check(jsonBody(context), issues);
  if (issues.length > 0) throw new ValidationFailed(issues);
  return result;
}

function service(settings: Settings): ConversationService {
  const extractor =
    settings.llmProvider === "chat_completions"
      ? new ChatCompletionsExtractor({
          baseUrl: settings.llmEndpoint,
          apiKey: settings.llmApiKey,
          model: settings.llmModel,
          reasoningEffort: settings.llmReasoningEffort,
        })
      : null;
  return new ConversationService(extractor, settings.providerTimeoutSeconds);
}

const health: Handler = async () => ({ status: 200, body: { status: "ok", service: "lifetwin-backend" } });
const ready: Handler = async () => ({
  status: 200,
  body: { status: "ready", prediction: "not_implemented", voice: "deferred" },
});

const capabilities: Handler = async ({ settings }) => {
  const s = settings();
  return {
    status: 200,
    body: {
      schema_version: "1.0",
      intake: "guided",
      llm_configured: s.llmConfigured,
      web_research_configured: Boolean(s.tavilyApiKey.trim()),
      advisor: "curated_educational",
      quiz: "local_scoring_content",
      prediction: "not_implemented",
      voice: voiceConfigured(s) ? "available" : "unavailable",
      // Unchanged unless the opt-in ephemeral session store is enabled.
      health_data_storage: s.sessionsEnabled ? "ephemeral_sessions_30_minutes" : "none",
    },
  };
};

const deferred =
  (check: (value: unknown, issues: Issue[]) => unknown): Handler =>
  async (context) => {
    // Only route shells and input boundaries: no model, math or mock results.
    validated(context, check);
    return { status: 501, body: DEFERRED };
  };

const turn: Handler = async (context) => {
  const request = validated(context, validateTurn)!;
  return { status: 200, body: await service(context.settings()).turn(request) };
};

const advisor: Handler = async (context) => {
  const request = validated(context, validateAdvisor)!;
  const s = context.settings();
  return {
    status: 200,
    body: await buildPlan(request, { apiKey: s.tavilyApiKey, totalTimeoutSeconds: 12 }),
  };
};

const quizList: Handler = async ({ url }) => {
  const issues: Issue[] = [];
  const result = listQuestions(url.searchParams, issues);
  if (issues.length > 0) throw new ValidationFailed(issues);
  return { status: 200, body: result };
};

const quizDetail: Handler = async ({ params }) => {
  const issues: Issue[] = [];
  const question = questionDetail(params[0], issues);
  if (issues.length > 0) throw new ValidationFailed(issues);
  if (!question) throw new ApiHttpError(404, "quiz_question_not_found", "Quiz question not found.");
  return { status: 200, body: question };
};

const voiceToken: Handler = async (context) => {
  validated(context, validateVoiceToken);
  try {
    return { status: 200, body: await mintToken(context.settings()) };
  } catch (error) {
    if (error instanceof VoiceUnavailable) throw new ApiHttpError(503, "voice_unavailable", UNAVAILABLE_MESSAGE);
    throw error;
  }
};

const SESSION_ID = /^[0-9a-f]{32}$/;
const SESSION_GONE = "This session has ended. Please start again.";

/** Opt-in ephemeral session store (SESSION_STORE=ephemeral); see convex/README.md. */
const sessions: Handler = async (context) => {
  const store = context.deps.sessions;
  if (!store) throw new Error("session store unavailable");
  const body = validated(context, (value, issues) => {
    const loc = ["body"];
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      issues.push({ loc, msg: "model_type" });
      return null;
    }
    const input = value as Record<string, unknown>;
    const allowed = ["action", "session_id", "conversation_state", "quiz_progress"];
    for (const key of Object.keys(input)) if (!allowed.includes(key)) issues.push({ loc: [...loc, key], msg: "extra_forbidden" });
    const action = input.action;
    if (!["create", "get", "save", "delete"].includes(action as string)) issues.push({ loc: [...loc, "action"], msg: "literal_error" });
    if (action === "create") {
      if ("session_id" in input || "conversation_state" in input || "quiz_progress" in input) issues.push({ loc, msg: "create_takes_no_data" });
    } else if (typeof input.session_id !== "string" || !SESSION_ID.test(input.session_id)) {
      issues.push({ loc: [...loc, "session_id"], msg: "pattern" });
    }
    if (action !== "save" && ("conversation_state" in input || "quiz_progress" in input) && action !== "create") {
      issues.push({ loc, msg: "only_save_takes_data" });
    }
    let conversation: string | undefined;
    let quiz: string | undefined;
    if (action === "save") {
      if (!("conversation_state" in input) && !("quiz_progress" in input)) issues.push({ loc, msg: "nothing_to_save" });
      if ("conversation_state" in input) {
        const state = validateState(input.conversation_state, [...loc, "conversation_state"], issues);
        if (state) conversation = pyJson(state);
      }
      if ("quiz_progress" in input) {
        const progress = validateQuizProgress(input.quiz_progress, [...loc, "quiz_progress"], issues);
        if (progress) quiz = pyJson(progress);
      }
    }
    return { action: action as string, sessionId: input.session_id as string, conversation, quiz };
  })!;
  if (body.action === "create") {
    const sessionId = requestId();
    const row = await store.create(sessionId, Date.now() + SESSION_TTL_MS);
    return { status: 200, body: sessionView(row) };
  }
  if (body.action === "delete") {
    await store.remove(body.sessionId);
    return { status: 200, body: { schema_version: "1.0", status: "deleted" } };
  }
  const row =
    body.action === "get"
      ? await store.get(body.sessionId)
      : await store.save(body.sessionId, { conversation: body.conversation, quiz: body.quiz });
  if (!row) throw new ApiHttpError(404, "session_not_found", SESSION_GONE);
  return { status: 200, body: sessionView(row) };
};

interface Route {
  path: string | RegExp;
  methods: Record<string, Handler>;
  enabled?: (settings: () => Settings) => boolean;
}

const ROUTES: Route[] = [
  { path: "/health", methods: { GET: health } },
  // FastAPI's generated document, copied verbatim (see convex/parity/generate.py).
  { path: "/openapi.json", methods: { GET: async () => ({ status: 200, raw: OPENAPI_JSON }) } },
  { path: "/ready", methods: { GET: ready } },
  { path: "/api/capabilities", methods: { GET: capabilities } },
  { path: "/api/predict", methods: { POST: deferred((value, issues) => validatePredict(value, issues)) } },
  { path: "/api/compare", methods: { POST: deferred((value, issues) => validateCompare(value, issues)) } },
  { path: "/api/sensitivity", methods: { POST: deferred((value, issues) => validateSensitivity(value, issues)) } },
  { path: "/api/onboarding/turn", methods: { POST: turn } },
  { path: "/api/advisor", methods: { POST: advisor } },
  { path: "/api/quiz/questions", methods: { GET: quizList } },
  { path: /^\/api\/quiz\/questions\/([^/]+)$/, methods: { GET: quizDetail } },
  { path: "/api/voice/token", methods: { POST: voiceToken } },
  { path: "/api/sessions", methods: { POST: sessions }, enabled: (settings) => settings().sessionsEnabled },
];

function match(route: Route, path: string): string[] | null {
  if (typeof route.path === "string") return route.path === path ? [] : null;
  const found = route.path.exec(path);
  return found ? found.slice(1) : null;
}

function findRoute(path: string, settings: () => Settings): { route: Route; params: string[] } | null {
  for (const route of ROUTES) {
    const params = match(route, path);
    if (params && (!route.enabled || route.enabled(settings))) return { route, params };
  }
  return null;
}

function decodePath(pathname: string): string {
  try {
    return decodeURIComponent(pathname);
  } catch {
    return pathname;
  }
}

/** Starlette CORSMiddleware preflight, for the configured exact origins. */
function preflight(request: Request, origins: string[]): Response {
  const headers: Record<string, string> = {
    Vary: "Origin, Access-Control-Request-Method, Access-Control-Request-Headers, Access-Control-Request-Private-Network",
    "Access-Control-Allow-Methods": "GET, POST",
    "Access-Control-Max-Age": "600",
    "Access-Control-Allow-Headers": "Accept, Accept-Language, Content-Language, Content-Type",
  };
  const failures: string[] = [];
  const origin = request.headers.get("origin")!;
  if (origins.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
  else failures.push("origin");
  if (!["GET", "POST"].includes(request.headers.get("access-control-request-method")!)) failures.push("method");
  const requested = request.headers.get("access-control-request-headers");
  if (requested !== null) {
    const allowed = ["accept", "accept-language", "content-language", "content-type"];
    if (requested.split(",").some((header) => !allowed.includes(header.toLowerCase().trim()))) failures.push("headers");
  }
  if (request.headers.get("access-control-request-private-network") !== null) failures.push("private-network");
  headers["Content-Type"] = "text/plain; charset=utf-8";
  return new Response(failures.length ? `Disallowed CORS ${failures.join(", ")}` : "OK", {
    status: failures.length ? 400 : 200,
    headers,
  });
}

async function readBody(request: Request, cap: number): Promise<Uint8Array | null> {
  if (!request.body) return new Uint8Array(await request.arrayBuffer());
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    // Count actual bytes: a false Content-Length cannot bypass the limit.
    if (size + value.byteLength > cap) {
      await reader.cancel().catch(() => undefined);
      return null;
    }
    chunks.push(value);
    size += value.byteLength;
  }
  const out = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

class Deadline extends Error {}

export async function dispatch(request: Request, deps: Deps): Promise<Response> {
  const id = requestId();
  const url = new URL(request.url);
  const path = decodePath(url.pathname);
  let cached: Settings | undefined;
  const settings = () => (cached ??= loadSettings(deps.env));
  const origin = request.headers.get("origin");
  let origins: string[] = [];
  try {
    origins = settings().corsOrigins;
  } catch {
    // Invalid configuration is reported by the route below; CORS stays closed.
  }
  if (origin !== null && request.method === "OPTIONS" && request.headers.has("access-control-request-method")) {
    return preflight(request, origins);
  }

  const finish = (reply: Reply): Response => {
    const headers = new Headers(reply.headers);
    const text = reply.raw ?? (reply.body === undefined ? undefined : pyJson(reply.body));
    if (text !== undefined) headers.set("content-type", "application/json");
    headers.set("x-request-id", id);
    headers.set("cache-control", "no-store");
    headers.set("x-content-type-options", "nosniff");
    // Starlette CORSMiddleware simple-response headers.
    if (origin !== null) headers.set("Access-Control-Expose-Headers", "X-Request-ID");
    if (origin !== null && origins.includes(origin)) headers.set("Access-Control-Allow-Origin", origin);
    headers.append("Vary", "Origin");
    // HEAD responses carry headers only, as HTTP servers send them.
    return new Response(request.method === "HEAD" ? null : (text ?? null), { status: reply.status, headers });
  };
  const error = (status: number, code: string, message: string, headers?: Record<string, string>) =>
    finish({ status, body: apiError(code, message, id), headers });

  const probe = path === "/health" || path === "/ready";
  let bytes: Uint8Array = new Uint8Array();
  let route: { route: Route; params: string[] } | null = null;
  const work = async (): Promise<Response> => {
    if (!probe) {
      const body = await readBody(request, settings().maxBodyBytes);
      if (body === null) return error(413, "body_too_large", "That message is too long. Please shorten it and try again.");
      bytes = body;
    }
    route = findRoute(path, settings);
    if (!route) {
      const stripped = path.replace(/\/+$/, "");
      if (path !== "/" && stripped !== path && findRoute(stripped, settings)) {
        return finish({ status: 307, headers: { location: `${url.origin}${stripped}${url.search}` } });
      }
      return error(404, "not_found", "We could not find that. Please go back and try again.");
    }
    const handler = route.route.methods[request.method];
    if (!handler) {
      return error(405, "request_rejected", "We could not do that. Please go back and try again.", {
        Allow: Object.keys(route.route.methods).join(", "),
      });
    }
    return finish(await handler({ request, url, params: route.params, bytes, settings, deps, requestId: id }));
  };

  try {
    if (probe) return await work();
    const timeout = settings().requestTimeoutSeconds;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Deadline()), timeout * 1000);
    });
    try {
      return await Promise.race([work(), deadline]);
    } finally {
      clearTimeout(timer);
    }
  } catch (caught) {
    if (caught instanceof ValidationFailed) {
      // Pydantic's default error includes raw input; deliberately omit it.
      return error(422, "invalid_request", invalidInputMessage(caught.issues));
    }
    if (caught instanceof ApiHttpError) return error(caught.status, caught.code, caught.publicMessage, caught.headers);
    if (caught instanceof BadRequest) return error(400, "request_rejected", "We could not do that. Please go back and try again.");
    if (caught instanceof Deadline) return error(504, "request_timeout", "This is taking too long. Please try again.");
    // Never log bodies, headers or exception text: they may hold health data.
    const routePath = route ? String((route as { route: Route }).route.path) : "unmatched";
    const kind = caught instanceof ConfigError ? `ConfigError(${caught.variable})` : caught instanceof Error ? caught.name : "Error";
    console.error(`unhandled error request_id=${id} method=${request.method} route=${routePath} exception=${kind}`);
    return error(500, "internal_error", "Something went wrong on our side. Please try again in a moment.");
  }
}

import { conversationRoute } from "./conversation.ts";
import { wellnessRoute } from "./wellness.ts";
import { documentInfo, readDocument } from "./document-read.ts";
import { type Config, providerInfo, voiceToken } from "./providers.ts";
import { routes, validate } from "./validation.ts";

type Result = { status: number; body: unknown };
type Loader = () => Promise<Config>;
const PREFIXES = ["/functions/v1/lifetwin-api", "/lifetwin-api"];

function pathFor(path: string): string | null {
  for (const prefix of PREFIXES) {
    if (path.startsWith(prefix + "/")) return path.slice(prefix.length);
  }
  return path.startsWith("/api/") || ["/health", "/ready"].includes(path)
    ? path
    : null;
}

export function apiError(
  status: number,
  code: string,
  message: string,
): Result {
  return {
    status,
    body: {
      schema_version: "1.0",
      status: "error",
      code,
      message,
      request_id: null,
    },
  };
}

async function readBody(
  request: Request,
  limit: number,
  timeoutMs = 5000,
): Promise<unknown> {
  if (!request.body) return {};
  const reader = request.body.getReader();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    reader.cancel().catch(() => {});
  }, timeoutMs);
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      size += item.value.length;
      if (size > limit) throw new RangeError("Body limit");
      chunks.push(item.value);
    }
  } finally {
    clearTimeout(timer);
    await reader.cancel().catch(() => {});
  }
  if (timedOut) throw new DOMException("Request deadline", "TimeoutError");
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

/** JWT verification is mandatory at Supabase ingress (supabase/config.toml). */
export function createHandler(load: Loader) {
  let active = 0;
  let activePdfs = 0;
  let windowStart = 0;
  let count = 0;
  return async (request: Request): Promise<Response> => {
    const requestId = crypto.randomUUID().replaceAll("-", "");
    let config: Config = {};
    const origin = request.headers.get("origin");
    const respond = (result: Result) => {
      const headers = new Headers({
        "content-type": "application/json",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
        "x-request-id": requestId,
      });
      const origins = (config.LIFETWIN_CORS_ORIGINS || "").split(",").map((x) =>
        x.trim()
      );
      if (origin && origins.includes(origin) && /^https:\/\//.test(origin)) {
        headers.set("access-control-allow-origin", origin);
        headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
        headers.set(
          "access-control-allow-headers",
          "authorization, apikey, content-type, x-client-info",
        );
        headers.set("access-control-expose-headers", "x-request-id");
        headers.set("vary", "Origin");
      }
      if (result.status === 429) headers.set("retry-after", "60");
      const body = result.body as Record<string, unknown>;
      if (body?.status === "error") body.request_id = requestId;
      return new Response(result.status === 204 ? null : JSON.stringify(body), {
        status: result.status,
        headers,
      });
    };
    try {
      const url = new URL(request.url);
      const path = pathFor(url.pathname);
      if (!path) {
        return respond(apiError(404, "not_found", "We could not find that."));
      }
      if (path === "/health" && request.method === "GET") {
        return respond({
          status: 200,
          body: { status: "ok", service: "lifetwin-backend" },
        });
      }
      const isPdf = path === "/api/documents/read" && request.method === "POST";
      if (active >= 16 || (isPdf && activePdfs >= 1)) {
        return respond(
          apiError(429, "server_busy", "Please try again in a few seconds."),
        );
      }
      const now = Date.now();
      if (now - windowStart >= 60000) {
        windowStart = now;
        count = 0;
      }
      if (++count > 120) {
        return respond(
          apiError(
            429,
            "rate_limit_exceeded",
            "Please wait a minute and try again.",
          ),
        );
      }
      active++;
      if (isPdf) activePdfs++;
      try {
        config = await load();
        if (request.method === "OPTIONS") {
          return respond({ status: 204, body: {} });
        }
        if (path === "/ready" && request.method === "GET") {
          return respond({
            status: 200,
            body: {
              status: "ready",
              prediction: "not_implemented",
              voice: "deferred",
            },
          });
        }
        if (path === "/api/capabilities" && request.method === "GET") {
          const info = providerInfo(config);
          return respond({
            status: 200,
            body: {
              schema_version: "1.0",
              intake: "guided",
              llm_configured: info.configured,
              web_research_configured: false,
              advisor: "curated_educational",
              quiz: "local_scoring_content",
              prediction: "not_implemented",
              voice: config.CARTESIA_API_KEY && config.CARTESIA_VOICE_ID
                ? "available"
                : "unavailable",
              health_data_storage: "none",
              documents: {
                text_extraction: true,
                pdf: documentInfo(config),
              },
              // Who reads and words conversation turns (owner ruling 2026-10-25).
              conversation: {
                ...providerInfo({
                  ...config,
                  PERSONALIZE_PROVIDER: (config.CONVERSATION_PROVIDER ||
                      (config.ANTHROPIC_API_KEY ? "claude" : "muse")) ===
                      "claude"
                    ? "claude"
                    : "muse",
                }),
                routes: [
                  "/api/onboarding/turn",
                  "/api/checkin/turn",
                  "/api/change/turn",
                ],
              },
              personalize: info,
              coach: {
                endpoint: "/api/coach/plan",
                planner: "deterministic_catalog",
                runs: "on_app_open_or_resume",
                personalize: { ...info, daily_cap_per_client: 30 },
              },
            },
          });
        }
        let payload: unknown = {};
        const contract = routes[path];
        if (request.method === "POST" && contract) {
          const configuredPdfLimit = Number(
            config.API_MAX_PDF_BODY_BYTES || 14_000_000,
          );
          const pdfLimit = Number.isSafeInteger(configuredPdfLimit) &&
              configuredPdfLimit >= 1024 && configuredPdfLimit <= 16_000_000
            ? configuredPdfLimit
            : 14_000_000;
          try {
            payload = await readBody(
              request,
              path === "/api/documents/read"
                ? pdfLimit
                : path === "/api/documents/extract"
                ? 393216
                : 32768,
              isPdf ? 10000 : 5000,
            );
          } catch (error) {
            return respond(
              error instanceof DOMException && error.name === "TimeoutError"
                ? apiError(
                  504,
                  "request_timeout",
                  "This is taking too long. Please try again.",
                )
                : error instanceof RangeError
                ? apiError(
                  413,
                  "body_too_large",
                  "That message is too long. Please shorten it.",
                )
                : apiError(
                  422,
                  "invalid_request",
                  "Please check your answers and try again.",
                ),
            );
          }
          if (!validate(contract[0], payload)) {
            return respond(
              apiError(
                422,
                "invalid_request",
                path === "/api/voice/token"
                  ? "Please agree to use your voice first."
                  : "Please check your answers and try again.",
              ),
            );
          }
        } else if (
          !(request.method === "GET" &&
            (path === "/api/quiz/questions" ||
              path.startsWith("/api/quiz/questions/")))
        ) {
          return respond(
            apiError(
              contract ? 405 : 404,
              contract ? "request_rejected" : "not_found",
              "We could not do that.",
            ),
          );
        }
        let result: Result | null = null;
        if (
          ["/api/predict", "/api/compare", "/api/sensitivity"].includes(path)
        ) {
          result = {
            status: 501,
            body: {
              schema_version: "1.0",
              status: "not_implemented",
              code: "prediction_not_implemented",
              message: "This prediction feature is not implemented yet.",
              model_version: null,
              prediction: null,
            },
          };
        } else if (path === "/api/voice/token") {
          const token = await voiceToken(config);
          result = token ? { status: 200, body: token } : apiError(
            503,
            "voice_unavailable",
            "Voice isn't available right now. You can keep going by typing.",
          );
        } else if (path === "/api/documents/read") {
          result = await readDocument(payload, config);
        } else if (
          path.startsWith("/api/onboarding/") ||
          path.startsWith("/api/checkin/") || path.startsWith("/api/change/")
        ) {
          result = await conversationRoute(
            path,
            payload as Record<string, unknown>,
            config,
          );
        } else result = await wellnessRoute(path, payload, url, config);
        if (!result) {
          return respond(apiError(404, "not_found", "We could not find that."));
        }
        const responseSchema = result.status >= 400 && result.status !== 501
          ? "error.schema.json"
          : contract?.[1] ??
            (path === "/api/quiz/questions"
              ? "quiz.schema.json"
              : "quiz.question.schema.json");
        if (!validate(responseSchema, result.body)) {
          return respond(
            apiError(
              503,
              "backend_unavailable",
              "This feature is unavailable. Please try again later.",
            ),
          );
        }
        return respond(result);
      } finally {
        active--;
        if (isPdf) activePdfs--;
      }
    } catch {
      return respond(
        apiError(
          503,
          "backend_unavailable",
          "The service is unavailable. Please try again later.",
        ),
      );
    }
  };
}

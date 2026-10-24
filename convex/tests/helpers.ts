import { vi } from "vitest";
import { dispatch } from "../convex/lib/api";
import type { Env } from "../convex/lib/config";

export const modules = import.meta.glob("../convex/**/*.ts");

export const REQUEST_ID = /"request_id":"[0-9a-f]{32}"/g;
export const mask = (text: string) => text.replace(REQUEST_ID, '"request_id":"<id>"');

export const PROVIDER_ENV_PREFIXES = ["OPENAI_", "LLM_", "TAVILY_", "CARTESIA_", "API_", "CORS_", "SESSION_"];

/** A fetch double that fails the test if any network call happens. */
export function forbidNetwork() {
  const spy = vi.fn(async () => {
    throw new Error("unexpected network call");
  });
  vi.stubGlobal("fetch", spy);
  return spy;
}

export interface Recorded {
  method: string;
  url: string;
  authorization: string | null;
  cartesia_version: string | null;
  json: unknown;
  signal: AbortSignal | null | undefined;
}

/** A fetch double that records requests and answers with a fixed upstream response. */
export function fakeUpstream(status: number, body: string, headers: Record<string, string> = {}) {
  const seen: Recorded[] = [];
  const spy = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    const text = init?.body ? String(init.body) : "";
    seen.push({
      method: request.method,
      url: request.url,
      authorization: request.headers.get("authorization"),
      cartesia_version: request.headers.get("cartesia-version"),
      json: text ? JSON.parse(text) : null,
      signal: init?.signal,
    });
    return new Response(body, { status, headers });
  });
  vi.stubGlobal("fetch", spy);
  return { spy, seen };
}

export async function call(
  env: Env,
  method: string,
  path: string,
  options: { body?: string | null; contentType?: string | null; headers?: Record<string, string> } = {},
) {
  const headers: Record<string, string> = { ...(options.headers ?? {}) };
  if (options.contentType) headers["content-type"] = options.contentType;
  const response = await dispatch(
    new Request(`http://127.0.0.1:3211${path}`, {
      method,
      headers,
      body: options.body === null || options.body === undefined ? undefined : options.body,
    }),
    { env },
  );
  return { response, text: await response.text() };
}

export async function json(env: Env, method: string, path: string, body?: unknown) {
  const { response, text } = await call(env, method, path, {
    body: body === undefined ? undefined : JSON.stringify(body),
    contentType: body === undefined ? undefined : "application/json",
  });
  return { status: response.status, headers: response.headers, text, body: JSON.parse(text || "null") };
}

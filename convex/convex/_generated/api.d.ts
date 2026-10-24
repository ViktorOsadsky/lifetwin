/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as content_openapi from "../content/openapi.js";
import type * as crons from "../crons.js";
import type * as http from "../http.js";
import type * as lib_advisor from "../lib/advisor.js";
import type * as lib_api from "../lib/api.js";
import type * as lib_config from "../lib/config.js";
import type * as lib_conversation from "../lib/conversation.js";
import type * as lib_jsonload from "../lib/jsonload.js";
import type * as lib_models from "../lib/models.js";
import type * as lib_parsing from "../lib/parsing.js";
import type * as lib_providers from "../lib/providers.js";
import type * as lib_py from "../lib/py.js";
import type * as lib_quiz from "../lib/quiz.js";
import type * as lib_sessionsCore from "../lib/sessionsCore.js";
import type * as lib_voice from "../lib/voice.js";
import type * as sessions from "../sessions.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "content/openapi": typeof content_openapi;
  crons: typeof crons;
  http: typeof http;
  "lib/advisor": typeof lib_advisor;
  "lib/api": typeof lib_api;
  "lib/config": typeof lib_config;
  "lib/conversation": typeof lib_conversation;
  "lib/jsonload": typeof lib_jsonload;
  "lib/models": typeof lib_models;
  "lib/parsing": typeof lib_parsing;
  "lib/providers": typeof lib_providers;
  "lib/py": typeof lib_py;
  "lib/quiz": typeof lib_quiz;
  "lib/sessionsCore": typeof lib_sessionsCore;
  "lib/voice": typeof lib_voice;
  sessions: typeof sessions;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};

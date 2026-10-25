import { createHandler } from "./handler.ts";
import { loadConfig } from "./settings.ts";

Deno.serve(createHandler(loadConfig));

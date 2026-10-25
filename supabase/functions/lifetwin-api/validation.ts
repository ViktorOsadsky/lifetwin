import { Ajv2020 } from "npm:ajv@8.17.1/dist/2020.js";
import schemas from "./schemas.json" with { type: "json" };

const ajv = new Ajv2020({ strict: false, useDefaults: true, allErrors: false });
ajv.addFormat("date", {
  type: "string",
  validate: (value: string) =>
    /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)),
});
ajv.addFormat("date-time", {
  type: "string",
  validate: (value: string) => Number.isFinite(Date.parse(value)),
});
ajv.addFormat("uri", {
  type: "string",
  validate: (value: string) => {
    try {
      return Boolean(new URL(value).protocol);
    } catch {
      return false;
    }
  },
});
const validators = new Map(
  Object.entries(schemas).map(([name, schema]) => [name, ajv.compile(schema)]),
);

/** No validation errors are returned: they may contain the person's input. */
export function validate(name: string, value: unknown): boolean {
  const validator = validators.get(name);
  if (!validator) throw new Error("Unknown contract");
  return Boolean(validator(value));
}

export const routes: Record<string, [string, string]> = {
  "/api/onboarding/turn": [
    "conversation.request.schema.json",
    "conversation.schema.json",
  ],
  "/api/checkin/start": [
    "checkin.start.request.schema.json",
    "checkin.schema.json",
  ],
  "/api/checkin/turn": [
    "checkin.turn.request.schema.json",
    "checkin.schema.json",
  ],
  "/api/change/start": [
    "change.start.request.schema.json",
    "change.schema.json",
  ],
  "/api/change/turn": ["change.turn.request.schema.json", "change.schema.json"],
  "/api/advisor": ["advisor.request.schema.json", "advisor.schema.json"],
  "/api/recommendations": [
    "recommendations.request.schema.json",
    "recommendations.schema.json",
  ],
  "/api/coach/plan": [
    "coach.plan.request.schema.json",
    "coach.plan.schema.json",
  ],
  "/api/documents/extract": [
    "documents.extract.request.schema.json",
    "documents.extract.schema.json",
  ],
  "/api/voice/token": [
    "voice.token.request.schema.json",
    "voice.token.schema.json",
  ],
  "/api/predict": ["prediction.request.schema.json", "compare.schema.json"],
  "/api/compare": ["compare.request.schema.json", "compare.schema.json"],
  "/api/sensitivity": [
    "sensitivity.request.schema.json",
    "sensitivity.schema.json",
  ],
};

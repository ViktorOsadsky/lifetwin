// Request validation mirroring the strict Pydantic models in server/lifetwin.
// Errors carry Pydantic-style locations so the redacted 422 message names the
// same fields as FastAPI's handler, and nothing echoes submitted values.

import { pyLen, pyStrip } from "./py";

export const SCHEMA_VERSION = "1.0";

export const FIELDS = [
  "age",
  "sex",
  "height_cm",
  "weight_kg",
  "sleep_hours",
  "exercise_minutes_weekly",
  "smoking_status",
  "alcohol_drinks_weekly",
  "diabetes",
  "systolic_bp",
  "diastolic_bp",
] as const;
export type ProfileField = (typeof FIELDS)[number];
export type ProfileValue = number | string | boolean;
export type Profile = Partial<Record<ProfileField, ProfileValue>>;
export type FullProfile = Record<ProfileField, ProfileValue | null>;

export const BP_ORDER_MESSAGE = "The top blood pressure number is usually the bigger one. Please check your reading.";

export type Loc = (string | number)[];
export interface Issue {
  loc: Loc;
  msg: string;
}

export class ValidationFailed extends Error {
  constructor(readonly issues: Issue[]) {
    super("validation failed");
  }
}

const FIELD_WORDS: Record<string, string> = {
  age: "age",
  sex: "sex",
  height_cm: "height",
  weight_kg: "weight",
  sleep_hours: "hours of sleep",
  exercise_minutes_weekly: "weekly exercise minutes",
  smoking_status: "smoking",
  alcohol_drinks_weekly: "drinks per week",
  diabetes: "diabetes",
  systolic_bp: "top blood pressure number",
  diastolic_bp: "bottom blood pressure number",
  text: "your message",
  limit: "number of questions",
  question_id: "question",
  voice_consent: "voice",
};

/** Port of lifetwin.app.invalid_input_message. */
export function invalidInputMessage(issues: Issue[]): string {
  if (issues.some((issue) => issue.loc.length > 0 && issue.loc[issue.loc.length - 1] === "voice_consent")) {
    return "Please agree to use your voice first.";
  }
  if (issues.some((issue) => issue.msg.includes(BP_ORDER_MESSAGE))) return BP_ORDER_MESSAGE;
  const names: string[] = [];
  for (const issue of issues) {
    const key = issue.loc.length > 0 ? String(issue.loc[issue.loc.length - 1]) : "";
    const word = Object.prototype.hasOwnProperty.call(FIELD_WORDS, key) ? FIELD_WORDS[key] : undefined;
    if (word && !names.includes(word)) names.push(word);
  }
  if (names.length > 0) return `Please check these answers: ${names.join(", ")}. Then try again.`;
  return "Some answers do not look right. Please check them and try again.";
}

type Obj = Record<string, unknown>;
const isObject = (value: unknown): value is Obj =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const isNumber = (value: unknown): value is number => typeof value === "number";

/** Strict Pydantic model: object input, defined fields first, then forbidden extras. */
function model(value: unknown, loc: Loc, issues: Issue[], fields: string[], body: (input: Obj) => void): boolean {
  if (!isObject(value)) {
    issues.push({ loc, msg: "model_type" });
    return false;
  }
  const before = issues.length;
  body(value);
  for (const key of Object.keys(value)) {
    if (!fields.includes(key)) issues.push({ loc: [...loc, key], msg: "extra_forbidden" });
  }
  return issues.length === before;
}

// Field checkers return the value or push an issue.
function wholeNumber(value: unknown, loc: Loc, issues: Issue[], min: number, max: number): number | null {
  if (value === null) return null;
  // Integral floats (35.0) are accepted like the WholeNumber validator.
  if (!isNumber(value) || !Number.isFinite(value) || !Number.isInteger(value) || value < min || value > max) {
    issues.push({ loc, msg: "int" });
    return null;
  }
  return value;
}

function finiteNumber(value: unknown, loc: Loc, issues: Issue[], min: number, max: number): number | null {
  if (value === null) return null;
  if (!isNumber(value) || !Number.isFinite(value) || value < min || value > max) {
    issues.push({ loc, msg: "float" });
    return null;
  }
  return value;
}

function literal<T extends string>(value: unknown, loc: Loc, issues: Issue[], options: readonly T[], nullable = true): T | null {
  if (value === null && nullable) return null;
  if (typeof value !== "string" || !(options as readonly string[]).includes(value)) {
    issues.push({ loc, msg: "literal_error" });
    return null;
  }
  return value as T;
}

function strictBool(value: unknown, loc: Loc, issues: Issue[], nullable = true): boolean | null {
  if (value === null && nullable) return null;
  if (typeof value !== "boolean") {
    issues.push({ loc, msg: "bool" });
    return null;
  }
  return value;
}

export const SEXES = ["female", "male", "intersex", "prefer_not_to_say"] as const;
export const SMOKING = ["never", "former", "current", "unknown"] as const;

export function emptyProfile(): FullProfile {
  return Object.fromEntries(FIELDS.map((field) => [field, null])) as FullProfile;
}

/** HealthProfile: ranges validate data, not model eligibility. */
export function validateProfile(value: unknown, loc: Loc, issues: Issue[]): FullProfile | null {
  const profile = emptyProfile();
  const ok = model(value, loc, issues, [...FIELDS], (input) => {
    const get = (field: ProfileField) => (field in input ? input[field] : null);
    const at = (field: ProfileField): Loc => [...loc, field];
    profile.age = wholeNumber(get("age"), at("age"), issues, 0, 120);
    profile.sex = literal(get("sex"), at("sex"), issues, SEXES);
    profile.height_cm = finiteNumber(get("height_cm"), at("height_cm"), issues, 50, 280);
    profile.weight_kg = finiteNumber(get("weight_kg"), at("weight_kg"), issues, 10, 700);
    profile.sleep_hours = finiteNumber(get("sleep_hours"), at("sleep_hours"), issues, 0, 24);
    profile.exercise_minutes_weekly = wholeNumber(get("exercise_minutes_weekly"), at("exercise_minutes_weekly"), issues, 0, 10080);
    profile.smoking_status = literal(get("smoking_status"), at("smoking_status"), issues, SMOKING);
    profile.alcohol_drinks_weekly = finiteNumber(get("alcohol_drinks_weekly"), at("alcohol_drinks_weekly"), issues, 0, 200);
    profile.diabetes = strictBool(get("diabetes"), at("diabetes"), issues);
    profile.systolic_bp = wholeNumber(get("systolic_bp"), at("systolic_bp"), issues, 40, 300);
    profile.diastolic_bp = wholeNumber(get("diastolic_bp"), at("diastolic_bp"), issues, 20, 200);
  });
  if (!ok) return null;
  if (profile.systolic_bp !== null && profile.diastolic_bp !== null && (profile.systolic_bp as number) <= (profile.diastolic_bp as number)) {
    issues.push({ loc, msg: `Value error, ${BP_ORDER_MESSAGE}` });
    return null;
  }
  return profile;
}

/** HealthProfile.model_validate(values).model_dump(exclude_none=True), or null when invalid. */
export function validatedValues(values: Profile): Profile | null {
  const issues: Issue[] = [];
  const profile = validateProfile(values, [], issues);
  return profile ? compact(profile) : null;
}

/** model_dump(exclude_none=True) in field order. */
export function compact(profile: Profile | FullProfile): Profile {
  const out: Profile = {};
  for (const field of FIELDS) {
    const value = profile[field];
    if (value !== null && value !== undefined) out[field] = value;
  }
  return out;
}

export function fullProfile(values: Profile): FullProfile {
  const profile = emptyProfile();
  for (const field of FIELDS) if (values[field] !== undefined) profile[field] = values[field]!;
  return profile;
}

export const PHASES = ["idle", "asking", "confirming", "ready", "cancelled"] as const;
export type Phase = (typeof PHASES)[number];

export interface ConversationState {
  phase: Phase;
  confirmed_profile: FullProfile;
  pending_profile: FullProfile;
  current_field: ProfileField | null;
  skipped_fields: ProfileField[];
}

export function newState(phase: Phase = "idle"): ConversationState {
  return {
    phase,
    confirmed_profile: emptyProfile(),
    pending_profile: emptyProfile(),
    current_field: null,
    skipped_fields: [],
  };
}

const STATE_FIELDS = ["phase", "confirmed_profile", "pending_profile", "current_field", "skipped_fields"];

export function validateState(value: unknown, loc: Loc, issues: Issue[]): ConversationState | null {
  const state = newState();
  const ok = model(value, loc, issues, STATE_FIELDS, (input) => {
    if ("phase" in input) state.phase = (literal(input.phase, [...loc, "phase"], issues, PHASES, false) ?? "idle") as Phase;
    if ("confirmed_profile" in input) state.confirmed_profile = validateProfile(input.confirmed_profile, [...loc, "confirmed_profile"], issues) ?? emptyProfile();
    if ("pending_profile" in input) state.pending_profile = validateProfile(input.pending_profile, [...loc, "pending_profile"], issues) ?? emptyProfile();
    if ("current_field" in input) state.current_field = literal(input.current_field, [...loc, "current_field"], issues, FIELDS);
    if ("skipped_fields" in input) {
      const skipped = input.skipped_fields;
      if (!Array.isArray(skipped)) {
        issues.push({ loc: [...loc, "skipped_fields"], msg: "list_type" });
      } else if (skipped.length > 11) {
        issues.push({ loc: [...loc, "skipped_fields"], msg: "too_long" });
      } else {
        state.skipped_fields = skipped.map(
          (item, index) => literal(item, [...loc, "skipped_fields", index], issues, FIELDS, false) as ProfileField,
        );
      }
    }
  });
  if (!ok) return null;
  const pending = Object.keys(compact(state.pending_profile)).length > 0;
  const problem =
    pending !== (state.phase === "confirming")
      ? "Only the confirming phase may contain pending values"
      : new Set(state.skipped_fields).size !== state.skipped_fields.length
        ? "Skipped fields must be unique"
        : state.phase === "asking" && state.current_field === null
          ? "An asking state requires a current field"
          : ["ready", "cancelled", "idle"].includes(state.phase) && state.current_field !== null
            ? "This phase cannot have a current field"
            : null;
  if (problem) {
    issues.push({ loc, msg: `Value error, ${problem}` });
    return null;
  }
  return state;
}

export const ACTIONS = ["start", "reply", "confirm", "correct", "skip", "cancel", "import"] as const;
export type Action = (typeof ACTIONS)[number];

export interface TurnRequest {
  action: Action;
  state: ConversationState;
  text: string | null;
  input_mode: "text" | "transcript";
  field: ProfileField | null;
  provider_consent: boolean;
  /** "import": values the user already confirmed one by one on the phone (Apple Health read-back). */
  values: FullProfile | null;
}

const TURN_FIELDS = ["action", "state", "text", "input_mode", "field", "provider_consent", "values"];

export function validateTurn(value: unknown, issues: Issue[]): TurnRequest | null {
  const loc: Loc = ["body"];
  const request: TurnRequest = {
    action: "start",
    state: newState(),
    text: null,
    input_mode: "text",
    field: null,
    provider_consent: false,
    values: null,
  };
  const ok = model(value, loc, issues, TURN_FIELDS, (input) => {
    if (!("action" in input)) issues.push({ loc: [...loc, "action"], msg: "missing" });
    else request.action = (literal(input.action, [...loc, "action"], issues, ACTIONS, false) ?? "start") as Action;
    if ("state" in input) request.state = validateState(input.state, [...loc, "state"], issues) ?? newState();
    if ("text" in input && input.text !== null) {
      const text = input.text;
      if (typeof text !== "string" || pyLen(text) < 1 || pyLen(text) > 2000) issues.push({ loc: [...loc, "text"], msg: "string" });
      else request.text = text;
    }
    if ("input_mode" in input) request.input_mode = (literal(input.input_mode, [...loc, "input_mode"], issues, ["text", "transcript"] as const, false) ?? "text") as "text" | "transcript";
    if ("field" in input) request.field = literal(input.field, [...loc, "field"], issues, FIELDS);
    if ("provider_consent" in input) request.provider_consent = strictBool(input.provider_consent, [...loc, "provider_consent"], issues, false) ?? false;
    if ("values" in input && input.values !== null) request.values = validateProfile(input.values, [...loc, "values"], issues);
  });
  if (!ok) return null;
  const problem =
    request.action === "import" && !(request.values && Object.keys(compact(request.values)).length > 0)
      ? "An import requires at least one confirmed value"
      : request.action !== "import" && request.values !== null
        ? "Only the import action accepts values"
        : ["reply", "correct"].includes(request.action) && !pyStrip(request.text ?? "")
      ? "A reply or correction requires nonempty text"
      : !["reply", "correct"].includes(request.action) && request.text !== null
        ? "Only reply and correct actions accept text"
        : request.field !== null && !["correct", "skip"].includes(request.action)
          ? "An explicit field is accepted only for correction or skipping"
          : null;
  if (problem) {
    issues.push({ loc, msg: `Value error, ${problem}` });
    return null;
  }
  return request;
}

export const TOPICS = ["physical_activity", "sleep", "nutrition", "smoking", "supplements"] as const;
export type ResearchTopic = (typeof TOPICS)[number];

export interface AdvisorRequest {
  profile: FullProfile | null;
  topics: ResearchTopic[];
  use_web_research: boolean;
}

export function validateAdvisor(value: unknown, issues: Issue[]): AdvisorRequest | null {
  const loc: Loc = ["body"];
  const request: AdvisorRequest = { profile: null, topics: ["physical_activity", "sleep", "nutrition"], use_web_research: false };
  const ok = model(value, loc, issues, ["schema_version", "profile", "topics", "use_web_research"], (input) => {
    if ("schema_version" in input) literal(input.schema_version, [...loc, "schema_version"], issues, ["1.0"] as const, false);
    if ("profile" in input && input.profile !== null) request.profile = validateProfile(input.profile, [...loc, "profile"], issues);
    if ("topics" in input) {
      const topics = input.topics;
      if (!Array.isArray(topics)) {
        issues.push({ loc: [...loc, "topics"], msg: "list_type" });
      } else if (topics.length < 1 || topics.length > 3) {
        issues.push({ loc: [...loc, "topics"], msg: "length" });
      } else {
        const before = issues.length;
        const parsed = topics.map((topic, index) => literal(topic, [...loc, "topics", index], issues, TOPICS, false) as ResearchTopic);
        if (issues.length === before) {
          if (new Set(parsed).size !== parsed.length) issues.push({ loc: [...loc, "topics"], msg: "Value error, Select each topic only once." });
          else request.topics = parsed;
        }
      }
    }
    if ("use_web_research" in input) request.use_web_research = strictBool(input.use_web_research, [...loc, "use_web_research"], issues, false) ?? false;
  });
  return ok ? request : null;
}

export function validatePredict(value: unknown, issues: Issue[]): boolean {
  return validateProfile(value, ["body"], issues) !== null;
}

export function validateCompare(value: unknown, issues: Issue[]): boolean {
  const loc: Loc = ["body"];
  return model(value, loc, issues, ["baseline", "scenario"], (input) => {
    for (const key of ["baseline", "scenario"]) {
      if (!(key in input)) issues.push({ loc: [...loc, key], msg: "missing" });
      else validateProfile(input[key], [...loc, key], issues);
    }
  });
}

export function validateSensitivity(value: unknown, issues: Issue[]): boolean {
  const loc: Loc = ["body"];
  return model(value, loc, issues, ["profile"], (input) => {
    if (!("profile" in input)) issues.push({ loc: [...loc, "profile"], msg: "missing" });
    else validateProfile(input.profile, [...loc, "profile"], issues);
  });
}

export function validateVoiceToken(value: unknown, issues: Issue[]): boolean {
  const loc: Loc = ["body"];
  return model(value, loc, issues, ["voice_consent"], (input) => {
    // Only an explicit true is accepted; false or missing is rejected as 422.
    if (input.voice_consent !== true) issues.push({ loc: [...loc, "voice_consent"], msg: "literal_error" });
  });
}

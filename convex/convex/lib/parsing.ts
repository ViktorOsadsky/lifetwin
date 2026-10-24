// Port of server/lifetwin/onboarding/parsing.py (including PR #18's spoken
// answer normalization). Conservative keyless extraction: ambiguous values
// remain unconfirmed. Regular expressions are written in Python syntax and
// translated so \s, \d, \w and \b keep CPython's Unicode meaning.

import { type Profile, type ProfileField, validatedValues } from "./models";
import { B, D, W, WS, escapeRegExp, pyFloat, pyRound, pySplit, pyStrip, rstripChars } from "./py";

/** Compile a Python-syntax pattern. */
function py(pattern: string, flags = ""): RegExp {
  const source = pattern.replace(/\\\\|\\[sdwb]/g, (token) =>
    token === "\\\\" ? token : { "\\s": WS, "\\d": D, "\\w": W, "\\b": B }[token]!,
  );
  return new RegExp(source, `u${flags}`);
}
const full = (pattern: string, flags = "") => py(`^(?:${pattern})$`, flags);
const fullmatch = (pattern: string, value: string, flags = "") => full(pattern, flags).exec(value);
const sub = (pattern: string, replacement: string | ((...args: any[]) => string), value: string, flags = "") =>
  value.replace(py(pattern, `g${flags}`), replacement as any);

export const QUESTIONS: Record<ProfileField, string> = {
  age: "How old are you? You can skip any question you don't know.",
  sex: 'Are you a woman or a man? You can also say intersex, or "prefer not to say".',
  height_cm: "How tall are you? For example, 5 feet 10 inches, or 178 cm.",
  weight_kg: "How much do you weigh? For example, 160 pounds, or 72 kg.",
  sleep_hours: "How many hours do you usually sleep each night? For example, 7 hours.",
  exercise_minutes_weekly:
    "How many minutes of exercise do you get in a whole week? " +
    "For example, a 30-minute walk 5 days a week is 150 minutes.",
  smoking_status: "Do you smoke now, did you smoke in the past, or have you never smoked?",
  alcohol_drinks_weekly:
    "How many alcoholic drinks do you usually have in a week? " + 'For example, 3 drinks. If you don\'t drink, say "none".',
  diabetes:
    "Has a doctor ever told you that you have diabetes? Please say yes or no. " + 'If you\'re not sure, say "I don\'t know".',
  systolic_bp:
    "What is your blood pressure? For example, 120 over 80. " + 'If you don\'t know it, just say "I don\'t know".',
  diastolic_bp:
    "What is the bottom number of your blood pressure? For example, the 80 in 120 over 80. " +
    'If you don\'t know it, just say "I don\'t know".',
};

// Plain names for messages; code identifiers never reach the person.
export const FRIENDLY_LABELS: Record<ProfileField, string> = {
  age: "age",
  sex: "sex",
  height_cm: "height",
  weight_kg: "weight",
  sleep_hours: "sleep",
  exercise_minutes_weekly: "exercise",
  smoking_status: "smoking",
  alcohol_drinks_weekly: "alcohol",
  diabetes: "diabetes",
  systolic_bp: "top blood pressure number",
  diastolic_bp: "bottom blood pressure number",
};

export const EXAMPLES: Record<ProfileField, string> = {
  age: '"I\'m 72"',
  sex: '"a woman"',
  height_cm: '"5 feet 10 inches"',
  weight_kg: '"160 pounds"',
  sleep_hours: '"7 hours"',
  exercise_minutes_weekly: '"150 minutes a week"',
  smoking_status: '"I never smoked"',
  alcohol_drinks_weekly: '"3 drinks a week"',
  diabetes: '"I don\'t have diabetes"',
  systolic_bp: '"120 over 80"',
  diastolic_bp: '"80"',
};

const LABELS: Record<string, ProfileField> = {
  age: "age",
  sex: "sex",
  height: "height_cm",
  height_cm: "height_cm",
  weight: "weight_kg",
  weight_kg: "weight_kg",
  sleep: "sleep_hours",
  sleep_hours: "sleep_hours",
  exercise: "exercise_minutes_weekly",
  exercise_minutes_weekly: "exercise_minutes_weekly",
  smoking: "smoking_status",
  smoking_status: "smoking_status",
  alcohol: "alcohol_drinks_weekly",
  alcohol_drinks_weekly: "alcohol_drinks_weekly",
  diabetes: "diabetes",
  systolic: "systolic_bp",
  systolic_bp: "systolic_bp",
  diastolic: "diastolic_bp",
  diastolic_bp: "diastolic_bp",
};

const SKIP_WORDS = new Set([
  "skip",
  "skip it",
  "skip this",
  "skip this one",
  "pass",
  "next",
  "unknown",
  "i don't know",
  "i do not know",
  "don't know",
  "dont know",
  "i dont know",
  "not sure",
  "i'm not sure",
  "im not sure",
  "i am not sure",
  "unsure",
  "no idea",
  "i have no idea",
  "i don't remember",
  "i do not remember",
  "don't remember",
  "i'd rather not say",
  "i would rather not say",
  "rather not say",
  "prefer not to say",
  "i prefer not to say",
]);
// These record an answer for sex instead of skipping the question.
const SEX_PREFER_NOT = ["prefer not to say", "i prefer not to say", "i'd rather not say", "i would rather not say", "rather not say"];
// "Do you know your blood pressure?" is commonly answered with a plain no.
const BP_NO = new Set(["no", "nope", "no i don't", "no i do not", "i don't"]);
export const BP_ORDER_MESSAGE =
  "The top number is usually the bigger one. Could you check your reading? " + "For example, 120 over 80.";

// A provider may assign a quote to a field other than the one asked only when
// the clause itself names that field: bare "160" for weight is not systolic.
const FIELD_CUES: Record<ProfileField, string> = {
  age: String.raw`\b(?:age|years?|yrs?|old)\b`,
  sex: String.raw`\b(?:sex|female|male|intersex|woman|man)\b`,
  height_cm: String.raw`height|tall|cm\b|centimet|met(?:er|re)|\d\s*m\b|ft\b|feet|foot|inch|\d\s*in\b|['"]`,
  weight_kg: String.raw`weigh|kg\b|kilo|lbs?\b|pound`,
  sleep_hours: String.raw`sleep|night`,
  exercise_minutes_weekly: String.raw`exercis|minutes?|mins?\b|workout|walk|week`,
  smoking_status: String.raw`smok|cigar`,
  alcohol_drinks_weekly: String.raw`drink|alcohol|beer|wine`,
  diabetes: String.raw`diabet`,
  systolic_bp: String.raw`systolic|blood pressure|mmhg|\btop\b|\d\s*(?:/|over)\s*\d`,
  diastolic_bp: String.raw`diastolic|blood pressure|mmhg|\bbottom\b|\d\s*(?:/|over)\s*\d`,
};

// Bound numeric tokens before conversion, as well as validating profile ranges.
const NUMBER = String.raw`(\d{1,6}(?:\.\d{1,6})?)`;
const PREFIXES: Record<ProfileField, string> = {
  age: "(?:i am|i'm|my age is)",
  sex: "(?:i am|i'm|my sex is)",
  height_cm: "(?:i am|i'm|my height is)",
  weight_kg: "(?:i weigh|my weight is)",
  sleep_hours: "(?:i sleep|my sleep is)",
  exercise_minutes_weekly: "(?:i exercise)",
  alcohol_drinks_weekly: "(?:i drink)",
  smoking_status: "(?!)",
  diabetes: "(?!)",
  systolic_bp: "(?:my systolic blood pressure is|my systolic is|my blood pressure is)",
  diastolic_bp: "(?:my diastolic blood pressure is|my diastolic is|my blood pressure is)",
};
const QUOTES: Record<string, string> = {
  "’": "'",
  "‘": "'",
  "“": '"',
  "”": '"',
  "′": "'",
  "″": '"',
};
const BP_PAIR = String.raw`(\d{2,3})\s*(?:/|over)\s*(\d{2,3})(?:\s*mmhg)?`;

/** Map smart punctuation (iOS default) and prime marks to ASCII; collapse spaces. */
export function normalizeText(text: string): string {
  const translated = text.replace(/[‘’“”′″]/g, (char) => QUOTES[char]);
  return pySplit(translated).join(" ");
}

const UNITS_WORDS: Record<string, number> = {
  zero: 0,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  eleven: 11,
  twelve: 12,
  thirteen: 13,
  fourteen: 14,
  fifteen: 15,
  sixteen: 16,
  seventeen: 17,
  eighteen: 18,
  nineteen: 19,
};
const TENS_WORDS: Record<string, number> = {
  twenty: 20,
  thirty: 30,
  forty: 40,
  fifty: 50,
  sixty: 60,
  seventy: 70,
  eighty: 80,
  ninety: 90,
};
const UNITS_ALT = Object.keys(UNITS_WORDS).join("|");
const NUMBER_WORDS =
  String.raw`\b(?:(a|one|two) hundred(?: and)? )?(?:(` +
  Object.keys(TENS_WORDS).join("|") +
  String.raw`)(?:[ -](` +
  UNITS_ALT +
  String.raw`))?|(` +
  UNITS_ALT +
  String.raw`))\b` +
  String.raw`|\b(a|one|two) hundred\b`;
const HUNDREDS: Record<string, number> = { a: 100, one: 100, two: 200 };

/** Spoken answers arrive as words: "five foot eight" -> "5 foot 8". */
function numberWords(value: string): string {
  const digits = (_match: string, g1?: string, g2?: string, g3?: string, g4?: string, g5?: string) => {
    const hundreds = g1 || g5;
    let total = hundreds ? HUNDREDS[hundreds] : 0;
    if (g2) total += TENS_WORDS[g2] + (g3 ? UNITS_WORDS[g3] : 0);
    else if (g4) total += UNITS_WORDS[g4];
    return String(total);
  };
  value = sub(String.raw`\b(?:half an hour|a half hour)\b`, "30 minutes", value);
  return sub(NUMBER_WORDS, digits, value);
}

// Everyday speech around an otherwise explicit answer. Real uncertainty,
// negation and past or hypothetical tense are never stripped.
const FILLERS = String.raw`^(?:(?:oh|well|um|uh|so|hmm|ok|okay)\s+)+`;
const HABIT = String.raw`^(?:usually|normally|typically|generally)\s+`;
// Only verbs that belong to the asked field: "I weigh 70" must never answer the age question.
const HABIT_VERBS: Partial<Record<ProfileField, string>> = {
  sleep_hours: "get|sleep",
  exercise_minutes_weekly: "do|get|walk|exercise",
  weight_kg: "weigh",
  alcohol_drinks_weekly: "have|drink",
};
const APPROX = String.raw`\b(?:about|around|roughly|approximately|close to|nearly|almost)\s+(?=\d)`;
const TRAILING =
  String.raw`\s+(?:i think|i guess|i believe|or so|give or take|more or less` + String.raw`|these days|nowadays|right now|at the moment)$`;
const ACTIVITY = String.raw`\s+of\s+(?:walking|exercise|exercising|activity|swimming|biking|cycling|gardening|dancing)\b`;

function phrase(field: ProfileField, text: string): string {
  let value = pyStrip(rstripChars(normalizeText(text).toLowerCase(), ".!?"));
  // Commas are pauses inside one spoken answer ("no, I don't"; "5 feet, 10 inches").
  value = pySplit(value.replace(/,/g, " ")).join(" ");
  value = sub(FILLERS, "", value);
  value = sub("^" + PREFIXES[field] + String.raw`\s+`, "", value);
  value = sub(HABIT, "", value);
  const verbs = HABIT_VERBS[field];
  if (verbs) value = sub(String.raw`^i\s+(?:usually\s+|normally\s+|typically\s+)?(?:` + verbs + String.raw`)\s+`, "", value);
  value = numberWords(value);
  value = sub(TRAILING, "", value);
  if (field === "exercise_minutes_weekly") value = sub(ACTIVITY, "", value);
  value = sub(APPROX, "", value);
  return sub(String.raw`(\d+) and a half\b`, "$1.5", value);
}

export function isSkip(text: string, field: ProfileField): boolean {
  const value = pySplit(rstripChars(normalizeText(text).toLowerCase().replace(/,/g, " "), ".!?")).join(" ");
  if (field === "smoking_status" && value === "unknown") return false;
  if (field === "sex" && SEX_PREFER_NOT.includes(value)) return false;
  if ((field === "systolic_bp" || field === "diastolic_bp") && BP_NO.has(value)) return true;
  return SKIP_WORDS.has(value);
}

function number(value: string, suffix = ""): number | null {
  const match = fullmatch(NUMBER + suffix, value);
  return match ? pyFloat(match[1]) : null;
}

const SEX_ANSWERS: Record<string, string> = {
  female: "female",
  woman: "female",
  "a woman": "female",
  male: "male",
  man: "male",
  "a man": "male",
  intersex: "intersex",
  prefer_not_to_say: "prefer_not_to_say",
  ...Object.fromEntries(SEX_PREFER_NOT.map((item) => [item, "prefer_not_to_say"])),
};
const SMOKING_ANSWERS: Record<string, string> = {
  never: "never",
  "never smoked": "never",
  "i never smoked": "never",
  "i've never smoked": "never",
  "i have never smoked": "never",
  former: "former",
  "formerly smoked": "former",
  "in the past": "former",
  "i smoked in the past": "former",
  "i used to smoke": "former",
  "i quit": "former",
  "i quit smoking": "former",
  current: "current",
  "currently smoke": "current",
  "i smoke": "current",
  "i smoke now": "current",
  "yes i smoke": "current",
  unknown: "unknown",
};
const DIABETES_YES = new Set([
  "yes",
  "yes diagnosed",
  "yes i do",
  "yes i have diabetes",
  "i have diabetes",
  "i have been diagnosed with diabetes",
]);
const DIABETES_NO = new Set([
  "no",
  "nope",
  "no i don't",
  "no i do not",
  "no diagnosis",
  "i don't have diabetes",
  "i do not have diabetes",
  "no i don't have diabetes",
  "i have not been diagnosed with diabetes",
]);
const own = <T>(table: Record<string, T>, key: string): T | null =>
  Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null;

const INTEGER_FIELDS = new Set<ProfileField>(["age", "exercise_minutes_weekly", "systolic_bp", "diastolic_bp"]);

/** Accept explicit single measurements; do not guess units or diagnoses. */
export function parseValue(field: ProfileField, text: string): Profile {
  let value = phrase(field, text);
  let result: number | string | boolean | null = null;
  if (field === "age") {
    result = number(value, String.raw`(?:\s*(?:years?(?: old)?|yrs?))?`);
  } else if (field === "height_cm") {
    value = sub(String.raw`\s+tall$`, "", value);
    const cm = number(value, String.raw`\s*(?:cm|centimeters?|centimetres?)`);
    const meters = number(value, String.raw`\s*(?:m|meters?|metres?)`);
    const inches = number(value, String.raw`\s*(?:in|inches|inch|")`);
    const feet = fullmatch(
      String.raw`(\d{1,2})\s*(?:ft\.?|feet|foot|')` + String.raw`(?:\s*(?:and\s+)?(\d{1,2}(?:\.\d{1,6})?)\s*(?:in\.?|inches|inch|")?)?`,
      value,
    );
    if (feet) {
      if (feet[2] === undefined || pyFloat(feet[2]) < 12) {
        result = pyFloat(feet[1]) * 30.48 + (feet[2] === undefined ? 0 : pyFloat(feet[2])) * 2.54;
      }
    } else if (cm !== null) result = cm;
    else if (meters !== null) result = meters * 100;
    else if (inches !== null) result = inches * 2.54;
  } else if (field === "weight_kg") {
    const kg = number(value, String.raw`\s*(?:kg|kilograms?|kilos?)`);
    const lb = number(value, String.raw`\s*(?:lb|lbs|pounds?)`);
    result = kg !== null ? kg : lb !== null ? lb * 0.45359237 : null;
  } else if (field === "sleep_hours") {
    result = number(value, String.raw`(?:\s*(?:hours?|hrs?|h)(?:\s*(?:per|a|each)\s*night)?)?`);
  } else if (field === "exercise_minutes_weekly") {
    result = number(value, String.raw`(?:\s*(?:minutes?|mins?)(?:\s*(?:per|a|each|/)\s*week)?)?`);
    const hours = number(value, String.raw`\s*(?:hours?|hrs?)(?:\s*(?:per|a|each|/)\s*week)`);
    if (hours !== null) result = hours * 60;
    // A bare small number is more likely days or hours than weekly minutes.
    if (fullmatch(NUMBER, value) && pyFloat(value) > 0 && pyFloat(value) < 15) result = null;
    const daily = fullmatch(
      NUMBER +
        String.raw`\s*(minutes?|mins?|hours?|hrs?)\s*(?:a|per|each)\s*day` +
        String.raw`\s*(?:and\s+)?(?:([1-7])\s*days?\s*(?:a|per|each)\s*week|(every day))`,
      value,
    );
    if (daily) {
      const perDay = pyFloat(daily[1]) * (daily[2].startsWith("m") ? 1 : 60);
      result = perDay * (daily[4] !== undefined ? 7 : Number(daily[3]));
    }
    if (["none", "i don't exercise", "i do not exercise"].includes(value)) result = 0;
  } else if (field === "alcohol_drinks_weekly") {
    result = number(value, String.raw`(?:\s*drinks?(?:\s*(?:per|a|each|/)\s*week)?)?`);
    if (["none", "i don't drink", "i do not drink"].includes(value)) result = 0;
  } else if (field === "systolic_bp" || field === "diastolic_bp") {
    const pair = fullmatch(BP_PAIR, value);
    if (pair) {
      const systolic = pyFloat(pair[1]);
      const diastolic = pyFloat(pair[2]);
      if (systolic <= diastolic) return {};
      return validatedValues({ systolic_bp: systolic, diastolic_bp: diastolic }) ?? {};
    }
    result = number(value, String.raw`(?:\s*mmhg)?`);
  } else if (field === "sex") {
    result = own(SEX_ANSWERS, value);
  } else if (field === "smoking_status") {
    result = own(SMOKING_ANSWERS, value);
    // "I quit smoking back in 1990", "I stopped smoking years ago": quitting is the answer.
    if (result === null && fullmatch(String.raw`i(?: have|'ve)? (?:quit|stopped|gave up)(?: smoking)?(?: .+)?|i used to smoke(?: .+)?`, value)) {
      result = "former";
    }
  } else if (field === "diabetes") {
    if (DIABETES_YES.has(value)) result = true;
    else if (DIABETES_NO.has(value)) result = false;
  }
  if (result === null) return {};
  if (INTEGER_FIELDS.has(field)) {
    if (!Number.isInteger(result as number)) return {};
  } else if (typeof result === "number") {
    result = pyRound(result, 4);
  }
  return validatedValues({ [field]: result }) ?? {};
}

/** Field-specific follow-up for an answer that is close but not safe to read. */
export function clarify(text: string, field: ProfileField): string | null {
  const value = phrase(field, text);
  const about = fullmatch(String.raw`(?:about|around|roughly|approximately|maybe)\s+(.+)`, value);
  const bare = fullmatch(NUMBER, about ? about[1] : value);
  const numberText = bare ? bare[1] : null;
  if (field === "weight_kg") {
    if (about) {
      return "Your best guess is fine. Please say just the number with pounds or " + 'kilograms, like "160 pounds".';
    }
    if (numberText) {
      return (
        `Is that ${numberText} pounds or ${numberText} kilograms? Please say the number ` +
        `with the unit, like "${numberText} pounds".`
      );
    }
  }
  if (field === "height_cm") {
    if (about) {
      return "Your best guess is fine. Please say just the number with the unit, " + 'like "5 feet 10 inches" or "178 cm".';
    }
    if (numberText) {
      return (
        "Is that inches or centimeters? Please say it with the unit, " + 'like "70 inches". You can also say "5 feet 10 inches".'
      );
    }
  }
  if (field === "systolic_bp" || field === "diastolic_bp") {
    const pair = fullmatch(BP_PAIR, value);
    if (pair && pyFloat(pair[1]) <= pyFloat(pair[2])) return BP_ORDER_MESSAGE;
  }
  if (field === "exercise_minutes_weekly") {
    if (py(String.raw`\b(?:a|per|each|every)\s+day\b`).test(value)) {
      return "How many days a week do you do that? You can say, for example, " + '"30 minutes a day, 5 days a week".';
    }
    if (numberText && !about && pyFloat(numberText) > 0 && pyFloat(numberText) < 15) {
      return (
        `Is that ${numberText} minutes or ${numberText} hours in the whole week? Please say it ` +
        `with minutes or hours, like "${numberText} hours a week".`
      );
    }
  }
  return null;
}

function conflicts(values: Profile, parsed: Profile): boolean {
  return Object.entries(parsed).some(([key, val]) => key in values && values[key as ProfileField] !== val);
}

/** Handle a short answer or several explicitly labeled clauses. */
export function parseReply(text: string, field: ProfileField): Profile {
  text = normalizeText(text);
  // One measurement may contain commas or "and" ("5 feet, 10 inches").
  const whole = parseValue(field, text);
  if (Object.keys(whole).length > 0) return whole;
  const parts = text.split(py(String.raw`[;,]|\s+and\s+`, "i"));
  const values: Profile = {};
  for (const part of parts) {
    if (!pyStrip(part)) continue;
    const label = fullmatch(String.raw`\s*([a-z_]+)\s*[:=]\s*(.+)\s*`, part, "i");
    let parsed: Profile;
    if (label) {
      const target = own(LABELS, label[1].toLowerCase());
      if (target === null) return {};
      parsed = parseValue(target, label[2]);
    } else if (parts.length === 1) {
      parsed = parseValue(field, part);
    } else {
      // Unlabeled leftovers may contradict a labeled measurement.
      return {};
    }
    if (Object.keys(parsed).length === 0) return {};
    // Contradictory repeated values require clarification of the whole turn.
    if (conflicts(values, parsed)) return {};
    Object.assign(values, parsed);
  }
  return values;
}

export interface ExtractionCandidate {
  field: ProfileField;
  quote: string;
}

function sameValues(a: Profile, b: Profile): boolean {
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((key) => key in b && a[key as ProfileField] === b[key as ProfileField]);
}

/**
 * Validate evidence boundaries AND the full context of every clause. A
 * provider-selected span cannot remove a negation, tense, uncertainty or a
 * contradictory second measurement, and a field other than the asked one
 * needs a clause that names it.
 */
export function groundedCandidates(text: string, candidates: ExtractionCandidate[], asked: ProfileField): Profile {
  text = normalizeText(text);
  const clauses = text
    .split(py(String.raw`[;,\n]|(?<!\d)[.!?]|[.!?](?!\d)|\s+and\s+`, "i"))
    .map((clause) => pyStrip(clause))
    .filter((clause) => clause.length > 0);
  const values: Profile = {};
  const covered = new Set<number>();
  for (const candidate of candidates) {
    const quote = normalizeText(candidate.quote);
    const quoteValues = parseValue(candidate.field, quote);
    if (Object.keys(quoteValues).length === 0) return {};
    const matching: number[] = [];
    const evidence = py(String.raw`(?<!\w)` + escapeRegExp(quote) + String.raw`(?!\w)`);
    for (const [index, clause] of clauses.entries()) {
      // Word boundaries stop "male" inside "female" and "70 kg" inside "170 kg".
      if (!evidence.test(clause)) continue;
      if (candidate.field !== asked && !py(FIELD_CUES[candidate.field], "i").test(clause)) return {};
      // These two modifiers assert present time; stripping other prose would
      // risk dropping negation, ambiguity, or historical context.
      const normalized = sub(String.raw`\b(?:current|currently)\s+`, "", clause, "i");
      if (!sameValues(parseReply(normalized, candidate.field), quoteValues)) return {};
      matching.push(index);
    }
    if (matching.length === 0) return {};
    if (conflicts(values, quoteValues)) return {};
    for (const index of matching) covered.add(index);
    Object.assign(values, quoteValues);
  }
  // Every complete clause must be accounted for.
  return covered.size === clauses.length ? values : {};
}

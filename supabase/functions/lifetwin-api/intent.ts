/**
 * One reader for every yes/no moment: consent, offers, read-backs and "anything else?".
 * A port of server/lifetwin/core/intent.py; the lexicon, questions, patterns and the
 * Claude prompt come from intent-data.json (scripts/export_edge_intent.py), so the two
 * cannot drift. readLocal runs first, and alone for the consent questions (memory,
 * outside AI, voice), which are never sent to a model. When the rules are not confident
 * and the person said yes to Claude, readIntent asks Claude and validates its JSON
 * strictly; any failure keeps the local reading. Tone only changes Mochi's wording: it
 * never turns a no into a yes.
 */
import data from "./intent-data.json" with { type: "json" };

export type IntentKind =
  | "yes"
  | "no"
  | "unsure"
  | "answer_other"
  | "correction"
  | "off_topic";
export type Tone = "eager" | "reluctant" | "joking" | "annoyed" | "neutral";
export type IntentResult = {
  intent: IntentKind;
  confidence: number;
  tone: Tone;
  corrected_value: string | null;
  source: "rules" | "claude";
};
export type Question = {
  kind: string;
  text: string;
  yes_means: string;
  no_means: string;
  echo: string[];
  extra: string[][];
  check: string;
};
/** Claude's JSON for (system, user, schema), or null; the caller checked consent. */
export type Complete = (
  system: string,
  user: string,
  schema: Record<string, unknown>,
) => Promise<unknown>;

export const YES_FLOOR = data.YES_FLOOR;
export const NO_FLOOR = data.NO_FLOOR;
export const INTENT_PROMPT = data.prompt;
export const INTENT_SCHEMA = data.schema as Record<string, unknown>;
export const LINES = data.lines;
const Q = data.questions as Record<string, Question>;
export const MEMORY = Q.memory, OUTSIDE_AI = Q.outside_ai, VOICE = Q.voice;
export const HEALTH_OFFER = Q.health_offer, MISSING = Q.missing;
export const ANYTHING_ELSE = Q.anything_else, ALSO_UPDATE = Q.also_update;
export const KEEP_GOING = Q.keep_going;
/** A read-back ("Age: 46. Is that right?"): a yes saves the answer read back. */
export const readBack = (text: string): Question => ({
  ...(data.read_back as Question),
  text,
});

const isConsent = (q: Question) =>
  ["memory", "outside_ai", "voice"].includes(q.kind);
/** A read-back saves a health answer: "okay" or "I guess" alone is not a yes. */
const isStrict = (q: Question) => q.kind === "read_back";

const result = (
  intent: IntentKind,
  confidence: number,
  extra: Partial<IntentResult> = {},
): IntentResult => ({
  intent,
  confidence,
  tone: "neutral",
  corrected_value: null,
  source: "rules",
  ...extra,
});
export const clearYes = (r: IntentResult) =>
  r.intent === "yes" && r.confidence >= YES_FLOOR;
export const clearNo = (r: IntentResult) =>
  r.intent === "no" && r.confidence >= NO_FLOOR;
export const confident = (r: IntentResult) =>
  r.confidence >= (r.intent === "no" ? NO_FLOOR : YES_FLOOR);

// -- The local reader --------------------------------------------------------------

type Hit = [number, string, number, string, boolean];
type Rule = [RegExp, string, number, string, boolean];
const word = (p: string) => new RegExp(`(?<![\\w'])${p}(?![\\w'])`, "g");
const LEXICON: Rule[] = (data.lexicon as [
  string,
  string,
  number,
  string,
  boolean,
][]).map(([p, pol, c, t, w]) => [word(p), pol, c, t, w]);
// "never" answers a smoking read-back; it is not a no to it.
const NEVER = word("never(?: ever)?").source;
const P = data.patterns;
const FILLERS = new RegExp(P.fillers, "g");
const JOKING = new RegExp(P.joking);
const ANNOYED = new RegExp(P.annoyed);
const EAGER = new RegExp(P.eager);
const SELF_CORRECTION = new RegExp(P.self_correction);
const CONTRAST = new RegExp(P.contrast);

const words = (s: string) => s.split(/\s+/).filter(Boolean);
const squash = (s: string) => words(s).join(" ");
/** Python's str.strip(chars). */
const strip = (s: string, chars: string) => {
  let a = 0, b = s.length;
  while (a < b && chars.includes(s[a])) a++;
  while (b > a && chars.includes(s[b - 1])) b--;
  return s.slice(a, b);
};

export function normalize(text: string): string {
  let s = text.toLowerCase().replace(/[’‘`]/g, "'");
  s = s.replace(
    /\b(don|doesn|didn|won|can|isn|wasn|wouldn|couldn|shouldn|haven)t\b/g,
    "$1't",
  );
  s = s.replace(/\b(that|it|let|there|what)s\b/g, "$1's");
  s = s.replace(/\bim\b/g, "i'm").replace(/\bive\b/g, "i've");
  s = s.replace(/\bid\b(?= (?:rather|prefer|like|love|say))/g, "i'd");
  s = s.replace(/\b(uh|mm|um)-(huh|hmm|hm|uh)\b/g, "$1 $2");
  s = s.replace(/\bok(?:ay)?-(?=\w)/g, "okay ");
  s = s.replace(/[^\w'?!\s]/g, " ");
  s = s.replace(/\b(\w+)(?: \1\b){2,}/g, "$1 $1"); // "yes yes yes yes" -> "yes yes"
  return squash(s);
}

function stripEcho(s: string, q: Question): string {
  for (const echo of q.echo) {
    // The "?" goes with the echo only when an answer follows it.
    s = s.replace(
      new RegExp(`(?<![\\w'])${echo}(?![\\w'])(?:\\s*\\?(?=\\s*\\w))?`, "g"),
      " ",
    );
  }
  return squash(s);
}

/** Each [position, polarity, confidence, tone, weak] found, and the words left over. */
function hits(s: string, q: Question): [Hit[], string] {
  const found: Hit[] = [];
  let rest = s;
  const extra: Rule[] = q.extra.map((
    [p, pol],
  ) => [word(p), pol, 0.95, "neutral", false]);
  for (const [pattern, polarity, conf, tone, weak] of [...extra, ...LEXICON]) {
    if (isStrict(q) && polarity === "no" && pattern.source === NEVER) continue;
    for (const match of [...rest.matchAll(pattern)]) {
      if (!match[0].trim()) continue;
      const start = match.index!, end = start + match[0].length;
      found.push([start, polarity, conf, tone, weak]);
      rest = rest.slice(0, start) + " ".repeat(end - start) + rest.slice(end);
    }
  }
  found.sort((a, b) => {
    for (let i = 0; i < a.length; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return 0;
  });
  return [found, squash(rest.replaceAll("?", " ").replaceAll("!", " "))];
}

function toneOf(s: string, base: string): Tone {
  if (ANNOYED.test(s)) return "annoyed";
  if (JOKING.test(s)) return "joking";
  if (base !== "neutral") return base as Tone;
  return EAGER.test(s) ? "eager" : "neutral";
}

const polarities = (found: Hit[]) => new Set(found.map((h) => h[1]));
const leftOver = (rest: string) => words(rest.replace(FILLERS, " "));
/** The first hit with the highest confidence (Python's max). */
const strongest = (found: Hit[]) =>
  found.reduce((best, h) => h[2] > best[2] ? h : best);
const round2 = (x: number) => Number(x.toFixed(2));

/** The rules' reading of a reply to ``q`` (never a network call). */
export function readLocal(
  text: string | null | undefined,
  q: Question,
): IntentResult {
  const raw = normalize(text ?? "");
  // Silence is never consent.
  if (!strip(raw, " ?!")) return result("off_topic", 1);
  let s = stripEcho(raw, q);
  if (["please", "please please"].includes(strip(s, " !"))) {
    return result("yes", 0.9);
  }
  if (!strip(s, " ?!")) {
    // Only the question's own words: "remember the little things?"
    return result("unsure", raw.includes("?") ? 0.9 : 0.6);
  }
  // "Yes, actually no": what follows the last self-correction is what they meant.
  const parts = s.split(SELF_CORRECTION).filter((p) => strip(p, " ,.!?"));
  const corrected = parts.length > 1;
  if (corrected) {
    const last = polarities(hits(parts[parts.length - 1], q)[0]);
    if (last.has("yes") || last.has("no")) s = parts[parts.length - 1];
  }
  // "Yes but my weight is 80 now" / "no, it's 5'11": the lead word, then an answer.
  let leadValue: string | null = null;
  const contrast = CONTRAST.exec(s);
  if (contrast) {
    const head = s.slice(0, contrast.index);
    const tail = s.slice(contrast.index + contrast[0].length);
    const [headHits, headRest] = hits(head, q);
    const headPol = polarities(headHits);
    const tailPol = polarities(hits(tail, q)[0]);
    if (
      headPol.size === 1 && (headPol.has("yes") || headPol.has("no")) &&
      !leftOver(headRest).length &&
      /\d|\b(?:now|it's|is|was|am|i'm|weigh|tall|sleep)\b/.test(tail) &&
      ![...tailPol].some((p) => !headPol.has(p) && p !== "unsure")
    ) {
      leadValue = tail.trim();
      s = head;
    }
  } else {
    const noLead = /^(?:no|nope|nah|not quite|wrong)\b[\s,.!-]*(?<rest>.*\d.*)$/
      .exec(s);
    if (noLead) {
      leadValue = noLead.groups!.rest.trim();
      s = "no";
    }
  }
  const [found, rest] = hits(s, q);
  const leftover = leftOver(rest);
  const pols = polarities(found);
  const asked = s.includes("?");

  if (leadValue !== null) {
    const polarity = pols.size === 1 ? [...pols][0] : "unsure";
    if (polarity === "no" && q.kind === "read_back") {
      return result("correction", 0.85, {
        tone: toneOf(raw, "neutral"),
        corrected_value: leadValue.slice(0, 300),
      });
    }
    if (polarity === "yes" || polarity === "no") {
      const best = strongest(found.filter((h) => h[1] === polarity));
      return result(polarity, 0.85, {
        tone: toneOf(raw, best[3]),
        corrected_value: leadValue.slice(0, 300),
      });
    }
  }
  if (!found.length) {
    if (/\d/.test(s)) {
      return result(
        q.kind === "read_back" ? "correction" : "answer_other",
        0.6,
        { corrected_value: (text ?? "").trim().slice(0, 300) },
      );
    }
    if (asked) return result("unsure", 0.85);
    return result("off_topic", 0.5);
  }
  const decided = [...pols].filter((p) => p !== "unsure");
  if (!decided.length) {
    return result("unsure", 0.9, { tone: toneOf(raw, "neutral") });
  }
  if (decided.length > 1) {
    // "Yeah no" means no; "no yeah" leans yes (asked again if it matters).
    const sided = found.filter((h) => h[1] !== "unsure");
    if (
      found.length === 2 && sided[0][1] === "yes" && sided[1][1] === "no" &&
      ["yeah", "yes", "yea"].includes(words(s)[0])
    ) return result("no", 0.75, { tone: toneOf(raw, "neutral") });
    if (corrected) {
      const last = sided[sided.length - 1];
      return result(last[1] as IntentKind, 0.75, {
        tone: toneOf(raw, last[3]),
      });
    }
    return result("unsure", 0.3, { tone: toneOf(raw, "neutral") });
  }
  const polarity = decided[0] as IntentKind;
  const chosen = found.filter((h) => h[1] === polarity);
  const best = strongest(chosen);
  let confidence = best[2];
  if (pols.has("unsure")) {
    // "Sure, but what does it mean?": a doubt beside the yes.
    confidence = Math.min(confidence, polarity === "yes" ? 0.55 : 0.7);
  }
  if (asked && polarity === "yes" && !corrected) {
    confidence = Math.min(confidence, 0.6); // "okay?" or "you can?" is a question back
  }
  if (leftover.length) confidence -= leftover.length <= 3 ? 0.1 : 0.3;
  if (corrected) confidence = Math.min(confidence, 0.85);
  if (isStrict(q) && polarity === "yes" && chosen.every((h) => h[4])) {
    confidence = Math.min(confidence, 0.6); // "okay" alone does not save a read-back
  }
  return result(polarity, round2(Math.max(confidence, 0.05)), {
    tone: toneOf(raw, best[3]),
  });
}

// -- Claude ---------------------------------------------------------------------------

const KINDS = new Set(
  ["yes", "no", "unsure", "answer_other", "correction", "off_topic"],
);
const TONES = new Set(["eager", "reluctant", "joking", "annoyed", "neutral"]);
const KEYS = ["confidence", "corrected_value", "intent", "tone"];

/** Strict: the four keys only, known values, and a corrected value from the reply. */
export function validate(content: unknown, text: string): IntentResult | null {
  let parsed = content;
  if (typeof content === "string") {
    try {
      parsed = JSON.parse(content);
    } catch {
      return null;
    }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const d = parsed as Record<string, unknown>;
  if (Object.keys(d).sort().join() !== KEYS.join()) return null;
  const { intent, confidence, tone } = d;
  let value = d.corrected_value;
  if (
    typeof confidence !== "number" || !Number.isFinite(confidence) ||
    confidence < 0 || confidence > 1 ||
    typeof intent !== "string" || !KINDS.has(intent) ||
    typeof tone !== "string" || !TONES.has(tone) ||
    !(value === null ||
      typeof value === "string" && [...value].length <= 300)
  ) return null;
  if (
    typeof value === "string" && !normalize(text).includes(normalize(value))
  ) {
    // A value not in the person's words is never used.
    if (intent === "correction") return null;
    value = null;
  }
  if (intent === "correction" && !d.corrected_value) return null;
  return {
    intent: intent as IntentKind,
    confidence,
    tone: tone as Tone,
    corrected_value: value as string | null,
    source: "claude",
  };
}

/** Claude's validated reading within ``ms``, or null (any failure keeps the rules'). */
export async function claudeRead(
  complete: Complete,
  text: string,
  q: Question,
  ms = 4000,
): Promise<IntentResult | null> {
  // Consent questions are asked before Claude may hear anything: never sent.
  if (isConsent(q)) return null;
  const user = JSON.stringify({
    question: q.text,
    a_yes_means: q.yes_means,
    a_no_means: q.no_means,
    reply: text,
  });
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const content = await Promise.race([
      complete(INTENT_PROMPT, user, INTENT_SCHEMA),
      new Promise<null>((done) => timer = setTimeout(() => done(null), ms)),
    ]);
    return content == null ? null : validate(content, text);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Rules first; Claude only when they are not confident, never for consent questions.
 * ``askClaude``: the caller saw words the rules left unexplained.
 */
export async function readIntent(
  text: string | null | undefined,
  q: Question,
  complete: Complete | null = null,
  { allowed = false, askClaude = false } = {},
): Promise<IntentResult> {
  const local = readLocal(text, q);
  if (
    (confident(local) && !askClaude) || isConsent(q) || !allowed ||
    !complete || local.intent === "off_topic" && !(text ?? "").trim()
  ) return local;
  const claude = await claudeRead(complete, text ?? "", q);
  if (!claude) return local;
  if (local.intent === "no" && claude.intent === "yes") {
    // The rules heard a no: Claude never turns it into a yes.
    return result("unsure", 0.4, { tone: claude.tone, source: "claude" });
  }
  return claude;
}

// -- Wording --------------------------------------------------------------------------

/** Mochi's answer to a yes or a no, fitted to how it was said (never the intent). */
export function ack(r: IntentResult, yesLine: string, noLine: string): string {
  if (r.intent === "yes") {
    return ({
      reluctant: "No problem, you can change this anytime.",
      eager: "Love it, thank you!",
      joking: "Ha, thank you!",
      annoyed: "Got it, thank you.",
    } as Record<string, string>)[r.tone] ?? yesLine;
  }
  return r.tone === "annoyed" ? "Of course. " + noLine : noLine;
}

/** Every word of the reply is a yes/no word or filler: nothing else was said. */
export function explained(text: string | null | undefined, q: Question) {
  const [found, rest] = hits(stripEcho(normalize(text ?? ""), q), q);
  return found.length > 0 && !leftOver(rest).length;
}

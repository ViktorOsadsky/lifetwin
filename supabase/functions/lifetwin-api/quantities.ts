/**
 * Spoken amounts in the asked field's unit. Mirrors server/lifetwin/core/quantities.py
 * (owner ruling 2026-10-25: "the voice agents need to be able to do math"): "2 hours" to
 * a minutes question is 120, "30 minutes three times a week" is 90 a week, "5 foot 10" is
 * 177.8 cm. It never guesses: a weight said to a sleep question, a weekly amount said to
 * a nightly question, a range or a vague amount reads as nothing.
 */
export type Status =
  | "ok"
  | "none"
  | "wrong_unit"
  | "other_topic"
  | "period"
  | "ambiguous"
  | "range";
export interface Reading {
  value: number | null;
  status: Status;
}

const FIELDS: Record<string, [string, string]> = {
  sleep_hours: ["hours", "night"],
  sleep_hours_last_night: ["hours", "once"],
  sleep_hours_night_before: ["hours", "once"],
  exercise_minutes_weekly: ["minutes", "week"],
  moderate_recreation_min_week: ["minutes", "week"],
  vigorous_recreation_min_week: ["minutes", "week"],
  sedentary_min_day: ["minutes", "day"],
  exercise_minutes_today: ["minutes", "once"],
  moderate_recreation_min: ["minutes", "once"],
  vigorous_recreation_min: ["minutes", "once"],
  height_cm: ["height", "once"],
  weight_kg: ["weight", "once"],
};
const MINUTE_LIMITS: Record<string, number> = {
  week: 10080,
  day: 1439,
  once: 1440,
  night: 1440,
};
const LB_PER_KG = 0.45359237;
const ONES: Record<string, number> = {
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
const TENS: Record<string, number> = {
  twenty: 20,
  thirty: 30,
  forty: 40,
  fifty: 50,
  sixty: 60,
  seventy: 70,
  eighty: 80,
  ninety: 90,
};
const ONE = Object.keys(ONES).join("|");
const TEN = Object.keys(TENS).join("|");
const SIMPLE = `(?:(${TEN})(?:[\\s-](${ONE}))?|(${ONE}))`;
const WORD_NUMBER = new RegExp(
  `\\b(a|one|two|three)\\s+hundred(?:\\s+and)?\\s+${SIMPLE}\\b|\\b(a|one|two|three)\\s+hundred\\b|\\b${SIMPLE}\\b`,
  "g",
);
const HOURS = "(?:hours?|hrs?|h)";
const MINUTES = "(?:minutes?|mins?)";
const NUMBER = "\\d+(?:\\.\\d+)?";
const DURATION = new RegExp(
  `(${NUMBER})\\s*-?\\s*(${HOURS}|${MINUTES})\\b(?:\\s*(?:and\\s+)?(${NUMBER})\\s*${MINUTES}\\b)?`,
  "g",
);
const FEET = new RegExp(
  `([3-8])\\s*(?:feet|foot|ft|')\\s*(?:(?:and\\s+)?(${NUMBER})\\s*(?:inches|inch|in|"|'')?)?(?![\\d.])`,
);
const INCHES = new RegExp(`(${NUMBER})\\s*(?:inches|inch|in|")(?!\\w)`);
const CM = new RegExp(`(${NUMBER})\\s*(?:cm|centimet(?:er|re)s?)\\b`);
const METRES = /([12](?:\.\d{1,2})?)\s*(?:m|met(?:er|re)s?)\b/;
const POUNDS = new RegExp(`(${NUMBER})\\s*(?:lbs?|pounds?)\\b`);
const KILOS = new RegExp(`(${NUMBER})\\s*(?:kgs?|kilos?|kilograms?)\\b`);
const STONE = new RegExp(
  `(${NUMBER})\\s*(?:stone|st)\\b(?:\\s*(?:and\\s+)?(${NUMBER})\\s*(?:lbs?|pounds?)?)?`,
);
const TIMES =
  /\b(?:(\d+)\s+(?:times|days|sessions|mornings|evenings|nights)|(once|twice))\s+(?:a|per|each|every|in\s+a|this)\s+week\b|\b(\d)\s+days?\b/;
const DAILY =
  /\b(?:a|per|each|every)\s+day\b|\bdaily\b|\bevery\s+(?:morning|evening)\b/;
const WEEKLY = /\b(?:a|per|each|every|in\s+a)\s+week\b|\bweekly\b/;
const NIGHTLY = /\b(?:a|per|each|every)\s+night\b|\bnightly\b/;
const RANGE = new RegExp(`${NUMBER}\\s*(?:-|to|or)\\s*${NUMBER}`);
const SLEEP_WORDS = /\b(?:sleep\w*|slept|asleep|in bed|naps?)\b/;
const AWAKE_WORDS =
  /\b(?:walk\w*|exercis\w*|gym|run\w*|jog\w*|swim\w*|bik\w*|cycl\w*|workout|sit|sitting|sat|desk)\b/;
const VAGUE = /\b(?:a few|several|some|a lot|lots|many|a bit)\b/;
const NONE: Reading = { value: null, status: "none" };
const no = (status: Status): Reading => ({ value: null, status });

function hundreds(word: string): number {
  return 100 * (word === "a" || word === "one" ? 1 : ONES[word]);
}

/** Lower case, number words as digits and spoken fractions as decimals. */
export function spokenNumbers(text: string): string {
  let s = text.toLowerCase().replace(/’/g, "'").replace(/”/g, '"')
    .replace(/½/g, ".5");
  s = s.replace(/(?<=\d),(?=\d{3}\b)/g, "").replace(/[!?,;:()]/g, " ")
    .replace(/\.(?!\d)/g, " ");
  s = s.replace(/\ba couple(?: of)?\b/g, "2")
    .replace(/\b(?:an?|one)\s+hour\s+and\s+a\s+half\b/g, "1.5 hours")
    .replace(/\b(?:an?|one)\s+hour\s+and\s+a\s+quarter\b/g, "1.25 hours")
    .replace(/\bthree\s+quarters\s+of\s+an?\s+hour\b/g, "45 minutes")
    .replace(
      /\b(?:a\s+)?quarter\s+(?:of\s+)?an?\s+hour\b|\ba\s+quarter\s+hour\b/g,
      "15 minutes",
    )
    .replace(/\bhalf\s+(?:an?\s+)?hour\b/g, "30 minutes")
    .replace(/\b(?:an?|one)\s+hour\b/g, "1 hour")
    .replace(/\b(?:a\s+)?half\s+(?:a\s+)?(pound|kilo|foot|inch)\b/g, "0.5 $1");
  s = s.replace(
    WORD_NUMBER,
    (_m, h, t, to, o, bare, t2, to2, o2) => {
      if (bare) return String(hundreds(bare));
      let total = h ? hundreds(h) : 0;
      const tens = h ? t : t2, ones = h ? to : to2, only = h ? o : o2;
      total += tens ? TENS[tens] + (ONES[ones] ?? 0) : ONES[only];
      return String(total);
    },
  );
  s = s.replace(/(\d+)\s+and\s+a\s+half\b/g, "$1.5")
    .replace(/(\d+)\s+and\s+a\s+quarter\b/g, "$1.25")
    .replace(/(\d+)\s+and\s+three\s+quarters\b/g, "$1.75")
    .replace(
      /(\d+)\s*(?:and\s+)?(\d+)\s*\/\s*(\d+)\b/g,
      (m, w, top, bottom) =>
        +bottom && +top < +bottom ? String(+w + +top / +bottom) : m,
    )
    .replace(/(\d)\s+point\s+(\d+)/g, "$1.$2");
  return s.split(/\s+/).filter(Boolean).join(" ");
}

function minutesSaid(text: string): [number, number, number][] | null {
  const found: [number, number, number][] = [];
  for (const m of text.matchAll(DURATION)) {
    const hours = new RegExp(`^${HOURS}$`).test(m[2]);
    let minutes = +m[1] * (hours ? 60 : 1);
    if (m[3]) {
      if (!hours) return null;
      minutes += +m[3];
    }
    found.push([minutes, m.index!, m.index! + m[0].length]);
  }
  return found;
}

function frequency(rest: string, weekly: boolean): [string, number] {
  const times = rest.match(TIMES);
  if (times) {
    if (times[2]) return ["week", times[2] === "once" ? 1 : 2];
    return ["week", +(times[1] ?? times[3])];
  }
  if (DAILY.test(rest)) return ["day", 7];
  if (WEEKLY.test(rest)) return ["week", 1];
  if (NIGHTLY.test(rest)) return ["night", 7];
  // "on Mondays and again on Thursdays": one session on each day named (weekly only).
  const days = new Set(
    [...rest.matchAll(/\b(mon|tues|wednes|thurs|fri|satur|sun)days?\b/g)].map((
      m,
    ) => m[1]),
  );
  if (days.size && weekly) return ["week", days.size];
  return ["none", 1];
}

function duration(text: string, field: string): Reading {
  const [unit, period] = FIELDS[field];
  let amounts = minutesSaid(text);
  if (amounts === null) return no("ambiguous");
  if (!amounts.length) {
    if (
      POUNDS.test(text) || KILOS.test(text) || FEET.test(text) ||
      CM.test(text) || METRES.test(text)
    ) return no("wrong_unit");
    const numbers = text.match(new RegExp(NUMBER, "g")) ?? [];
    if (
      numbers.length !== 1 ||
      /\b(?:times|days|drinks?|steps|miles?|km)\b/.test(text)
    ) return NONE;
    const n = +numbers[0];
    if (unit === "minutes" && n < 10) return no("ambiguous");
    amounts = [[unit === "hours" ? n * 60 : n, 0, 0]];
  }
  let rest = text;
  for (const [, start, end] of [...amounts].reverse()) {
    rest = rest.slice(0, start) + " " + rest.slice(end);
  }
  const [said, sessions] = frequency(rest, period === "week");
  let minutes: number;
  if (amounts.length > 1) {
    if (
      period !== "week" || !["none", "week"].includes(said) ||
      ![1, amounts.length].includes(sessions)
    ) return no("ambiguous");
    minutes = amounts.reduce((sum, [a]) => sum + a, 0);
  } else {
    minutes = amounts[0][0];
    if (period === "week") minutes *= sessions;
    else if (said === "week") return no("period");
    else if (said === "day" && unit === "hours") {
      // "8 hours a day" of sleep
    } else if (said !== "none" && period === "once" && unit === "minutes") {
      return no("period");
    }
  }
  let value: number, low: number, high: number;
  if (unit === "hours") {
    value = Math.round(minutes / 60 * 100) / 100;
    // A usual night is 2 to 16 hours ("90 minutes" is no night); one night may be shorter.
    [low, high] = period === "night" ? [2, 16] : [1, 20];
  } else {
    value = Math.round(minutes);
    [low, high] = [0, MINUTE_LIMITS[period]];
  }
  return value >= low && value <= high ? { value, status: "ok" } : no("range");
}

function height(text: string): Reading {
  if (minutesSaid(text)?.length || POUNDS.test(text) || KILOS.test(text)) {
    return no("wrong_unit");
  }
  let value: number;
  const feet = text.match(FEET),
    cm = text.match(CM),
    metres = text.match(METRES),
    inches = text.match(INCHES);
  const said = feet ?? cm ?? metres ?? inches;
  if (
    said &&
    /\d/.test(
      text.slice(0, said.index) + " " +
        text.slice((said.index ?? 0) + said[0].length),
    )
  ) {
    // "5 foot 4, well, probably 5 3 and a half": a second height. The reader never
    // picks one of the two.
    return no("ambiguous");
  }
  if (feet) {
    const extra = +(feet[2] ?? 0);
    if (extra >= 12) return no("ambiguous");
    value = (+feet[1] * 12 + extra) * 2.54;
  } else if (cm) value = +cm[1];
  else if (metres) value = +metres[1] * 100;
  else if (inches) value = +inches[1] * 2.54;
  else {
    const numbers = text.match(new RegExp(NUMBER, "g")) ?? [];
    if (numbers.length === 2 && /^[4-7]\s+\d{1,2}$/.test(text.trim())) {
      if (+numbers[1] >= 12) return no("ambiguous");
      value = (+numbers[0] * 12 + +numbers[1]) * 2.54; // "five ten"
    } else if (
      numbers.length === 1 && +numbers[0] >= 120 && +numbers[0] <= 230
    ) {
      value = +numbers[0];
    } else return NONE;
  }
  value = Math.round(value * 10) / 10;
  return value >= 50 && value <= 280 ? { value, status: "ok" } : no("range");
}

function weight(text: string): Reading {
  if (minutesSaid(text)?.length || FEET.test(text) || CM.test(text)) {
    return no("wrong_unit");
  }
  let value: number;
  const stone = text.match(STONE),
    pounds = text.match(POUNDS),
    kilos = text.match(KILOS);
  if (stone) value = (+stone[1] * 14 + +(stone[2] ?? 0)) * LB_PER_KG;
  else if (pounds) value = +pounds[1] * LB_PER_KG;
  else if (kilos) value = +kilos[1];
  else return /\d/.test(text) ? no("ambiguous") : NONE;
  value = Math.round(value * 100) / 100;
  return value >= 10 && value <= 700 ? { value, status: "ok" } : no("range");
}

/** The amount `text` states, in `field`'s unit, or why it states none. */
export function readQuantity(text: string, field: string): Reading {
  if (!(field in FIELDS) || !text || text.length > 500) return NONE;
  const s = spokenNumbers(text);
  if (RANGE.test(s) || /(?:^|\s)-\d/.test(s)) return no("ambiguous");
  if (VAGUE.test(s) && !/\d/.test(s)) return NONE;
  const unit = FIELDS[field][0];
  // "7 and a half hours of sleep" to the exercise question answers another question.
  const sleepField = unit === "hours";
  if (
    (SLEEP_WORDS.test(s) && !sleepField) || (AWAKE_WORDS.test(s) && sleepField)
  ) return no("other_topic");
  if (unit === "height") return height(s);
  if (unit === "weight") return weight(s);
  if (sleepField && (POUNDS.test(s) || KILOS.test(s) || FEET.test(s))) {
    return no("wrong_unit");
  }
  return duration(s, field);
}

export const quantityFields = new Set(Object.keys(FIELDS));

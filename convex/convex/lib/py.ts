// Python-compatible primitives. The FastAPI backend is the reference
// implementation, so text handling, rounding and JSON output follow CPython
// semantics exactly instead of JavaScript's defaults.

// Characters for which Python's str.isspace() is true (also Python's \s).
export const WS = "[\\t\\n\\x0b\\x0c\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]";
// Python's Unicode \w and \d.
export const W = "[\\p{L}\\p{N}_]";
export const D = "\\p{Nd}";
// Python's \b for Unicode patterns.
export const B = `(?:(?<=${W})(?!${W})|(?<!${W})(?=${W}))`;

const WS_RUN = new RegExp(`${WS}+`, "u");
const WS_EDGE = new RegExp(`^${WS}+|${WS}+$`, "gu");

/** str.split() with no arguments. */
export function pySplit(value: string): string[] {
  return value.split(WS_RUN).filter((part) => part.length > 0);
}

/** str.strip() with no arguments. */
export function pyStrip(value: string): string {
  return value.replace(WS_EDGE, "");
}

/** str.rstrip(chars). */
export function rstripChars(value: string, chars: string): string {
  let end = value.length;
  while (end > 0 && chars.includes(value[end - 1])) end -= 1;
  return value.slice(0, end);
}

/** Python's re.escape for use inside a JavaScript regular expression. */
export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
}

/** len(str): code points, not UTF-16 units. */
export function pyLen(value: string): number {
  let count = 0;
  for (const _ of value) count += 1;
  return count;
}

const ND = /\p{Nd}/u;

/** Map any Unicode decimal digit to ASCII, as int()/float() accept them. */
export function asciiDigits(value: string): string {
  let out = "";
  for (const char of value) {
    if (char >= "0" && char <= "9") {
      out += char;
      continue;
    }
    if (!ND.test(char)) {
      out += char;
      continue;
    }
    // Every Nd run is a complete, contiguous 0-9 sequence (or several).
    const code = char.codePointAt(0)!;
    let start = code;
    while (start > 0 && ND.test(String.fromCodePoint(start - 1))) start -= 1;
    out += String((code - start) % 10);
  }
  return out;
}

/** float(text) for a string already matched by a digits[.digits] pattern. */
export function pyFloat(value: string): number {
  return Number(asciiDigits(value));
}

/** Exact decimal expansion of a finite double. */
function exactDecimal(value: number): { negative: boolean; int: string; frac: string } {
  const negative = value < 0 || Object.is(value, -0);
  const text = Math.abs(value).toFixed(100);
  const [int, frac = ""] = text.split(".");
  return { negative, int, frac };
}

/**
 * Correctly rounded decimal string with round-half-even on the exact binary
 * value: Python's format(value, f".{digits}f") and round(value, digits).
 */
export function pyFixed(value: number, digits: number): string {
  if (!Number.isFinite(value)) throw new Error("non-finite");
  const { negative, int, frac } = exactDecimal(value);
  const kept = int + frac.slice(0, digits).padEnd(digits, "0");
  const rest = frac.slice(digits);
  let roundUp = false;
  if (rest.length > 0) {
    const first = rest.charCodeAt(0) - 48;
    const tail = /[1-9]/.test(rest.slice(1));
    if (first > 5 || (first === 5 && tail)) roundUp = true;
    else if (first === 5 && !tail) roundUp = (kept.charCodeAt(kept.length - 1) - 48) % 2 === 1;
  }
  let digitsOut = kept;
  if (roundUp) {
    const chars = kept.split("");
    let index = chars.length - 1;
    while (index >= 0) {
      if (chars[index] === "9") {
        chars[index] = "0";
        index -= 1;
      } else {
        chars[index] = String.fromCharCode(chars[index].charCodeAt(0) + 1);
        break;
      }
    }
    digitsOut = (index < 0 ? "1" : "") + chars.join("");
  }
  const intLength = digitsOut.length - digits;
  let intPart = digitsOut.slice(0, intLength).replace(/^0+(?=\d)/, "");
  if (intPart === "") intPart = "0";
  const fracPart = digitsOut.slice(intLength);
  const body = digits > 0 ? `${intPart}.${fracPart}` : intPart;
  // Python keeps the sign of negative values that round to zero ("-0.00").
  return negative ? `-${body}` : body;
}

/** round(value, digits) for floats. */
export function pyRound(value: number, digits: number): number {
  return Number(pyFixed(value, digits));
}

/** round(value) -> int. */
export function pyRoundInt(value: number): number {
  return Number(pyFixed(value, 0));
}

/** repr(float): shortest round-trip digits in Python's layout. */
export function pyFloatRepr(value: number): string {
  if (Number.isNaN(value)) return "NaN";
  if (value === Infinity) return "Infinity";
  if (value === -Infinity) return "-Infinity";
  if (value === 0) return Object.is(value, -0) ? "-0.0" : "0.0";
  const [mantissa, exponentText] = value.toExponential().split("e");
  const exponent = Number(exponentText);
  const negative = mantissa.startsWith("-");
  const digits = mantissa.replace("-", "").replace(".", "");
  let out: string;
  if (exponent < -4 || exponent >= 16) {
    const lead = digits[0];
    const rest = digits.slice(1);
    const sign = exponent < 0 ? "-" : "+";
    out = `${lead}${rest ? "." + rest : ""}e${sign}${String(Math.abs(exponent)).padStart(2, "0")}`;
  } else if (exponent < 0) {
    out = `0.${"0".repeat(-exponent - 1)}${digits}`;
  } else if (digits.length <= exponent + 1) {
    out = `${digits}${"0".repeat(exponent + 1 - digits.length)}.0`;
  } else {
    out = `${digits.slice(0, exponent + 1)}.${digits.slice(exponent + 1)}`;
  }
  return negative ? `-${out}` : out;
}

// Response fields whose Pydantic type is float; FastAPI prints them as 175.0.
const FLOAT_KEYS = new Set(["height_cm", "weight_kg", "sleep_hours", "alcohol_drinks_weekly", "speed"]);

/**
 * json.dumps(value, ensure_ascii=False, separators=(",", ":")) with Python
 * float formatting for float-typed fields: the exact bytes Starlette sends.
 */
export function pyJson(value: unknown, key?: string): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (key !== undefined && FLOAT_KEYS.has(key)) return pyFloatRepr(value);
    return Number.isInteger(value) ? String(value) : pyFloatRepr(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map((item) => pyJson(item)).join(",")}]`;
  const entries = Object.entries(value as Record<string, unknown>).filter(([, item]) => item !== undefined);
  return `{${entries.map(([name, item]) => `${JSON.stringify(name)}:${pyJson(item, name)}`).join(",")}}`;
}

/** Python truthiness for JSON values. */
export function pyTruthy(value: unknown): boolean {
  if (value === null || value === undefined || value === false || value === 0 || value === "") return false;
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "object") return Object.keys(value as object).length > 0;
  return true;
}

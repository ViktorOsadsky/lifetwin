// json.loads() as Starlette's Request.json() applies it: accepts NaN and
// Infinity like CPython, rejects trailing data, keeps the last duplicate key.

export class JsonDecodeError extends Error {}
export class BodyDecodeError extends Error {}

/** Nesting deep enough that CPython's json raises RecursionError (HTTP 400 in FastAPI). */
export class JsonDepthError extends Error {}
// Measured against the reference app under TestClient: 971 nested arrays
// parse, 972 raise. The exact CPython limit depends on its stack depth.
const MAX_DEPTH = 971;

const BOM = String.fromCharCode(0xfeff);

function utf32(bytes: Uint8Array, littleEndian: boolean): string {
  if (bytes.length % 4 !== 0) throw new BodyDecodeError("undecodable body");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let out = "";
  for (let offset = 0; offset < bytes.length; offset += 4) {
    const code = view.getUint32(offset, littleEndian);
    if (code > 0x10ffff) throw new BodyDecodeError("undecodable body");
    out += String.fromCodePoint(code);
  }
  return out;
}

const decode = (encoding: string, bytes: Uint8Array) =>
  new TextDecoder(encoding, { fatal: true, ignoreBOM: true }).decode(bytes);

/** json.detect_encoding + bytes.decode: UTF-8 (BOM optional), UTF-16 and UTF-32. */
export function decodeBody(bytes: Uint8Array): string {
  const b = bytes;
  const starts = (...prefix: number[]) => prefix.every((value, index) => b[index] === value);
  try {
    if (starts(0x00, 0x00, 0xfe, 0xff)) return utf32(b.subarray(4), false);
    if (starts(0xff, 0xfe, 0x00, 0x00)) return utf32(b.subarray(4), true);
    if (starts(0xfe, 0xff)) return decode("utf-16be", b.subarray(2));
    if (starts(0xff, 0xfe)) return decode("utf-16le", b.subarray(2));
    let encoding = "utf-8";
    if (b.length >= 4) {
      if (!b[0]) encoding = b[1] ? "utf-16be" : "utf-32be";
      else if (!b[1]) encoding = b[2] || b[3] ? "utf-16le" : "utf-32le";
    } else if (b.length === 2) {
      if (!b[0]) encoding = "utf-16be";
      else if (!b[1]) encoding = "utf-16le";
    }
    if (encoding === "utf-32be") return utf32(b, false);
    if (encoding === "utf-32le") return utf32(b, true);
    const text = decode(encoding, b);
    // utf-8-sig drops a leading BOM; plain UTF-16/32 keep it (json.loads then rejects it).
    return encoding === "utf-8" && text.startsWith(BOM) ? text.slice(1) : text;
  } catch (error) {
    if (error instanceof BodyDecodeError) throw error;
    throw new BodyDecodeError("undecodable body");
  }
}

export function pyJsonLoads(text: string): unknown {
  let index = 0;
  const fail = (): never => {
    throw new JsonDecodeError("invalid JSON");
  };
  const skip = () => {
    while (index < text.length && " \t\n\r".includes(text[index])) index += 1;
  };
  const literal = (word: string, value: unknown) => {
    if (text.startsWith(word, index)) {
      index += word.length;
      return value;
    }
    return fail();
  };
  const string = (): string => {
    index += 1;
    let out = "";
    while (true) {
      if (index >= text.length) fail();
      const char = text[index];
      if (char === '"') {
        index += 1;
        return out;
      }
      if (char.charCodeAt(0) < 0x20) fail();
      if (char === "\\") {
        const next = text[index + 1];
        const simple: Record<string, string> = {
          '"': '"',
          "\\": "\\",
          "/": "/",
          b: "\b",
          f: "\f",
          n: "\n",
          r: "\r",
          t: "\t",
        };
        if (next in simple) {
          out += simple[next];
          index += 2;
        } else if (next === "u") {
          const hex = text.slice(index + 2, index + 6);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail();
          out += String.fromCharCode(parseInt(hex, 16));
          index += 6;
        } else {
          fail();
        }
        continue;
      }
      out += char;
      index += 1;
    }
  };
  const number = (): number => {
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?/.exec(text.slice(index));
    if (!match) return fail();
    index += match[0].length;
    return Number(match[0]);
  };
  const value = (depth: number): unknown => {
    if (depth >= MAX_DEPTH) throw new JsonDepthError("too deep");
    skip();
    const char = text[index];
    if (char === "{") {
      index += 1;
      const object: Record<string, unknown> = {};
      skip();
      if (text[index] === "}") {
        index += 1;
        return object;
      }
      while (true) {
        skip();
        if (text[index] !== '"') fail();
        const key = string();
        skip();
        if (text[index] !== ":") fail();
        index += 1;
        const item = value(depth + 1);
        Object.defineProperty(object, key, { value: item, writable: true, enumerable: true, configurable: true });
        skip();
        if (text[index] === ",") {
          index += 1;
          continue;
        }
        if (text[index] === "}") {
          index += 1;
          return object;
        }
        fail();
      }
    }
    if (char === "[") {
      index += 1;
      const array: unknown[] = [];
      skip();
      if (text[index] === "]") {
        index += 1;
        return array;
      }
      while (true) {
        array.push(value(depth + 1));
        skip();
        if (text[index] === ",") {
          index += 1;
          continue;
        }
        if (text[index] === "]") {
          index += 1;
          return array;
        }
        fail();
      }
    }
    if (char === '"') return string();
    if (char === "n") return literal("null", null);
    if (char === "t") return literal("true", true);
    if (char === "f") return literal("false", false);
    if (char === "N") return literal("NaN", NaN);
    if (char === "I") return literal("Infinity", Infinity);
    if (char === "-" && text.startsWith("-Infinity", index)) return literal("-Infinity", -Infinity);
    return number();
  };
  const result = value(0);
  skip();
  if (index !== text.length) fail();
  return result;
}

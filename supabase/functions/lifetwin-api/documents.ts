/** Conservative parser-only document extraction. No document text reaches a provider. */
import content from "./wellness-content.json" with { type: "json" };
const data: any = content.documents;
const patterns: Record<string, { source: string; flags: string }> =
  data.patterns;
function rx(source: string, flags = ""): RegExp {
  return new RegExp(source.replaceAll("(?P<", "(?<"), flags);
}
function pattern(name: string, global = false): RegExp {
  const p = patterns[name];
  return rx(p.source, p.flags + (global ? "g" : ""));
}
const words = (value: string): string[] =>
  value.toLowerCase().match(/[a-z][a-z'-]+/g) ?? [];
export function redact(
  pages: string[],
): { pages: string[]; removed: number; patients: number } {
  let removed = 0;
  const names: Set<string>[] = [], nameWords = new Set<string>();
  const red = (name: string, global = false) => {
    const p = data.redaction[name];
    return rx(p.source, p.flags + (global ? "g" : ""));
  };
  const addName = (value: string, patient: boolean) => {
    const tokens = new Set(words(value).filter((w) => w.length > 1));
    if (patient && tokens.size) names.push(tokens);
    for (const token of tokens) if (token.length > 2) nameWords.add(token);
  };
  const labelled = red("_LABELLED", true);
  const clean = pages.map((page) => {
    let dropNext = false, previous = "";
    return page.split("\n").map((line) => {
      if (dropNext && line.trim()) {
        dropNext = false;
        if (
          red("_IS_NAME_LABEL").test(previous.replace(/[:#]\s*$/, "").trim())
        ) addName(line, true);
        removed++;
        return "[removed]";
      }
      if (red("_LABEL_ONLY").test(line)) {
        dropNext = true;
        previous = line;
        return line;
      }
      previous = line;
      return line.replace(labelled, (...args: any[]) => {
        const groups = args[args.length - 1];
        if (!groups.value.trim()) return args[0];
        const patient = red("_IS_NAME_LABEL").test(groups.label);
        if (
          patient ||
          rx(`^(?:${data.redact_people_labels})`, "i").test(groups.label)
        ) addName(groups.value, patient);
        removed++;
        return `${groups.label}${groups.sep} [removed]`;
      });
    }).join("\n");
  });
  const people: Set<string>[] = [];
  for (const name of names) {
    const same = people.findIndex((p) =>
      [...name].every((w) => p.has(w)) || [...p].every((w) => name.has(w))
    );
    if (same >= 0) { for (const token of name) people[same].add(token); }
    else people.push(name);
  }
  const common = new Set(data.common_name_words);
  const namePattern = [...nameWords].filter((w) => !common.has(w)).sort((
    a,
    b,
  ) => b.length - a.length);
  const safePages = clean.map((initial) => {
    let page = initial;
    for (const p of data.redact_inline) {
      page = page.replace(rx(p.source, p.flags + "g"), () => {
        removed++;
        return "[removed]";
      });
    }
    for (const name of ["_HONORIFIC", "_CREDENTIAL", "_DEAR"]) {
      page = page.replace(red(name, true), () => {
        removed++;
        return "[name]";
      });
    }
    if (namePattern.length) {
      page = page.replace(
        new RegExp(
          `\\b(?:${
            namePattern.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
              .join("|")
          })\\b`,
          "gi",
        ),
        () => {
          removed++;
          return "[name]";
        },
      );
    }
    return page;
  });
  return { pages: safePages, removed, patients: people.length };
}
const sections = new Set(data.patient_sections),
  diagnosisSections = new Set(data.diagnosis_sections);
export function heading(line: string): string | null {
  const text = line.trim().replace(/^[*#=\-_ ]+|[*#=\-_ ]+$/g, "").trim();
  const [head, ...rest] = text.split(":");
  const normalized = head.trim().toLowerCase().replace(/\s+/g, " ").replace(
    /\s*\/\s*/g,
    "/",
  );
  if (
    sections.has(normalized) ||
    sections.has(normalized.replaceAll("/", " and "))
  ) return normalized;
  const count = normalized.split(/\s+/).length;
  if (!rest.join(":").trim() && count <= 4 && !/\d/.test(normalized)) {
    for (
      const known of [...sections].sort((a: any, b: any) => b.length - a.length)
    ) if (normalized.startsWith(known + " ")) return known as string;
  }
  if (
    count <= 5 && !/\d/.test(normalized) &&
    pattern("_OTHER_PERSON").test(normalized)
  ) return normalized;
  if (
    !rest.join(":").trim() && count <= 5 && !/\d/.test(text) &&
    (rest.length || (text.toUpperCase() === text && text.length > 3))
  ) return normalized;
  return null;
}
function isoDate(y: number, m: number, d: number): string | null {
  const value = new Date(Date.UTC(y, m - 1, d));
  if (
    value.getUTCFullYear() !== y || value.getUTCMonth() !== m - 1 ||
    value.getUTCDate() !== d || y < 1900 || y > new Date().getUTCFullYear() + 1
  ) return null;
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${
    String(d).padStart(2, "0")
  }`;
}
export function dates(
  text: string,
): { start: number; length: number; date: string }[] {
  const out: { start: number; length: number; date: string }[] = [];
  for (
    const match of text.matchAll(
      /(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)|(?<![\d/])(\d{1,2})\/(\d{1,2})\/(\d{4}|\d{2})(?![\d/])|(?<![\d-])(\d{1,2})-(\d{1,2})-(\d{4})(?![\d-])/g,
    )
  ) {
    let y: number, m: number, d: number;
    if (match[1]) [y, m, d] = match.slice(1, 4).map(Number);
    else {
      [m, d, y] = match.slice(match[4] ? 4 : 7, match[4] ? 7 : 10).map(Number);
      if (y < 100) y += y <= new Date().getUTCFullYear() % 100 ? 2000 : 1900;
      if (m > 12 && d <= 12) [m, d] = [d, m];
    }
    const date = isoDate(y, m, d);
    if (date) out.push({ start: match.index!, length: match[0].length, date });
  }
  const months = [
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
  ];
  for (
    const match of text.matchAll(
      /\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b|\b(\d{1,2})[\s-]([a-z]{3,9})\.?[\s,-]+(\d{4})\b/gi,
    )
  ) {
    const date = match[1]
      ? isoDate(
        +match[3],
        months.indexOf(match[1].slice(0, 3).toLowerCase()) + 1,
        +match[2],
      )
      : isoDate(
        +match[6],
        months.indexOf(match[5].slice(0, 3).toLowerCase()) + 1,
        +match[4],
      );
    if (date) out.push({ start: match.index!, length: match[0].length, date });
  }
  return out.sort((a, b) => a.start - b.start);
}
export function documentDate(pages: string[]): string | null {
  for (const labels of data.date_labels) {
    for (const page of pages) {
      for (const line of page.split("\n")) {
        for (
          const match of line.matchAll(
            new RegExp(`\\b(?:${labels})\\b\\s*(?:on)?\\s*[:#-]?\\s*`, "gi"),
          )
        ) {
          const found = dates(line.slice(match.index! + match[0].length)).find(
            (d) => d.start <= 3,
          );
          if (found) return found.date;
        }
      }
    }
  }
  return null;
}
export type Candidate = {
  field: string;
  use: string;
  value: number | boolean | string;
  unit: string | null;
  date: string | null;
  date_basis: string | null;
  source_text: string;
  page: number;
  section: string | null;
  confidence: string;
  method: string;
};
export function readLine(
  line: string,
  page: number,
  section: string | null,
): Candidate[] {
  const found: Candidate[] = [];
  const when = dates(line);
  let plain = line;
  for (const item of [...when].reverse()) {
    plain = plain.slice(0, item.start) + " ".repeat(item.length) +
      plain.slice(item.start + item.length);
  }
  const add = (
    field: string,
    value: number | boolean | string,
    unit: string | null,
    confidence = "high",
  ) =>
    found.push({
      field,
      use: data.model_inputs.includes(field) ? "model_input" : "information",
      value,
      unit,
      date: when[0]?.date ?? null,
      date_basis: when.length ? "line" : null,
      source_text: line.length > 300 ? line.slice(0, 297) + "..." : line,
      page,
      section: section
        ? section.replace(/\b[a-z]/g, (c) => c.toUpperCase()).slice(0, 60)
        : null,
      confidence,
      method: "parser",
    });
  const clear = (start: number, end: number) =>
    !pattern("_SKIP_NEAR").test(plain.slice(Math.max(0, start - 18), end));
  for (const label of plain.matchAll(pattern("_HEIGHT_LABEL", true))) {
    const tail = plain.slice(label.index! + label[0].length);
    let value: number | null = null, end = 0, m: RegExpExecArray | null;
    if ((m = pattern("_HEIGHT_UNIT_FIRST").exec(tail))) {
      value = m[1].toLowerCase() === "cm"
        ? +m[2]
        : m[1].toLowerCase().startsWith("in")
        ? +m[2] * 2.54
        : null;
      end = m[0].length;
    } else if ((m = pattern("_HEIGHT_FT").exec(tail))) {
      if (+(m[2] ?? 0) >= 12) continue;
      value = (+m[1] * 12 + +(m[2] ?? 0)) * 2.54;
      end = m[0].length;
    } else if ((m = pattern("_HEIGHT_CM").exec(tail))) {
      value = +m[1] * (m[2].toLowerCase() === "m" ? 100 : 1);
      end = m[0].length;
    } else if ((m = pattern("_HEIGHT_IN").exec(tail))) {
      value = +m[1] * 2.54;
      end = m[0].length;
    }
    if (
      value !== null && value >= 100 && value <= 250 &&
      clear(label.index!, label.index! + label[0].length + end)
    ) add("height_cm", Math.round(value * 10) / 10, "cm");
  }
  for (const label of plain.matchAll(pattern("_WEIGHT_LABEL", true))) {
    const tail = plain.slice(label.index! + label[0].length);
    let m: RegExpExecArray | null, value: number, unit: string;
    if ((m = pattern("_WEIGHT_UNIT_FIRST").exec(tail))) {
      [unit, value] = [m[1], +m[2]];
    } else if ((m = pattern("_WEIGHT").exec(tail))) {
      [value, unit] = [+m[1], m[2]];
    } else continue;
    const kg = unit.toLowerCase().startsWith("k") ? value : value * 0.45359237;
    if (
      kg >= 25 && kg <= 300 &&
      clear(label.index!, label.index! + label[0].length + m[0].length)
    ) add("weight_kg", Math.round(kg * 10) / 10, "kg");
  }
  const labels = [...plain.matchAll(pattern("_BP_LABEL", true))];
  if (labels.length || /blood pressure|\bbp\b/i.test(section ?? "")) {
    for (const match of plain.matchAll(pattern("_BP", true))) {
      const before = labels.filter((l) =>
        l.index! + l[0].length <= match.index!
      );
      const last = before.at(-1);
      if (
        labels.length &&
        (!last || match.index! - (last.index! + last[0].length) > 28 ||
          !clear(last.index!, match.index! + match[0].length) ||
          /\d/.test(plain.slice(last.index! + last[0].length, match.index)))
      ) {
        continue;
      }
      if (!labels.length && pattern("_SKIP_NEAR").test(plain)) continue;
      if (
        +match[1] >= 70 && +match[1] <= 260 && +match[2] >= 40 &&
        +match[2] <= 150 && +match[1] > +match[2]
      ) add("blood_pressure", `${+match[1]}/${+match[2]}`, "mmHg");
    }
  }
  for (
    const [labelName, field] of [["_A1C", "hba1c"], ["_LDL", "ldl_cholesterol"]]
  ) {
    for (const label of plain.matchAll(pattern(labelName, true))) {
      const tail = plain.slice(label.index! + label[0].length),
        m = pattern("_LAB_VALUE").exec(tail);
      if (
        !m ||
        !pattern("_LAB_FLAG_ONLY").test(tail.slice(0, m[0].indexOf(m[1]))) ||
        !clear(label.index!, label.index! + label[0].length + m[0].length)
      ) continue;
      const value = +m[1], unit = (m[2] ?? "").toLowerCase();
      if (
        field === "hba1c" && ["", "%"].includes(unit) && value >= 3 &&
        value <= 20
      ) add(field, value, "%", unit ? "high" : "medium");
      if (field === "ldl_cholesterol") {
        if ((unit === "mg/dl" || !unit) && value >= 20 && value <= 400) {
          add(field, value, "mg/dL", unit ? "high" : "medium");
        } else if ((unit === "mmol/l" || !unit) && value >= .5 && value <= 10) {
          add(field, value, "mmol/L", unit ? "high" : "medium");
        }
      }
    }
  }
  if (section && diagnosisSections.has(section)) {
    for (const clause of line.split(pattern("_CLAUSE"))) {
      for (
        const [field, name] of [["hypertension_diagnosed", "_HTN"], [
          "diabetes_diagnosed",
          "_DM",
        ]]
      ) {
        const match = pattern(name).exec(clause);
        if (
          match && !pattern("_UNCERTAIN").test(clause) &&
          !pattern("_NEGATION").test(clause.slice(0, match.index))
        ) {
          add(field, true, null);
        }
      }
    }
  }
  if (pattern("_SMOKING").test(line) && !pattern("_SMOKING_SKIP").test(line)) {
    const states = [
      [
        "former",
        /\b(?:former|ex-?smoker|quit|quitted|stopped|past smoker|previous smoker)\b/i,
      ],
      ["never", /\bnever\b/i],
      [
        "current",
        /\b(?:current|currently smokes|smokes|every day|everyday|some days|daily smoker|ppd|packs? (?:a|per) day|pack a day|cigarettes? (?:a|per) day|active smoker)\b/i,
      ],
    ] as const;
    const statuses = states.filter(([, p]) => p.test(line));
    if (statuses.length === 1) add("smoking_status", statuses[0][0], null);
  }
  return found;
}
export function extractDocument(payload: any): any {
  const stripped = redact(payload.pages), notices: string[] = [];
  const result: any = {
    schema_version: "1.0",
    status: "nothing_found",
    candidates: [],
    notices,
    identifiers_removed: stripped.removed,
    provider_status: "not_requested",
    limitations: [
      "Every value is a suggestion until the person confirms it.",
      "Nothing from the document is stored. The text is discarded after this response.",
      "A missing diagnosis in a document does not mean the person does not have it.",
      "Only deterministic English text extraction is enabled on this backend; outside-AI document reading is unavailable.",
    ],
  };
  if (stripped.patients > 1) {
    notices.push("multiple_patients");
    return result;
  }
  const letters = stripped.pages.join(" ").match(/\p{L}/gu) ?? [];
  if (
    letters.length &&
    letters.filter((c) => c.charCodeAt(0) > 127).length / letters.length > .3
  ) {
    notices.push("language_not_supported");
    return result;
  }
  const languageWords =
    stripped.pages.join(" ").toLowerCase().match(/\p{L}+/gu) ?? [];
  const english = new Set(data.english_words),
    foreign = new Set(data.foreign_words);
  const englishCount = languageWords.filter((w) => english.has(w)).length,
    foreignCount = languageWords.filter((w) => foreign.has(w)).length;
  if (foreignCount >= 5 && foreignCount > englishCount) {
    notices.push("language_not_supported");
    return result;
  }
  const found: Candidate[] = [];
  let wordCount = 0, garbled = 0, otherSkipped = false;
  for (const [p, page] of stripped.pages.entries()) {
    let section: string | null = null, other = false;
    for (const raw of page.split("\n")) {
      const line = raw.trim();
      if (!line) continue;
      wordCount += (line.match(/[A-Za-z]{3,}/g) ?? []).length;
      const head = heading(line);
      if (head !== null) {
        if (!sections.has(head) && pattern("_OTHER_PERSON").test(head)) {
          other = true;
        } else if (sections.has(head) || !other) other = false;
        section = head;
      }
      if (other || pattern("_OTHER_PERSON").test(line)) {
        if (
          pattern("_VALUE_HINT").test(line) || pattern("_HTN").test(line) ||
          pattern("_DM").test(line)
        ) otherSkipped = true;
        continue;
      }
      if (pattern("_GARBLED").test(line)) {
        garbled++;
        if (/\d/.test(line)) continue;
      }
      found.push(...readLine(line, p + 1, section));
    }
  }
  const docDate = documentDate(stripped.pages),
    byField = new Map<string, Candidate[]>();
  for (const candidate of found) {
    if (!candidate.date && docDate) {
      candidate.date = docDate;
      candidate.date_basis = "document";
    }
    if (!byField.has(candidate.field)) byField.set(candidate.field, []);
    byField.get(candidate.field)!.push(candidate);
  }
  for (const [field, items] of byField) {
    items.sort((a, b) => (b.date ?? "").localeCompare(a.date ?? ""));
    if (field === "blood_pressure") {
      const kept: Candidate[] = [];
      for (const item of items) {
        if (
          !kept.some((k) =>
            k.value === item.value &&
            (k.date === item.date || !k.date || !item.date)
          )
        ) kept.push(item);
      }
      result.candidates.push(...kept.slice(0, 6));
      continue;
    }
    const values = new Set(items.map((i) => JSON.stringify(i.value)));
    const latest = items[0].date,
      newest = latest ? items.filter((i) => i.date === latest) : items;
    if (
      values.size === 1 ||
      (latest && new Set(newest.map((i) => JSON.stringify(i.value))).size === 1)
    ) result.candidates.push(items[0]);
    else if (!notices.includes("conflicting_values")) {
      notices.push("conflicting_values");
    }
  }
  for (const candidate of result.candidates) {
    if (!candidate.date && candidate.confidence === "high") {
      candidate.confidence = "medium";
    }
  }
  result.candidates.sort((a: Candidate, b: Candidate) =>
    data.field_order.indexOf(a.field) - data.field_order.indexOf(b.field) ||
    a.page - b.page
  );
  result.candidates = result.candidates.slice(0, 40);
  if (otherSkipped) notices.push("other_person_skipped");
  if (garbled >= 2) notices.push("partly_unreadable");
  result.status = result.candidates.length
    ? "found"
    : wordCount < 12
    ? "unreadable"
    : "nothing_found";
  return result;
}

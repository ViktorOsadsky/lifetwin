"""Deterministic candidate extraction from identifier-stripped document text.

Rules are in docs/document-upload.md. A value is offered only with a label, a
plausible number and units; a diagnosis only from explicit wording in a
diagnosis section. Anything doubtful yields nothing, so the conversation asks.
"""

import re
from dataclasses import dataclass, field
from datetime import date

from lifetwin.documents.models import MODEL_INPUTS, DocumentCandidate

MAX_BP_READINGS = 6

# ---------------------------------------------------------------- sections

_DIAGNOSIS_SECTIONS = {
    "assessment",
    "assessment and plan",
    "assessment & plan",
    "assessment/plan",
    "a/p",
    "diagnosis",
    "diagnoses",
    "discharge diagnosis",
    "discharge diagnoses",
    "problem list",
    "active problems",
    "active problem list",
    "problems",
    "past medical history",
    "pmh",
    "impression",
}
_PATIENT_SECTIONS = _DIAGNOSIS_SECTIONS | {
    "vitals",
    "vital signs",
    "plan",
    "social history",
    "results",
    "lab results",
    "labs",
    "laboratory results",
    "medications",
    "current medications",
    "medication list",
    "discharge medications",
    "allergies",
    "history of present illness",
    "hpi",
    "chief complaint",
    "reason for visit",
    "review of systems",
    "physical exam",
    "exam",
    "hospital course",
    "discharge instructions",
    "instructions",
    "follow-up",
    "follow up",
    "immunizations",
    "participant",
    "participant results",
    "patient",
    "your results",
    "measurements",
    "biometrics",
    "screening results",
    "employee",
    "primary member",
    "blood pressure log",
    "blood pressure readings",
    "home blood pressure log",
    "bp log",
    "readings",
}
_OTHER_PERSON = re.compile(
    r"\b(?:spouse|partner|husband|wife|family history|family hx|fhx|fh|mother|father|mom|dad"
    r"|sister|brother|sibling|siblings|son|daughter|children|grandmother|grandfather|aunt|uncle"
    r"|relative|relatives|family)\b",
    re.IGNORECASE,
)


def _heading(line: str) -> str | None:
    """The normalised heading a line starts, or None for an ordinary line."""
    text = line.strip().strip("*#=-_ ").strip()
    if not text:
        return None
    head, colon, _rest = text.partition(":")
    head = re.sub(r"\s+", " ", head.strip().lower())
    head = re.sub(r"\s*/\s*", "/", head)
    if head in _PATIENT_SECTIONS or (head.replace("/", " and ") in _PATIENT_SECTIONS):
        return head
    words = head.split()
    # "Results reviewed", "Vitals today": a known heading with a word or two after it.
    if not _rest.strip() and len(words) <= 4 and not re.search(r"\d", head):
        for known in sorted(_PATIENT_SECTIONS, key=len, reverse=True):
            if head.startswith(known + " "):
                return known
    if 0 < len(words) <= 5 and not re.search(r"\d", head) and _OTHER_PERSON.search(head):
        return head
    # An unknown short heading alone on its line ("HOSPITAL COURSE", "Plan of care:").
    if not _rest.strip() and 0 < len(words) <= 5 and not re.search(r"\d", text):
        if colon or (text.isupper() and len(text) > 3):
            return head
    return None


def _is_other(heading: str) -> bool:
    return heading not in _PATIENT_SECTIONS and bool(_OTHER_PERSON.search(heading))


# ---------------------------------------------------------------- dates

_MONTHS = {
    m: i
    for i, names in enumerate(
        [
            ("jan", "january"),
            ("feb", "february"),
            ("mar", "march"),
            ("apr", "april"),
            ("may",),
            ("jun", "june"),
            ("jul", "july"),
            ("aug", "august"),
            ("sep", "sept", "september"),
            ("oct", "october"),
            ("nov", "november"),
            ("dec", "december"),
        ],
        start=1,
    )
    for m in names
}
_MONTH = r"(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?"
_DATES = (
    ("iso", re.compile(r"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)")),
    ("us", re.compile(r"(?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/])")),
    ("us", re.compile(r"(?<![\d-])(\d{1,2})-(\d{1,2})-(\d{4})(?![\d-])")),
    ("mdy", re.compile(rf"\b({_MONTH})\s+(\d{{1,2}})(?:st|nd|rd|th)?,?\s+(\d{{4}})\b", re.I)),
    ("dmy", re.compile(rf"\b(\d{{1,2}})[\s-]({_MONTH})[\s,-]+(\d{{4}})\b", re.I)),
)


def find_dates(text: str, today: date) -> list[tuple[int, int, date]]:
    """Every full date in the text as (start, end, date)."""
    found = []
    for kind, pattern in _DATES:
        for m in pattern.finditer(text):
            a, b, c = m.groups()
            try:
                if kind == "iso":
                    y, mo, d = int(a), int(b), int(c)
                elif kind == "us":
                    mo, d, y = int(a), int(b), int(c)
                    if y < 100:
                        y += 2000 if y <= today.year % 100 else 1900
                    if mo > 12 and d <= 12:
                        mo, d = d, mo
                elif kind == "mdy":
                    mo, d, y = _MONTHS[a.lower()[:3]], int(b), int(c)
                else:
                    d, mo, y = int(a), _MONTHS[b.lower()[:3]], int(c)
                value = date(y, mo, d)
            except (ValueError, KeyError):
                continue
            if 1900 <= value.year <= today.year + 1:
                found.append((m.start(), m.end(), value))
    found.sort()
    return found


_DOC_DATE_LABELS = (
    r"date of service|service date|dos|visit date|date of visit|encounter date",
    r"date collected|collection date|collected|specimen collected",
    r"discharge date|date of discharge|discharged",
    r"date reported|report date|result date|reported|resulted",
    r"date printed|print date|printed|fill date|date filled|filled",
)


def document_date(pages: list[str], today: date) -> date | None:
    for labels in _DOC_DATE_LABELS:
        pattern = re.compile(rf"\b(?:{labels})\b\s*(?:on)?\s*[:#-]?\s*", re.I)
        for page in pages:
            for line in page.split("\n"):
                for m in pattern.finditer(line):
                    dates = [d for s, _e, d in find_dates(line[m.end() :], today) if s <= 3]
                    if dates:
                        return dates[0]
    return None


# ---------------------------------------------------------------- values

_NUM = r"(\d{1,3}(?:\.\d{1,2})?)"
_SKIP_NEAR = re.compile(
    r"\b(?:goal|target|ideal|desired|usual|previous|prior|last visit|change|changed|loss|gain"
    r"|lost|gained|down|up|birth|ibw|dosing|estimated|est|reported by|self-reported|range"
    r"|normal|ref|reference|recheck|repeat goal|under|below|above|less than|greater than)\b"
    r"|[<>≤≥]",
    re.IGNORECASE,
)

_HEIGHT_LABEL = re.compile(r"\b(?:height|ht|hgt|stature)\b\.?", re.I)
_HEIGHT_UNIT_FIRST = re.compile(r"^\s*\((cm|in|inches|ft)\)\s*[:=]?\s*" + _NUM + r"(?![\d.])", re.I)
_HEIGHT_FT = re.compile(
    r"^\s*[:=]?\s*(\d)\s*(?:'|’|′|ft\.?|feet|foot)\s*(?:(\d{1,2}(?:\.\d)?)\s*"
    r"(?:\"|”|″|''|’’|in\b\.?|inches|inch)?)?",
    re.I,
)
_HEIGHT_CM = re.compile(r"^\s*[:=]?\s*" + _NUM + r"\s*(cm|centimeters|m)\b", re.I)
_HEIGHT_IN = re.compile(r"^\s*[:=]?\s*(\d{2}(?:\.\d{1,2})?)\s*(?:in\b\.?|inches|\"|”|″)", re.I)

_WEIGHT_LABEL = re.compile(r"\b(?:body weight|weight|wt|wgt)\b\.?", re.I)
_WEIGHT_UNIT_FIRST = re.compile(r"^\s*\((lbs?|kg|kgs)\)\s*[:=]?\s*" + _NUM + r"(?![\d.])", re.I)
_WEIGHT = re.compile(r"^\s*[:=]?\s*" + _NUM + r"\s*(lbs?|pounds?|kgs?|kilograms?)\b\.?", re.I)

_BP_LABEL = re.compile(r"\b(?:bp|b/p|blood pressure|blood pres\.?)\b", re.I)
_BP = re.compile(r"(?<![\d/.])(\d{2,3})\s*/\s*(\d{2,3})(?![\d/.])")

_A1C = re.compile(
    r"\b(?:hemoglobin a1c|haemoglobin a1c|hgb a1c|hb a1c|hba1c|hgba1c|a1c|glycated hemoglobin"
    r"|glycohemoglobin)\b",
    re.I,
)
_LDL = re.compile(
    r"(?<![\w-])(?:ldl(?:[- ]?c)?(?:\s+cholesterol)?(?:,?\s*calc(?:ulated)?\.?)?"
    r"|ldl cholesterol(?:,?\s*calc(?:ulated)?)?)\b",
    re.I,
)
_LAB_VALUE = re.compile(
    r"^[^\d\n]{0,24}?(?<![\d.])(\d{1,3}(?:\.\d{1,2})?)(?![\d./])\s*(%|mg/dl|mmol/l)?", re.I
)
_LAB_FLAG_ONLY = re.compile(r"^[\s:=]*(?:\(?[hl]\)?|high|low|final|result|value|\s)*$", re.I)


@dataclass
class Found:
    field: str
    value: float | bool | str
    unit: str | None
    page: int
    line: str
    section: str | None
    line_date: date | None
    confidence: str = "high"
    method: str = "parser"


@dataclass
class Parsed:
    found: list[Found] = field(default_factory=list)
    other_person_skipped: bool = False
    garbled_lines: int = 0
    words: int = 0


def _window_clear(line: str, start: int, end: int) -> bool:
    """No goal/target/change cue just before the label or between label and value."""
    return not _SKIP_NEAR.search(line[max(0, start - 18) : end])


def _heights(line: str):
    for m in _HEIGHT_LABEL.finditer(line):
        rest = line[m.end() :]
        if u := _HEIGHT_UNIT_FIRST.match(rest):
            unit, value = u.group(1).lower(), float(u.group(2))
            cm = value if unit == "cm" else value * 2.54 if unit.startswith("in") else None
            end = m.end() + u.end()
        elif f := _HEIGHT_FT.match(rest):
            inches = float(f.group(2) or 0)
            if inches >= 12:
                continue
            cm = (int(f.group(1)) * 12 + inches) * 2.54
            end = m.end() + f.end()
        elif c := _HEIGHT_CM.match(rest):
            value, unit = float(c.group(1)), c.group(2).lower()
            cm = value * 100 if unit == "m" else value
            end = m.end() + c.end()
        elif i := _HEIGHT_IN.match(rest):
            cm = float(i.group(1)) * 2.54
            end = m.end() + i.end()
        else:
            continue
        if cm is not None and 100 <= cm <= 250 and _window_clear(line, m.start(), end):
            yield round(cm, 1)


def _weights(line: str):
    for m in _WEIGHT_LABEL.finditer(line):
        rest = line[m.end() :]
        if u := _WEIGHT_UNIT_FIRST.match(rest):
            unit, value = u.group(1).lower(), float(u.group(2))
            end = m.end() + u.end()
        elif w := _WEIGHT.match(rest):
            value, unit = float(w.group(1)), w.group(2).lower()
            end = m.end() + w.end()
        else:
            continue
        kg = value if unit.startswith("k") else value * 0.45359237
        if 25 <= kg <= 300 and _window_clear(line, m.start(), end):
            yield round(kg, 1)


def _pressures(line: str, in_bp_section: bool):
    labels = list(_BP_LABEL.finditer(line))
    if not labels and not in_bp_section:
        return
    for m in _BP.finditer(line):
        before = [lab for lab in labels if lab.end() <= m.start()]
        if labels:
            if not before or m.start() - before[-1].end() > 28:
                continue
            if not _window_clear(line, before[-1].start(), m.end()):
                continue
            between = line[before[-1].end() : m.start()]
            if re.search(r"\d", between):
                continue
        elif _SKIP_NEAR.search(line):
            continue
        sys_, dia = int(m.group(1)), int(m.group(2))
        if 70 <= sys_ <= 260 and 40 <= dia <= 150 and sys_ > dia:
            yield f"{sys_}/{dia}"


def _lab(line: str, label: re.Pattern, kind: str):
    for m in label.finditer(line):
        rest = line[m.end() :]
        v = _LAB_VALUE.match(rest)
        if not v or not _LAB_FLAG_ONLY.match(rest[: v.start(1)]):
            continue
        if not _window_clear(line, m.start(), m.end() + v.end()):
            continue
        value = float(v.group(1))
        unit = (v.group(2) or "").lower()
        if kind == "hba1c":
            if unit not in {"", "%"} or not 3 <= value <= 20:
                continue
            yield value, "%", "high" if unit else "medium"
        else:
            if unit == "mg/dl" or (not unit and 20 <= value <= 400):
                if 20 <= value <= 400:
                    yield value, "mg/dL", "high" if unit else "medium"
            elif unit == "mmol/l" or (not unit and 0.5 <= value <= 10):
                if 0.5 <= value <= 10:
                    yield value, "mmol/L", "high" if unit else "medium"


# ---------------------------------------------------------------- diagnoses and smoking

_HTN = re.compile(r"\b(?:essential hypertension|hypertension|htn|high blood pressure|i10)\b", re.I)
_DM = re.compile(
    r"\b(?:diabetes mellitus|diabetes|t2dm|t1dm|dm2|dm-2|dm ii|dm type (?:1|2|i|ii)"
    r"|type (?:1|2|i|ii) dm|iddm|niddm|e1[01](?:\.\d{1,2})?)\b",
    re.I,
)
_NEGATION = re.compile(
    r"\b(?:no|not|denies|denied|never|negative|neg|without (?:a )?(?:history|diagnosis|evidence)"
    r"|r/o|rule out|ruled out|absence of|free of)\b",
    re.I,
)
_UNCERTAIN = re.compile(
    r"\b(?:screening|screen|risk|possible|possibly|probable|probably|suspected|suspect|suspicion"
    r"|questionable|concern for|consider|borderline|likely|vs|versus|rule out|ruled out|r/o"
    r"|history of present|resolved|prediabetes|prediabetic|prehypertension|gestational|insipidus"
    r"|pulmonary|portal|ocular|intracranial|white coat|pregnancy|preeclampsia|induced|elevated"
    r"|education|counsel(?:ing|ed)?|diet|monitor(?:ing)?|supplies|test strips|meter)\b|\?|pre-",
    re.I,
)
_CLAUSE = re.compile(r"[;,]|\s-\s|\s–\s|\s—\s")


def _diagnoses(line: str):
    for clause in _CLAUSE.split(line):
        for field_name, pattern in (("hypertension_diagnosed", _HTN), ("diabetes_diagnosed", _DM)):
            m = pattern.search(clause)
            if not m or _UNCERTAIN.search(clause) or _NEGATION.search(clause[: m.start()]):
                continue
            yield field_name


_SMOKING = re.compile(r"\b(?:smok\w*|tobacco|cigarettes?|cigs?|nicotine)\b", re.I)
_SMOKING_SKIP = re.compile(
    r"\b(?:smokeless|chew\w*|snuff|vap\w*|e-?cig\w*|second-?hand|secondhand|passive|exposure"
    r"|exposed|cessation|counsel\w*|non-?smok\w*|alcohol use: never)\b",
    re.I,
)
_SMOKING_STATUS = (
    (
        "former",
        re.compile(
            r"\b(?:former|ex-?smoker|quit|quitted|stopped|past smoker|previous smoker)\b", re.I
        ),
    ),
    ("never", re.compile(r"\bnever\b", re.I)),
    (
        "current",
        re.compile(
            r"\b(?:current|currently smokes|smokes|every day|everyday|some days|daily smoker|ppd"
            r"|packs? (?:a|per) day|pack a day|cigarettes? (?:a|per) day|active smoker)\b",
            re.I,
        ),
    ),
)


def _smoking(line: str) -> str | None:
    if not _SMOKING.search(line) or _SMOKING_SKIP.search(line):
        return None
    statuses = {status for status, pattern in _SMOKING_STATUS if pattern.search(line)}
    return statuses.pop() if len(statuses) == 1 else None


# ---------------------------------------------------------------- garble / words

_WORD = re.compile(r"[A-Za-z]{3,}")
_GARBLED = re.compile(
    r"\d[?¿]|[?¿]\d|\b[a-z]{2,}\d+[a-z]{2,}\b|[^\x00-\x7f\w\s][A-Za-z]|\?{2,}|�", re.I
)
_VALUE_HINT = re.compile(
    r"weight|height|\bwt\b|\bht\b|\bbp\b|pressure|a1c|ldl|smok|tobacco|diabet|hypert", re.I
)


def _garbled(line: str) -> bool:
    if _GARBLED.search(line):
        return True
    tokens = line.split()
    singles = sum(1 for t in tokens if len(t) == 1 and t.isalpha() and t.lower() not in "ai")
    return len(tokens) >= 4 and singles * 2 >= len(tokens)


def _near_miss(line: str) -> bool:
    """A line that looks like it held a value, but nothing could be read from it."""
    return bool(re.search(r"\d", line)) and _garbled(line)


# ---------------------------------------------------------------- the pass


@dataclass
class Line:
    page: int
    text: str
    section: str | None
    # Inside a section about someone else, or the line names a relative.
    other: bool


def lines(pages: list[str]) -> list[Line]:
    """Every nonblank line with the section it sits in."""
    out = []
    for page_no, page in enumerate(pages, start=1):
        section: str | None = None
        other = False
        for raw in page.split("\n"):
            line = raw.strip()
            if not line:
                continue
            heading = _heading(line)
            if heading is not None:
                if _is_other(heading):
                    other = True
                elif heading in _PATIENT_SECTIONS or not other:
                    other = False
                section = heading
            out.append(Line(page_no, line, section, other or bool(_OTHER_PERSON.search(line))))
    return out


def parse(pages: list[str], today: date) -> Parsed:
    result = Parsed()
    for item in lines(pages):
        result.words += len(_WORD.findall(item.text))
        if item.other:
            if _has_value(item.text):
                result.other_person_skipped = True
            continue
        if _garbled(item.text):
            result.garbled_lines += 1
            if _near_miss(item.text):
                continue
        result.found.extend(read_line(item.text, item.page, item.section, today))
    return result


def read_line(line: str, page: int, section: str | None, today: date) -> list[Found]:
    """Every value one line of the patient's own text states."""
    section = _heading(line) or section
    line_dates = find_dates(line, today)
    line_date = line_dates[0][2] if line_dates else None
    # Dates are not readings: blank them before reading numbers.
    plain = line
    for start, end, _d in reversed(line_dates):
        plain = plain[:start] + " " * (end - start) + plain[end:]
    found: list[Found] = []

    def add(field_name, value, unit, confidence="high"):
        found.append(
            Found(
                field_name, value, unit, page, line, _section_label(section), line_date, confidence
            )
        )

    for cm in _heights(plain):
        add("height_cm", cm, "cm")
    for kg in _weights(plain):
        add("weight_kg", kg, "kg")
    in_bp_section = bool(section and re.search(r"blood pressure|\bbp\b", section))
    for reading in _pressures(plain, in_bp_section):
        add("blood_pressure", reading, "mmHg")
    for value, unit, confidence in _lab(plain, _A1C, "hba1c"):
        add("hba1c", value, unit, confidence)
    for value, unit, confidence in _lab(plain, _LDL, "ldl"):
        add("ldl_cholesterol", value, unit, confidence)
    if section in _DIAGNOSIS_SECTIONS:
        for name in _diagnoses(_after_heading(line)):
            add(name, True, None)
    if status := _smoking(line):
        add("smoking_status", status, None)
    return found


def _after_heading(line: str) -> str:
    head, colon, rest = line.partition(":")
    return rest if colon and _heading(head + ":") else line


def _section_label(section: str | None) -> str | None:
    return section.title()[:60] if section else None


def _has_value(line: str) -> bool:
    return bool(
        _VALUE_HINT.search(line) or _HTN.search(line) or _DM.search(line) or _BP.search(line)
    )


# ---------------------------------------------------------------- choose


def choose(found: list[Found], doc_date: date | None) -> tuple[list[DocumentCandidate], bool]:
    """Apply date, dedupe and conflict rules. Returns candidates and whether a conflict hid any."""
    conflict = False
    by_field: dict[str, list[tuple[Found, date | None, str | None]]] = {}
    for item in found:
        when = item.line_date or doc_date
        basis = "line" if item.line_date else "document" if doc_date else None
        by_field.setdefault(item.field, []).append((item, when, basis))

    chosen: list[tuple[Found, date | None, str | None]] = []
    for name, items in by_field.items():
        if name == "blood_pressure":
            readings: dict[str, tuple[Found, date | None, str | None]] = {}
            for item, when, basis in items:
                same = [k for k, (f, w, _b) in readings.items() if f.value == item.value]
                if same:
                    kept = readings[same[0]]
                    # An undated copy of a dated reading is the same reading.
                    if kept[1] == when or kept[1] is None or when is None:
                        if kept[1] is None and when is not None:
                            readings[same[0]] = (item, when, basis)
                        continue
                readings[f"{item.value}@{when}"] = (item, when, basis)
            ordered = sorted(readings.values(), key=lambda r: r[1] or date.min, reverse=True)
            chosen.extend(ordered[:MAX_BP_READINGS])
            continue
        values = {_key(item.value) for item, _w, _b in items}
        if len(values) == 1:
            best = max(items, key=lambda r: (r[1] or date.min, r[0].confidence == "high"))
            chosen.append(best)
            continue
        latest = max((w for _i, w, _b in items if w), default=None)
        newest = [r for r in items if r[1] == latest] if latest else items
        if latest and len({_key(r[0].value) for r in newest}) == 1:
            chosen.append(newest[0])
        else:
            conflict = True

    candidates = []
    for item, when, basis in chosen:
        confidence = item.confidence
        if when is None and confidence == "high":
            confidence = "medium"
        candidates.append(
            DocumentCandidate(
                field=item.field,
                use="model_input" if item.field in MODEL_INPUTS else "information",
                value=item.value,
                unit=item.unit,
                date=when.isoformat() if when else None,
                date_basis=basis,
                source_text=_snippet(item.line),
                page=item.page,
                section=item.section,
                confidence=confidence,
                method=item.method,
            )
        )
    order = list(_FIELD_ORDER)
    candidates.sort(key=lambda c: (order.index(c.field), c.page))
    return candidates, conflict


_FIELD_ORDER = (
    "height_cm",
    "weight_kg",
    "smoking_status",
    "diabetes_diagnosed",
    "hypertension_diagnosed",
    "blood_pressure",
    "hba1c",
    "ldl_cholesterol",
)


def _key(value: float | bool | str) -> str:
    return str(round(value, 1)) if isinstance(value, float) else str(value)


def _snippet(line: str) -> str:
    text = re.sub(r"\s{3,}", "   ", line.strip())
    return text if len(text) <= 300 else text[:297] + "..."

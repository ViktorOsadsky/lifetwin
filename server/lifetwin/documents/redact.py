"""Remove identifiers from recognised document text before anything else reads it.

Conservative on purpose: a removed word costs nothing, a leaked name costs trust.
Patient names are compared here, inside the redactor, so they never leave it.
"""

import re
from dataclasses import dataclass

REMOVED = "[removed]"
NAME = "[name]"

# Labels whose value identifies a person. The label is kept, the value removed.
_NAME_LABELS = (
    r"patient(?: name)?|pt\.?(?: name)?|name|full name|participant(?: name)?|member name|resident"
)
_PEOPLE_LABELS = (
    r"spouse(?: name)?|partner(?: name)?|husband|wife|guarantor|emergency contact|next of kin"
    r"|caregiver|responsible party|subscriber(?: name)?"
    r"|pcp|provider|physician|attending(?: physician)?|ordering(?: provider| physician)?"
    r"|referring(?: provider| physician)?|prescriber|prescribed by|pharmacist|doctor"
    r"|signed by|electronically signed by|dictated by|author|cc"
)
_ID_LABELS = (
    r"dob|d\.o\.b\.?|date of birth|birth ?date|birthdate|born"
    r"|mrn|med(?:ical)? rec(?:ord)?(?: number| no\.?| #)?|account(?: number| no\.?| #)?"
    r"|acct\.?(?: no\.?| #)?|member(?: id| number| no\.?| #)?|insurance(?: id| number| #)?"
    r"|subscriber id|policy(?: number| no\.?| #)?|group(?: number| no\.?| #)?"
    r"|rx(?: number| no\.?| #)?|ssn|social security(?: number)?|address|home address|street"
    r"|city|phone|home phone|cell(?: phone)?|mobile|tel|telephone|fax|e-?mail"
    r"|accession(?: number| no\.?| #)?|specimen id|order(?: number| no\.?| #)?|visit id"
    r"|encounter id|csn|fin|patient id|pt id|id"
)
_ANY_LABEL = rf"(?:{_NAME_LABELS}|{_PEOPLE_LABELS}|{_ID_LABELS})"
# "MRN: 00482913" up to two spaces, a bar, the next label or the end of the line.
_LABELLED = re.compile(
    rf"(?<![\w-])(?P<label>{_ANY_LABEL})\s*(?P<sep>[:#])[ \t]*"
    rf"(?P<value>[^\n|]*?)(?=\s{{2,}}|\s*\|\s*|[ \t]+{_ANY_LABEL}\s*[:#]|$)",
    re.IGNORECASE,
)
# A label alone on its line ("Patient Name"): table OCR puts the value on the next line.
_LABEL_ONLY = re.compile(rf"^\s*(?:{_NAME_LABELS}|{_ID_LABELS})\s*[:#]?\s*$", re.IGNORECASE)
_IS_NAME_LABEL = re.compile(rf"^(?:{_NAME_LABELS})$", re.IGNORECASE)

_INLINE = (
    re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"),
    re.compile(r"\b\d{3}-\d{2}-\d{4}\b"),
    re.compile(r"(?<![\w/])(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}\b"),
    re.compile(
        r"\b\d{1,6}\s+(?:[A-Z][a-zA-Z]+\.?\s+){1,4}"
        r"(?:St|Street|Ave|Avenue|Rd|Road|Ln|Lane|Dr|Drive|Blvd|Boulevard|Ct|Court|Way|Pl|Place"
        r"|Pkwy|Parkway|Ter|Terrace|Cir|Circle|Hwy|Highway|Trl|Trail|Sq|Square)\b\.?"
        r"(?:,?\s*(?:Apt|Suite|Ste|Unit|#)\.?\s*\w+)?"
    ),
    re.compile(r"\b[A-Z][a-zA-Z .'-]{1,30},\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"),
    re.compile(r"\b(?:P\.?O\.? Box)\s+\d+\b", re.IGNORECASE),
    # Long identifiers: accession, member and account numbers, never dates.
    re.compile(r"\b[A-Z]{0,4}-?\d{6,}[A-Z0-9]*\b"),
)
_HONORIFIC = re.compile(
    r"\b(?P<title>Dr|Mr|Mrs|Ms|Miss|Mx)\.?\s+(?:[A-Z]\.\s*)?[A-Z][a-zA-Z'-]+(?:\s+[A-Z][a-zA-Z'-]+)?"
)
_CREDENTIAL = re.compile(
    r"\b[A-Z][a-zA-Z'-]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z'-]+,?\s+"
    r"(?:MD|M\.D\.|DO|NP|PA-C|PA|RN|PharmD|RPh|APRN|FNP|FNP-C|DNP)\b"
)
_BARE_NAME = re.compile(r"^\s*[A-Z][a-z'-]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z'-]+\s*$")
_PERSON_HEADING = re.compile(
    r"^(?:spouse|partner|husband|wife|spouse ?/ ?partner|patient|participant|member)\b[\w /]*$",
    re.IGNORECASE,
)
_DEAR = re.compile(r"\b(Dear)\s+[A-Z][a-zA-Z'-]+(?:\s+[A-Z][a-zA-Z'-]+)?")


@dataclass
class Redacted:
    pages: list[str]
    removed: int
    # Distinct patient names seen in name labels (compared here, never returned).
    patient_names: int


def _name_tokens(value: str) -> frozenset[str]:
    words = re.findall(r"[A-Za-z][A-Za-z'-]+", value)
    return frozenset(w.lower() for w in words if len(w) > 1)


def _distinct(names: list[frozenset[str]]) -> int:
    """Count people: "Harold J. Testman" and "TESTMAN, HAROLD" are one person."""
    people: list[frozenset[str]] = []
    for name in names:
        if not name:
            continue
        for index, known in enumerate(people):
            if name <= known or known <= name:
                people[index] = known | name
                break
        else:
            people.append(name)
    return len(people)


def redact(pages: list[str]) -> Redacted:
    removed = 0
    patient_names: list[frozenset[str]] = []
    name_words: set[str] = set()

    def labelled(match: re.Match) -> str:
        nonlocal removed
        value = match.group("value").strip()
        if not value:
            return match.group(0)
        label = match.group("label")
        if _IS_NAME_LABEL.match(label.strip()):
            tokens = _name_tokens(value)
            patient_names.append(tokens)
            name_words.update(t for t in tokens if len(t) > 2)
        elif re.match(_PEOPLE_LABELS, label, re.IGNORECASE):
            name_words.update(t for t in _name_tokens(value) if len(t) > 2)
        removed += 1
        return f"{label}{match.group('sep')} {REMOVED}"

    first_pass = []
    for page in pages:
        lines = page.split("\n")
        out = []
        drop_next = False
        for line in lines:
            if drop_next and line.strip():
                drop_next = False
                if _IS_NAME_LABEL.match(_previous_label(out)):
                    tokens = _name_tokens(line)
                    patient_names.append(tokens)
                    name_words.update(t for t in tokens if len(t) > 2)
                removed += 1
                out.append(REMOVED)
                continue
            if _LABEL_ONLY.match(line):
                drop_next = True
                out.append(line)
                continue
            # "Spouse / Partner" then "Linda Mockwell" on its own line.
            if _BARE_NAME.match(line) and _PERSON_HEADING.match(_previous_label(out)):
                name_words.update(t for t in _name_tokens(line) if len(t) > 2)
                removed += 1
                out.append(NAME)
                continue
            out.append(_LABELLED.sub(labelled, line))
        first_pass.append("\n".join(out))

    def count(replacement: str):
        def sub(match: re.Match) -> str:
            nonlocal removed
            removed += 1
            return replacement

        return sub

    result = []
    words = sorted(name_words - _COMMON_WORDS, key=len, reverse=True)
    name_pattern = (
        re.compile(r"\b(?:" + "|".join(re.escape(w) for w in words) + r")\b", re.IGNORECASE)
        if words
        else None
    )
    for page in first_pass:
        for pattern in _INLINE:
            page = pattern.sub(count(REMOVED), page)
        page = _HONORIFIC.sub(lambda m: (count("")(m), f"{m.group('title')}. {NAME}")[1], page)
        page = _CREDENTIAL.sub(count(NAME), page)
        page = _DEAR.sub(lambda m: (count("")(m), f"{m.group(1)} {NAME}")[1], page)
        if name_pattern:
            page = name_pattern.sub(count(NAME), page)
        result.append(page)
    return Redacted(pages=result, removed=removed, patient_names=_distinct(patient_names))


def _previous_label(lines: list[str]) -> str:
    for line in reversed(lines):
        if line.strip():
            return re.sub(r"[:#]\s*$", "", line.strip())
    return ""


# Words that can follow a name label but are not names ("Name: see above").
_COMMON_WORDS = {
    "the",
    "and",
    "see",
    "above",
    "below",
    "none",
    "unknown",
    "self",
    "same",
    "patient",
    "spouse",
    "partner",
    "wife",
    "husband",
    "removed",
    "name",
    "md",
    "do",
    "np",
    "rn",
    "pharmd",
}

"""Every outside-AI line is checked before Mochi says it; a failed check uses the template.

The check refuses medical claims and advice (years gained, dates and time words,
diagnoses, medicines, doses, supplements other than a gentle, doctor-checked mention, promises), weight and diet words, percentages,
links, and any number (digits or words) the facts do not hold.
"""

import re

BLOCKED = re.compile(
    r"\b(?:years?|life ?span|life expectancy|live longer|longevity|death|die|dying|date|"
    r"diagnos\w*|prescri\w*|medicat\w*|medicine\w*|pills?|tablets?|doses?|dosage|dosing|"
    r"mg|mcg|milligrams?|iu|fish oil|omega|turmeric|"
    r"curcumin|melatonin|magnesium|zinc|calcium|iron|probiotics?|collagen|ginkgo|ginseng|"
    r"coq ?10|glucosamine|biotin|b ?12|herbal|cure\w*|treat\w*|heals?|guarantee\w*|promise\w*|definitely will|"
    r"will (?:add|give you|make you live|prevent|reverse|fix)|prevents?|reverses?|"
    r"stop taking|start taking|increase your|decrease your|percent|percentage|"
    r"chance of|risk of dying|as an ai|language model|weigh\w*|pounds?|lbs?|kilos?|kg|"
    r"slim\w*|shed\w*|fat|obes\w*|bmi|diet\w*|calories|creatine|elderberry|echinacea|cbd|"
    r"ashwagandha|protein (?:powders?|shakes?|bars?)|garlic pills?|st john's wort|"
    r"energy (?:drinks?|shots?)|pre[- ]?workout|caffeine\w*|stimulants?|"
    r"(?:add|adds|adding|gain)\w* (?:\w+ ){0,3}to your life|will feel|"
    r"belly|tummy|waist\w*|los(?:e|ing) (?:a (?:bit|little) of |some )?weight|"
    r"january|february|march|april|may|june|july|august|september|october|november|"
    r"december|monday|tuesday|wednesday|thursday|friday|saturday|sunday|spring|summer|"
    r"autumn|winter|tomorrow|next (?:week|month)|by the end)\b"
    r"|%|https?://|www\.",
    re.I,
)
# A gentle mention of a well-known, low-risk supplement is fine, with no dose or brand and a
# pointer to the doctor or pharmacist. Any other supplement or vitamin is blocked.
GENTLE_SUPPLEMENT = re.compile(r"\b(?:vitamin d|multi ?vitamin|fib(?:er|re))\b", re.I)
ANY_SUPPLEMENT = re.compile(r"\b(?:supplements?|vitamins?|multi ?vitamins?)\b", re.I)
DOCTOR_POINTER = re.compile(
    r"\b(?:check|ask|talk|speak)\w*\b[^.]{0,30}\b(?:doctor|pharmacist)\b", re.I
)
NUMBER_WORDS = re.compile(
    r"\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|"
    r"fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|"
    r"sixty|seventy|eighty|ninety|hundred|thousand|dozen|half|twice|double|triple)\b",
    re.I,
)


def _numbers(text: str) -> set[str]:
    return set(re.findall(r"\d+(?:\.\d+)?", text))


def safe_line(line: object, facts_text: str, *, max_length: int = 400) -> bool:
    """Short, plain, no blocked words, and every number already in the facts."""
    if not isinstance(line, str):
        return False
    line = line.strip()
    if not line or len(line) > max_length or "\n" in line:
        return False
    if BLOCKED.search(line):
        return False
    if ANY_SUPPLEMENT.search(GENTLE_SUPPLEMENT.sub(" ", line)):
        return False
    if GENTLE_SUPPLEMENT.search(line) and not DOCTOR_POINTER.search(line):
        return False
    if _numbers(line) - _numbers(facts_text):
        return False
    # Spelled-out numbers count too: only those the facts already hold.
    said = {word.lower() for word in NUMBER_WORDS.findall(line)}
    return said <= {word.lower() for word in NUMBER_WORDS.findall(facts_text)}

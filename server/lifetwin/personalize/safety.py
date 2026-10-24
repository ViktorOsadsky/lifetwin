"""Every outside-AI line is checked before Mochi says it; a failed check uses the template.

The check refuses medical claims and advice (years gained, dates, diagnoses, medicines,
doses, supplements, promises), percentages, links, and any number the facts do not hold.
"""

import re

BLOCKED = re.compile(
    r"\b(?:years?|life ?span|life expectancy|live longer|longevity|death|die|dying|date|"
    r"diagnos\w*|prescri\w*|medicat\w*|medicine\w*|pills?|tablets?|doses?|dosage|dosing|"
    r"mg|mcg|milligrams?|iu|supplements?|vitamins?|multi ?vitamins?|fish oil|omega|turmeric|"
    r"curcumin|melatonin|magnesium|zinc|calcium|iron|probiotics?|collagen|ginkgo|ginseng|"
    r"coq ?10|glucosamine|biotin|b ?12|herbal|cure\w*|guarantee\w*|promise\w*|definitely will|"
    r"will (?:add|give you|make you live|prevent|reverse|fix)|prevents?|reverses?|"
    r"stop taking|start taking|increase your|decrease your|percent|percentage|"
    r"chance of|risk of dying|as an ai|language model|weight loss|lose weight|gain weight|diet)\b"
    r"|%|https?://|www\.",
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
    return _numbers(line) <= _numbers(facts_text)

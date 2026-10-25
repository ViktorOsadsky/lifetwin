"""Safety gates for anything a person says or writes into a habit.

Emergencies reuse the shared check (``onboarding.intents.emergency``) and its fixed
line. The habit gates add what habits need: no supplements or "energy" products,
no restricting or purging food, no medicines or doses, and no alcohol advice. A gate
answers with a fixed reply; nothing the person said is echoed or logged.
"""

import re
from typing import Literal

from lifetwin.onboarding.intents import EMERGENCY_MESSAGE, emergency
from lifetwin.onboarding.parsing import normalize_text

SafetyKind = Literal["emergency", "eating_care", "supplement", "medical", "alcohol"]

# Restricting, compensating or purging food. Food habits only ever add something.
EATING_CARE = re.compile(
    r"\bskip(?:ping|ped)? (?:a |my |the |all )?(?:meals?|breakfast|lunch|dinner|food|eating)\b|"
    r"\b(?:stop|quit|stopped|avoid|avoiding) eating\b|\b(?:not|don't|do not|won't|never) eat(?:ing)?\b|"
    r"\beat(?:ing)? (?:less|nothing|only|very little|as little)\b|\bno (?:food|eating)\b|"
    r"\bstarv\w*|\bfast(?:ing|ed)\b|\bintermittent fast\w*|\b(?:do|doing|start) a fast\b|"
    r"\bfast (?:until|till|for (?:a |the |\d+ |whole ))|\bcrash diet\w*|\bdieting\b|\bon a diet\b|"
    r"\bcalorie\w*|\bcut (?:out|down on|back on) (?:carbs?|sugar|fats?|food|snacks?|sweets|bread|meals?)\b|"
    r"\bno (?:carbs?|sugar|sweets|snacks|bread|fats?)\b|\bonly (?:water|juice|liquids?)\b|"
    r"\b(?:detox|cleanse)\w*|\blaxatives?\b|\bdiuretics?\b|\bdiet pills?\b|\bappetite suppress\w*|"
    r"\bpurg\w*|\bthrow(?:ing)? up\b|\bthrew up\b|\bvomit\w*|\bmake myself (?:sick|throw up|vomit)\b|"
    r"\bearn(?:ing)? (?:my |the )?(?:food|meals?|dinner|lunch|dessert|treats?)\b|"
    r"\bburn (?:it |that |them )?off\b|\bmake up for (?:eating|what i ate|food|dinner|lunch)\b|"
    r"\b(?:lose|losing|drop|dropping) (?:weight|pounds|lbs|kilos|kg)\b|\bweight loss\b|"
    r"\bhate (?:my|how my) (?:body|stomach|thighs|belly)\b|\b(?:too|so|look|looking|feel|feeling) fat\b|"
    r"\bbody shape\b|\bbefore and after\b|\bthinner\b|\bskinn(?:y|ier)\b|\bthigh gap\b"
)
# Supplements and "energy" products, including stimulants. Coffee itself is an anchor
# ("after my morning coffee") and is not blocked.
SUPPLEMENT = re.compile(
    r"\bsupplement\w*|\bvitamins?\b|\bmultivitamins?\b|\bprotein (?:powder|shakes?|bars?)\b|"
    r"\bcreatine\b|\bpre ?-?workouts?\b|\benergy (?:drinks?|shots?|gels?|pills?)\b|"
    r"\bred ?bull\b|\bmonster energy\b|\bcaffeine (?:pills?|tablets?|gum|powder)\b|"
    r"\bfat burners?\b|\bmelatonin\b|\bmagnesium\b|\bfish oil\b|\bomega ?-?3s?\b|\bcollagen\b|"
    r"\bashwagandha\b|\bnootropics?\b|\bgummies\b|\bcbd\b|\bkratom\b|\bbcaas?\b|\bzinc\b|"
    r"\biron tablets?\b|\bherbal (?:pills?|remed\w*)\b|\bstimulants?\b"
)
MEDICAL = re.compile(
    r"\bdos(?:e|es|age|ing)\b|\b\d+ ?mg\b|\bmilligrams?\b|\bmedications?\b|\bmedicines?\b|"
    r"\bmeds\b|\bpills?\b|\btablets?\b|\binsulin\b|\bprescriptions?\b|\bantidepressants?\b|"
    r"\bsleeping pills?\b|\bstatins?\b|\binhaler\b"
)
ALCOHOL = re.compile(
    r"\balcohol\w*|\bwine\b|\bbeers?\b|\bcocktails?\b|\bvodka\b|\bwhiske?y\b|\bbooze\b|"
    r"\bgin\b|\btequila\b|\brum\b|\bliquor\b|\bnightcap\b|\bdrunk\b|\bhangover\b"
)

REPLIES: dict[SafetyKind, str] = {
    "emergency": EMERGENCY_MESSAGE,
    "eating_care": (
        "Thank you for telling me. I don't make habits about eating less, skipping meals, "
        "weight, or making up for food. Worries about food or your body are worth talking "
        "over with a doctor or someone you trust. I'm here whenever you'd like a small, "
        "kind habit instead."
    ),
    "supplement": (
        "I can't suggest supplements or energy products like energy drinks, pre-workout or "
        "caffeine pills. A pharmacist or doctor can help with those. We can pick an everyday "
        "habit instead."
    ),
    "medical": (
        "I can't help with medicines or doses. Your doctor or pharmacist is the right person "
        "for that. We can pick an everyday habit instead."
    ),
    "alcohol": (
        "I don't give advice about alcohol. A doctor can help with that. We can pick an "
        "everyday habit instead."
    ),
}


def _words(text: str) -> str:
    lowered = normalize_text(text).lower().replace("’", "'")
    return " ".join(re.sub(r"[^\w'\s-]", " ", lowered).split())


def check(text: str) -> SafetyKind | None:
    """The first gate a text trips, most serious first; None when it is fine."""
    if emergency(text):
        return "emergency"
    words = _words(text)
    for kind, pattern in (
        ("eating_care", EATING_CARE),
        ("supplement", SUPPLEMENT),
        ("medical", MEDICAL),
        ("alcohol", ALCOHOL),
    ):
        if pattern.search(words):
            return kind
    return None


def first_stop(texts: list[str]) -> SafetyKind | None:
    """The gate that must stop a proposal: an emergency, then food worries."""
    kinds = [check(text) for text in texts]
    for kind in ("emergency", "eating_care"):
        if kind in kinds:
            return kind
    return None

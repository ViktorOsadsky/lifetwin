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


def _any(*parts: str) -> re.Pattern[str]:
    return re.compile("|".join(parts))


# Self-harm phrasings the shared emergency check does not cover yet; same reply.
SELF_HARM = _any(
    r"\bbetter off without me\b",
    r"\b(?:hurt|hurting|harm|harming|cut|cutting) myself\b",
    r"\bself ?-?harm\w*",
    r"\b(?:wanna|gonna) die\b",
    r"\bunalive\b",
    r"\b(?:not|never) (?:to )?wake up (?:tomorrow|again)\b",
    r"\b(?:don't|do not) want to wake up\b",
)
# Restricting, compensating or purging food, and body-image distress. Food habits
# only ever add something.
EATING_CARE = _any(
    # skipping or limiting meals
    r"\bskip(?:ping|ped|s)? (?:a |my |the |all |of )?(?:meals?|breakfast|brekkie|brekky|lunch|"
    r"dinner|tea|supper|food|eating)\b",
    r"\b(?:stop|quit|stopped|avoid|avoiding) (?:eating|snacking)\b",
    r"\b(?:not|don't|do not|won't|never) eat(?:ing)?\b",
    r"\beat(?:ing)? (?:less|nothing|only|very little|as little|half|smaller)\b",
    r"\bno (?:food|eating|breakfast|brekkie|lunch|dinner|supper|snack\w*)\b",
    r"\bonly (?:have |eat |drink )?(?:water|juice|liquids?|coffee|tea|salad|one meal)\b",
    r"\b(?:just|nothing but) (?:coffee|tea|water)\b",
    r"\bwater only\b",
    r"\bone meal a day\b|\bomad\b",
    r"\bsmaller portions?\b|\bhalf (?:my|a) (?:usual )?(?:lunch|dinner|breakfast|meal|portion)\b",
    r"\bgo(?:ing)? without (?:food|eating|meals?|breakfast|lunch|dinner)\b",
    r"\bunder \d{3,4}\b",
    r"\bmacros\b",
    r"\b(?:16|18|20|23) (?:8|6|4|1)\b",  # "16:8" fasting, after punctuation is dropped
    r"\bstarv\w*",
    r"\bfast(?:ing|ed)\b|\b(?:water|juice) fast\b|\bintermittent fast\w*|\b(?:do|doing|start) a fast\b",
    r"\bfast (?:until|till|for (?:a |the |\d+ |whole ))",
    r"\bcrash diet\w*|\bdieting\b|\bon a diet\b|\bketo\b|\blow ?-?carb\w*",
    r"\bcalorie\w*",
    r"\bcut (?:out |down on |back on |down |back )?(?:the )?(?:carbs?|sugar|fats?|food|snacks?|"
    r"sweets|bread|meals?|portions?)\b",
    r"\bno (?:carbs?|sugar|sweets|snacks|bread|fats?)\b",
    r"\blay off (?:the )?(?:sweets|snacks|carbs|biscuits|cake|chocolate|bread)\b",
    r"\bignore (?:my |the )?hunger\b|\binstead of eating\b|\bto (?:avoid|stop) (?:snacking|eating)\b",
    r"\b(?:detox|cleanse)\w*|\blaxatives?\b|\bdiuretics?\b|\bdiet pills?\b|\bappetite suppress\w*",
    # purging
    r"\bpurg\w*|\bthrow(?:ing)? up\b|\bthrew up\b|\bvomit\w*|\bmake myself (?:sick|throw up|vomit)\b",
    r"\bsick it up\b|\bbring (?:it |up )?(?:up )?(?:my |the )?(?:dinner|food|lunch|meal)\b",
    r"\bchew and spit\b",
    # compensating for food
    r"\bearn(?:ing)? (?:my |the )?(?:food|meals?|dinner|lunch|dessert|treats?)\b",
    r"\b(?:burn|run|walk|work|sweat|exercise) (?:it |that |them |this )?off\b",
    r"\bwork off\b|\b(?:balance|cancel) (?:it |that )?out\b",
    r"\bmake up for (?:eating|what i ate|food|dinner|lunch)\b",
    r"\bpunish(?:ing)? myself\b",
    r"\b(?:run|walk|exercise|train) (?:extra|more|longer) (?:if|when|because) i (?:eat|ate)\b",
    r"\b(?:don't|do not) deserve (?:to eat|food|dinner|lunch|breakfast|a meal)\b",
    # weight and body image
    r"\b(?:lose|losing|drop|dropping|shed|shedding) (?:\d+ |a few |some |the |my )?(?:belly )?"
    r"(?:weight|pounds|lbs|kilos|kg|stone|fat)\b",
    r"\bweight loss\b|\bbelly fat\b|\bslim (?:down|up)\b|\bshred(?:ding)? for\b|\bflat stomach\b",
    r"\bhate (?:my|how my|how i look|myself)\b|\bfeel(?:ing)? (?:huge|disgusting|gross)\b",
    r"\bdisgusting after eating\b",
    r"\b(?:i'm|im|i am) (?:so |too |really )?(?:fat|big|huge)\b",
    r"\b(?:ugly|gross|disgusting) and fat\b|\bfat and (?:ugly|gross|disgusting)\b",
    r"\b(?:too|so|look|looking|feel|feeling) fat\b",
    r"\bbe smaller\b|\bbody shape\b|\bbefore and after\b|\bthinner\b|\bskinn(?:y|ier)\b|\bthigh gap\b",
)
# Supplements and "energy" products, including stimulants. Coffee itself is an anchor
# ("after my morning coffee") and is not blocked.
SUPPLEMENT = _any(
    r"\bsupplement\w*|\bvit(?:amin)?s?\b(?: [a-e]\d*)?|\bvit(?:amin)? ?[a-e]\d*\b|\bb12\b",
    r"\bmultivitamins?\b|\bmy multi\b|\bprotein (?:powder|shakes?|bars?)\b|\bwhey\b",
    r"\bcrea?tine?\b|\bpre ?-?w\w*outs?\b|\benergy (?:drinks?|shots?|gels?|pills?|cans?)\b",
    r"\b(?:zero sugar|sugar ?-?free) energy\b|\bred ?bull\b|\bmonster\b|\brockstar\b|\bbang energy\b|\bcelsius\b|\bc4\b|\b5 ?hour energy\b",
    r"\bno ?-?doz\b|\badderall\b|\bmodafinil\b|\bcaffeine (?:pills?|tablets?|gum|powder)\b",
    r"\bfat burners?\b|\bmelatonin\b|\bmagnesium\b|\bfish oil\b|\bomega\w*|\bcollagen\b",
    r"\bashwagandha\b|\bnootropics?\b|\bgummies\b|\bcbd\b|\bkratom\b|\bbcaas?\b|\bzinc\b",
    r"\biron tablets?\b|\bherbal (?:pills?|remed\w*)\b|\bstimulants?\b|\belectrolytes?\b",
    r"\bcolostrum\b|\bprobiotics?\b|\bginseng\b|\btu?rmeric\b|\blion'?s mane\b|\bcapsules?\b",
)
MEDICAL = _any(
    r"\bdos(?:e|es|age|ing)\b|\b\d+ ?mg\b|\bmilligrams?\b|\bmedications?\b|\bmedicines?\b",
    r"\bmeds\b|\bpills?\b|\btablets?\b|\binsulin\b|\bprescriptions?\b|\bantidepressants?\b",
    r"\bstatins?\b|\binhaler\b|\bibuprofen\b|\bparacetamol\b|\btylenol\b|\badvil\b|\baspirin\b",
    r"\bantibiotics?\b|\bmetformin\b|\bozempic\b|\bwegovy\b|\bmounjaro\b|\bxanax\b",
    r"\bpainkillers?\b|\bsleeping (?:pills?|tablets?)\b",
)
ALCOHOL = _any(
    r"\balcohol\w*|\bwine\b|\bbeers?\b|\bcocktails?\b|\bvodka\b|\bwhiske?y\b|\bbooze\b",
    r"\bgin\b|\btequila\b|\brum\b|\bliquor\b|\bnightcap\b|\bdrunk\b|\bhangover\b|\bpints?\b",
    r"\bglass of (?:red|white|rose|bubbly|fizz)\b|\bprosecco\b|\blager\b|\bcider\b|\bchampagne\b",
    r"\bhave a drink\b|\ba drink to\b|\b(?:cut (?:back|down) on|stop|quit|less) drinking\b",
    r"\bdry january\b|\bsober\b|\bg and t\b|\bg t\b",
)

REPLIES: dict[SafetyKind, str] = {
    "emergency": EMERGENCY_MESSAGE,
    "eating_care": (
        "Thank you for telling me. I don't make habits about eating less, skipping meals "
        "or making up for food. Worries about food or your body are worth talking "
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
    words = _words(text)
    if emergency(text) or SELF_HARM.search(words):
        return "emergency"
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

"""Deterministic gates around the coach: what the person said, and any outside-AI line.

Input gates run before anything is chosen (report §7): the existing emergency line,
then exercise red flags, then fixed replies for supplements, medicines, diagnosis,
weight loss, diabetes or kidney food questions and forecast questions. None of these
paths ever calls a provider.

The output check runs on every provider line. A line passes only if it adds nothing:
no numbers or units the draft lacks, no medicine, supplement or product words, no
diagnosis, cure or causal wording, no weight talk, no guilt, comparison or dependency
wording, no links, the same placeholders, and the draft's safety words.
"""

import re

from lifetwin.onboarding.intents import emergency

_FLAGS = re.I


def _rx(*parts: str) -> re.Pattern:
    return re.compile("|".join(parts), _FLAGS)


def words(text: str) -> str:
    return " ".join(re.sub(r"[^\w'\s]", " ", text.lower().replace("’", "'")).split())


# ---------------------------------------------------------------------------
# Input gates
# ---------------------------------------------------------------------------

# New or worse but not acute (report §1): pause movement and see the doctor.
RED_FLAG = _rx(
    r"\bdizz\w*",
    r"\blight ?headed\b",
    r"\bfaint\w*",
    r"\bpassed out\b",
    r"\bblack(?:ed)? out\b",
    r"\bswell\w*|\bswollen\b",
    r"\bheart (?:is |was |keeps |has been |had been |started )?(?:racing|fluttering|pounding|skipping)\b",
    r"\bpalpitations?\b",
    r"\bshort of breath\b|\bbreathless\b",
    r"\b(?:i|i've|i have|just) (?:fell|fallen|had a fall|took a (?:fall|tumble)|tripped)\b",
    r"\bfell (?:down|over|again|today|yesterday|this|last)\b",
    r"\bnew pain\b",
    r"\b(?:pain|it|knee|hip|back)(?: is| has|'s)? (?:got |getting |gotten )?worse\b",
    r"\bwon't go away\b|\bkeeps hurting\b",
    r"\bnumb\w*",
    r"\bsudden weakness\b",
    r"\bchest (?:pain|pains|hurt|felt tight|tight|pressure)\b|\bpain in my chest\b",
    r"\b(?:recent|new) (?:surgery|operation|diagnosis)\b|\bjust had (?:surgery|an operation)\b",
)
JOINT_PAIN = _rx(
    r"\b(?:knee|knees|hip|hips|ankle|ankles|foot|feet|leg|legs|back|joint|joints)\b.{0,25}"
    r"\b(?:hurt\w*|pain\w*|sore|ach\w*|stiff)\b",
    r"\b(?:hurt\w*|pain\w*|sore|ach\w*|stiff)\b.{0,25}"
    r"\b(?:knee|knees|hip|hips|ankle|ankles|foot|feet|leg|legs|back|joint|joints)\b",
    r"\barthritis\b",
)
CLEARED = _rx(
    r"\b(?:doctor|dr|nurse|physio\w*|therapist|pt)\b.{0,30}"
    r"\b(?:said|says|told me|cleared|gave me the go ahead)\b.{0,30}"
    r"\b(?:ok|okay|fine|alright|all right|go ahead|cleared|safe)\b",
    r"\b(?:i've|i have|i was|i've been|i got) (?:been )?cleared\b",
    r"\bcleared (?:me|to exercise)\b",
)
FORGET_ALL = _rx(
    r"\b(?:forget|delete|erase|wipe|clear)\b.{0,20}\b(?:everything|all of it|all that|it all|"
    r"all you know|all about me|what you know about me)\b",
    r"\bstop remembering\b",
)
FORGET = re.compile(r"\b(?:forget|don't remember|do not remember|delete)\b(.*)", _FLAGS)
SUPPLEMENT = _rx(
    r"\bsupplement\w*",
    r"\bvitamin\w*|\bvitamina\w*|\bmulti ?vitamin\w*",
    r"\bfish[ -]?oil\b|\bomega\b|\bcod liver\b|\bkrill\b",
    r"\bmagnesium\b|\bzinc\b|\bcalcium\b|\bpotassium\b|\biron (?:pills?|tablets?)\b",
    r"\bmelatonin\b|\bprobiotic\w*|\bturmeric\b|\bcurcumin\b|\bginkgo\b|\bginseng\b",
    r"\bst\.? john'?s wort\b|\bglucosamine\b|\bcollagen\b|\bbiotin\b|\bcoq ?10\b|\bb ?12\b",
    r"\bprotein (?:powder|shake)s?\b|\bherbal\b|\bgummies\b",
    r"\bdos(?:e|es|age|ing)\b",
)
MEDICINE = _rx(
    r"\b(?:stop|quit|skip|change|lower|raise|double|halve) (?:taking )?(?:my|the) "
    r"(?:\w+ )?(?:pills?|meds?|medicines?|medication\w*|tablets?|insulin|dose)\b",
    r"\b(?:extra|another|more|less) (?:\w+ )?(?:pills?|meds|medicine|metformin|insulin|dose)\b",
    r"\b(?:metformin|warfarin|insulin|statin|blood thinner|blood pressure pills?)\b",
    r"\bincrease my dose\b|\bdecrease my dose\b",
)
DIAGNOSIS = _rx(
    r"\bwhat (?:is|could) (?:it|this|that) be\b",
    r"\bwhat(?:'s| is) wrong with me\b",
    r"\bdo i have\b",
    r"\bis (?:it|this|that) (?:cancer|serious|a disease)\b",
    r"\bwhat is it\b",
)
WEIGHT = _rx(
    r"\blose (?:some |the )?(?:weight|pounds|lbs|kilos|\d+)",
    r"\bweight ?loss\b|\bslim down\b|\bdiet to\b|\bcrash diet\b",
    r"\bskip (?:dinner|lunch|breakfast|meals?)\b|\bfast(?:ing)?\b(?!er)",
    r"\bcalories?\b",
)
DIABETES_FOOD = _rx(
    r"\bcarbs?\b|\bcarbohydrates?\b|\bsugar\b.{0,20}\b(?:eat|have)\b|\bblood sugar\b",
    r"\bdiabet\w*\b.{0,40}\b(?:eat|food|diet|meal)\w*",
    r"\b(?:eat|food|diet|meal)\w*\b.{0,40}\bdiabet\w*",
)
KIDNEY = _rx(r"\bkidney\w*|\bdialysis\b|\brenal\b")
FORECAST = _rx(
    r"\bwhen (?:will|am) i (?:going to )?die\b",
    r"\bhow (?:long|many years) (?:do|will|have) i\b",
    r"\bhow many (?:more )?years\b",
    r"\blive longer\b|\blife expectancy\b|\blifespan\b",
    r"\badd (?:\w+ )?years\b|\byears (?:to my life|will it add)\b",
)
WEATHER_INDOORS = _rx(r"\b(?:cold|rain\w*|wet|icy|ice|snow\w*|hot|heat|storm\w*|windy|dark)\b")
NO_TIME = _rx(r"\bno time\b|\bbusy\b|\bran out of time\b|\btoo long\b|\bnot enough time\b")


def is_emergency(text: str | None) -> bool:
    return bool(text) and emergency(text)


def red_flag(text: str | None) -> bool:
    return bool(text) and bool(RED_FLAG.search(words(text)))


def joint_pain(text: str | None) -> bool:
    return bool(text) and bool(JOINT_PAIN.search(words(text)))


# ---------------------------------------------------------------------------
# Output check for provider lines
# ---------------------------------------------------------------------------

NUMBER_WORDS = re.compile(
    r"\b(?:zero|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|"
    r"fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|"
    r"seventy|eighty|ninety|hundred|thousand|million|dozen|half|double|twice|triple|once)\b",
    _FLAGS,
)
UNITS = re.compile(
    r"\b(?:mg|mcg|ug|µg|iu|i\.u|units?|grams?|g|kg|kilos?|kilograms?|lbs?|pounds?|ounces?|oz|"
    r"kcal|cals?|calories?|liters?|litres?|ml|cups?|glasses|servings?|portions?|percent|"
    r"steps|miles?|km|reps|sets|hours?|days?|weeks?|months?|years?|bpm)\b|%",
    _FLAGS,
)
BLOCKED = _rx(
    # Supplements, medicines and products (a tripwire lexicon, not a complete list).
    r"\bsupplement\w*|\bvitamin\w*|\bmulti ?vitamin\w*|\bfish[ -]?oil\b|\bomega\w*|\bcod liver\b",
    r"\bkrill\b|\bmagnesium\b|\bzinc\b|\bcalcium\b|\biron\b|\bpotassium\b|\bmelatonin\b",
    r"\bprobiotic\w*|\bturmeric\b|\bcurcumin\b|\bginkgo\b|\bginseng\b|\bst\.? john'?s\b",
    r"\bwort\b|\bglucosamine\b|\bchondroitin\b|\bcollagen\b|\bbiotin\b|\bcoq ?10\b|\bb ?12\b",
    r"\bfolic\b|\bniacin\b|\bechinacea\b|\belderberry\b|\bashwagandha\b|\bcreatine\b",
    r"\bketo\w*|\bcapsules?\b|\bpills?\b|\btablets?\b|\bsoftgels?\b|\bgumm(?:y|ies)\b",
    r"\bpowders?\b|\bshakes?\b|\bherb(?:al|s)?\b|\bnicotine\b|\bpatch(?:es)?\b",
    r"\bmetformin\b|\binsulin\b|\bwarfarin\b|\bcoumadin\b|\beliquis\b|\bapixaban\b",
    r"\bxarelto\b|\bstatins?\b|\b\w+statin\b|\blipitor\b|\bcrestor\b|\baspirin\b",
    r"\bibuprofen\b|\badvil\b|\bmotrin\b|\bnaproxen\b|\baleve\b|\btylenol\b|\bacetaminophen\b",
    r"\bparacetamol\b|\blisinopril\b|\blosartan\b|\bamlodipine\b|\bmetoprolol\b",
    r"\bhydrochlorothiazide\b|\bfurosemide\b|\blasix\b|\blevothyroxine\b|\bsynthroid\b",
    r"\bomeprazole\b|\bprilosec\b|\bnexium\b|\bppis?\b|\bprednisone\b|\bgabapentin\b",
    r"\bsertraline\b|\bzoloft\b|\bprozac\b|\bfluoxetine\b|\bssris?\b|\bdigoxin\b",
    r"\bozempic\b|\bsemaglutide\b|\bwegovy\b|\bmounjaro\b|\btirzepatide\b|\bjardiance\b",
    r"\bglipizide\b|\bopioids?\b|\boxycodone\b|\btramadol\b|\bblood thinners?\b",
    r"\bmedicat\w*|\bmedicines?\b|\bmeds\b|\bdrugs?\b|\bprescri\w*|\bdos(?:e|es|age|ing)\b",
    r"\bbrands?\b|\bbuy\w*|\bpurchas\w*|\border\w*|\bamazon\b|\bwalmart\b|\bcostco\b",
    r"\bstores?\b|\bshop\w*|\bproducts?\b|\bsale\b|\bdiscount\w*|\bcoupons?\b|\bcode\b",
    # Diagnosis, treatment and medical claims.
    r"\byou have (?:a |an )?\w*\s?(?:disease|condition|arthritis|diabetes|syndrome|"
    r"deficien\w*|disorder|infection|injury|osteo\w*|cancer)\b",
    r"\bdiagnos\w*|\bcur(?:e|es|ed|ing)\b|\btreat(?:s|ed|ing|ment)?\b|\bheal(?:s|ing)?\b",
    r"\bstop taking\b|\bstart taking\b|\bincrease your\b|\bdecrease your\b|\bdeficien\w*",
    r"\bsymptom\w*|\bsign of\b|\binfection\b|\bdisease\b",
    # Causal and longevity claims.
    r"\blive longer\b|\blonger life\b|\blife ?span\b|\blife expectancy\b|\blongevity\b",
    r"\byears?\b|\bprevent\w*|\brevers\w*|\blower\w* your risk\b|\breduc\w* (?:your )?risk\b",
    r"\brisk of\b|\bdie\b|\bdying\b|\bdeath\b|\bmortality\b|\bsurviv\w*|\bguarantee\w*",
    r"\bproven\b|\bpromise\w*|\bwill (?:make|keep|give|add|fix|protect)\b|\bensures?\b",
    r"\bbecause of (?:this|that)\b|\bclinically\b|\bscientifically\b",
    # Weight and diets (weight is never a lever).
    r"\bweigh\w*|\bslim\w*|\bburn\w*|\bfat\b|\bfasting\b|\bfast\b|\bdetox\w*|\bcleanse\w*",
    r"\bdiet(?:s|ing)?\b|\bcarb\w*|\bsugar\w*|\bskip (?:a |your )?(?:meals?|dinner|lunch)\b",
    # Guilt, shame, comparison and dependency.
    r"\bmiss(?:ed|ing)?\b|\bfail\w*|\bshould(?:n't| not)? have\b|\blazy\b|\bdisappoint\w*",
    r"\byou didn't\b|\byou did not\b|\bstreak\w*|\bbehind\b|\bashamed\b|\bshame\w*",
    r"\bguilt\w*|\bno excuses?\b|\bmust\b|\byou need to\b|\byou have to\b|\bhave got to\b",
    r"\bother people\b|\bothers your age\b|\beveryone else\b|\bpeople your age\b",
    r"\bcompared? (?:to|with)\b|\bsad if\b|\bmiss you\b|\bdon't leave\b|\bonly friend\b",
    r"\bneed me\b|\bwithout me\b|\blet (?:me|yourself) down\b|\btry harder\b|\bfinally\b",
    r"\bwhy didn't\b|\bwhy haven't\b|\bpush through\b|\bno pain\b",
    # Provider tells, injected instructions and links.
    r"\bas an ai\b|\blanguage model\b|\bi'?m an ai\b|\bchatbot\b|\bsystem prompt\b",
    r"\bignore (?:all |your |previous |the )\w*|\binstructions?\b|\bjson\b",
    r"https?://|\bwww\.|\.(?:com|org|net|gov|io|ai)\b|@|\b\d{3}[-. ]\d{3}[-. ]?\d{0,4}\b",
    r"\b(?:call|text|phone)\b",
)
PLACEHOLDER = re.compile(r"\{[a-z_0-9]+\}")


def _numbers(text: str) -> set[str]:
    return set(re.findall(r"\d+(?:[.,]\d+)?", text))


FILLER = {
    "the",
    "and",
    "for",
    "you",
    "your",
    "with",
    "that",
    "this",
    "are",
    "can",
    "into",
    "onto",
    "from",
    "then",
    "when",
    "like",
    "want",
    "have",
    "has",
    "will",
    "just",
    "some",
    "today",
    "about",
    "what",
    "how",
    "been",
    "there",
    "it's",
    "you'd",
    "you're",
    "let's",
}


def _content(text: str) -> set[str]:
    """Four-letter stems of the longer words, so "walking" and "walks" match."""
    return {w[:4] for w in re.findall(r"[a-z']+", text.lower()) if len(w) >= 4 and w not in FILLER}


def _sentences(text: str) -> int:
    return len([part for part in re.split(r"[.!?]+(?:\s|$)", text.strip()) if part.strip()])


def _hits(pattern: re.Pattern, text: str) -> set[str]:
    return {match.group(0).lower() for match in pattern.finditer(text)}


def safe_line(line: object, draft: str, keep_words: tuple[str, ...] = ()) -> bool:
    """True only when ``line`` is a plain, short rewording of ``draft`` that adds nothing."""
    if not isinstance(line, str):
        return False
    text = line.strip().replace("’", "'")
    if not text or "\n" in text or "\r" in text:
        return False
    if len(text) > min(400, max(len(draft) * 2, len(draft) + 120)):
        return False
    # It must still say the same thing: not much shorter, and most content words kept.
    if len(text) < len(draft) * 0.5:
        return False
    content = _content(draft)
    if content and len(content & _content(text)) < 0.4 * len(content):
        return False
    if _sentences(text) > _sentences(draft) + 1:
        return False
    if re.search(r"[<>\[\]\\|`*#]", text):
        return False
    if not _numbers(text) <= _numbers(draft):
        return False
    lowered_draft = draft.lower()
    for pattern in (NUMBER_WORDS, UNITS, BLOCKED):
        if _hits(pattern, text) - _hits(pattern, lowered_draft):
            return False
    if set(PLACEHOLDER.findall(text)) != set(PLACEHOLDER.findall(draft)):
        return False
    if "{" in PLACEHOLDER.sub("", text) or "}" in PLACEHOLDER.sub("", text):
        return False
    # No new names: a capitalised word mid-sentence must already be in the draft.
    names = {
        word
        for sentence in re.split(r"[.!?]+\s*", text)
        for word in re.findall(r"\b[A-Z][a-z]+", " ".join(sentence.split()[1:]))
    }
    if names - set(re.findall(r"\b[A-Z][a-z]+", draft)) - {"Mochi"}:
        return False
    lowered = text.lower()
    # A callback keeps saying where it came from ("You told me ...").
    if "you told me" in lowered_draft and not re.search(
        r"\byou (?:told me|said|mentioned)\b", lowered
    ):
        return False
    return all(word.lower() in lowered for word in keep_words)


def safe_slot(value: str | None) -> bool:
    """A note's words may fill a template slot only if they are a few plain words."""
    if not value:
        return False
    if not re.fullmatch(r"[A-Za-z][A-Za-z' -]{0,40}", value) or len(value.split()) > 4:
        return False
    return not (BLOCKED.search(value) or NUMBER_WORDS.search(value) or UNITS.search(value))

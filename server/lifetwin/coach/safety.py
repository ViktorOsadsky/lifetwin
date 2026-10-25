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

# Words for supplements and medicines, shared by the input gate and the output check.
SUPPLEMENT_WORDS = (
    r"\bsupplement\w*|\bvitamin\w*|\bvitamina\w*|\bmulti ?vitamin\w*|\bvit\b|\bd3\b|\bk2\b",
    r"\bfish[ -]?oil\w*|\bomega\w*|\bcod liver\b|\bkrill\b|\bmagnesium\b|\bzinc\b|\bcalcium\b",
    r"\biron\b|\bpotassium\b|\bmelatonin\b|\bprobiotic\w*|\bturmeric\b|\bcurcumin\b",
    r"\bginkgo\b|\bginseng\b|\bst\.? john'?s\b|\bwort\b|\bglucosamine\b|\bchondroitin\b",
    r"\bcollagen\b|\bbiotin\b|\bcoq ?10\b|\bb ?12\b|\bfolic\b|\bniacin\b|\bechinacea\b",
    r"\belderberry\b|\bashwagandha\b|\bcreatine\b|\bwhey\b|\bcbd\b|\bcannabi\w*|\bhemp\b",
    r"\bensure\b|\bboost shakes?\b|\bprotein (?:powder|shake|drink)s?\b|\bherb(?:al|s)?\b",
    r"\bgumm(?:y|ies)\b|\bcapsules?\b|\bsoftgels?\b|\bkelp\b|\bspirulina\b|\bkombucha\b",
    r"\benergy (?:drinks?|shots?|gels?|chews?|bars?)\b|\bred ?bull\b|\bmonster energy\b",
    r"\bpre[ -]?workouts?\b|\bcaffeine (?:pills?|tablets?|capsules?|supplements?|powder|shots?)\b",
    r"\bcaffeinated (?:pills?|tablets?)\b|\bno[ -]?doz\b|\bpreworkout\b",
)
DRUG_WORDS = (
    r"\bmetformin\b|\binsulin\b|\bwarfarin\b|\bcoumadin\b|\beliquis\b|\bapixaban\b|\bxarelto\b",
    r"\bstatins?\b|\b\w+statin\b|\blipitor\b|\bcrestor\b|\baspirin\b|\bibuprofen\b|\badvil\b",
    r"\bmotrin\b|\bnaproxen\b|\baleve\b|\btylenol\b|\bacetaminophen\b|\bparacetamol\b",
    r"\bpainkillers?\b|\bpain ?relievers?\b|\bvoltaren\b|\bdiclofenac\b|\binhalers?\b",
    r"\blisinopril\b|\blosartan\b|\bamlodipine\b|\bmetoprolol\b|\bhydrochlorothiazide\b",
    r"\bfurosemide\b|\blasix\b|\bdiuretics?\b|\bwater pills?\b|\blevothyroxine\b|\bsynthroid\b",
    r"\bomeprazole\b|\bprilosec\b|\bnexium\b|\bppis?\b|\bantacids?\b|\bprednisone\b",
    r"\bsteroids?\b|\bgabapentin\b|\bsertraline\b|\bzoloft\b|\bprozac\b|\bfluoxetine\b",
    r"\bssris?\b|\bantidepressants?\b|\bdigoxin\b|\bozempic\b|\bsemaglutide\b|\bwegovy\b",
    r"\bmounjaro\b|\btirzepatide\b|\bjardiance\b|\bglipizide\b|\bopioids?\b|\boxycodone\b",
    r"\btramadol\b|\bblood thinners?\b|\bsleeping pills?\b|\bantibiotics?\b|\bnicotine\b",
    r"\bnicorette\b|\bchantix\b|\bvarenicline\b|\bzyban\b|\bbupropion\b|\bvap(?:e|es|ing)\b",
    r"\be-?cig\w*|\bpatch(?:es)?\b|\blozenges?\b|\bpills?\b|\btablets?\b|\bmeds\b",
    r"\bmedicat\w*|\bmedicines?\b|\bdrugs?\b|\bprescri\w*",
)
DOSE_WORDS = (r"\bdos(?:e|es|age|ing)\b|\boverdos\w*",)

# Said now, these get the existing 911 line. The shared onboarding check catches the
# plainest phrasings; the coach adds more, because a plan must never follow them.
ACUTE = _rx(
    r"\bchest\b.{0,30}\b(?:pain|pains|pressure|discomfort|tight\w*|heavy|heaviness|hurt\w*|"
    r"squeez\w*|crush\w*|ach\w*|burn\w*)\b",
    r"\b(?:pain|pressure|tightness|heaviness|discomfort)\b.{0,15}\bchest\b",
    r"\belephant\b.{0,20}\bchest\b|\bchest\b.{0,40}\belephant\b",
    r"\b(?:can't|cannot|can not|can barely|could barely|hardly|struggling to|trouble) "
    r"(?:breathe|breathing|catch my breath|get (?:my )?breath)\b",
    r"\bgasping\b|\bchoking\b|\bturning blue\b",
    r"\bface (?:is )?(?:drooping|droopy|numb)\b|\bslurr\w*|\bwords (?:come|are coming) out wrong\b",
    r"\b(?:can't|cannot) (?:move|feel|lift) my (?:left |right )?(?:arm|leg|hand|face|side)\b",
    r"\b(?:can't|cannot) (?:speak|talk|get my words out)\b|\bsudden(?:ly)? (?:numb|weak|confus)\w*",
    r"\bworst headache\b|\bpassed out\b|\bunconscious\b|\bwon't wake\b",
    r"\b(?:hurt|harm|kill)(?:ing)? myself\b|\bwish (?:i was|i were|i'd be) dead\b",
    r"\b(?:end|ending) (?:things|it all|my life)\b|\b(?:take|took|taking|swallow\w*) all "
    r"(?:my|the|of my) (?:pills|tablets|medicines?|meds)\b|\boverdos\w*",
    r"\b(?:want|wanna|wants) to die\b|\bbetter off dead\b|\bno reason to live\b|\bsuicid\w*",
    r"\b(?:don't|do not) want to (?:live|be here|wake up)\b",
)
# "Had chest pain years ago": clearly the past, so a doctor line rather than 911.
LONG_AGO = _rx(r"\b(?:years? ago|in (?:19|20)\d\d|last year|years back|when i was (?:young|a))\b")

# New or worse but not acute (report §1): pause movement and see the doctor.
RED_FLAG = _rx(
    r"\bdizz\w*|\blight ?headed\w*|\bwoozy\b|\bvertigo\b|\b(?:room|head) (?:was |is |keeps )?spinning\b",
    r"\bfaint\w*|\bblack(?:ed)? out\b|\bnear(?:ly)? passed out\b",
    r"\bswell\w*|\bswollen\b|\bpuffy\b|\bpuffed up\b",
    r"\bheart(?:'s| is| was| keeps| has been| had been| started| kept)? (?:\w+ )?(?:racing|"
    r"fluttering|pounding|skipping|jumping|beating (?:really |very |so )?(?:fast|hard))\b",
    r"\bskipped a beat\b|\birregular (?:heart ?beat|pulse)\b|\bpalpitations?\b|\bafib\b",
    r"\bshort of breath\b|\bbreathless\b|\b(?:really|very|so|badly|get|got|getting) out of breath\b",
    r"\bout of breath (?:walking|easily|quickly|on the stairs)\b",
    r"\b(?:i|i've|i have|just|she|he) (?:fell(?! asleep| in love| for\b| behind| apart| short| "
    r"through| off the wagon)|fallen(?! asleep| in love)|had a fall|took a (?:fall|tumble)|"
    r"tripped|slipped)\b",
    r"\bfell (?:down|over|again|today|yesterday|this|last)\b|\bkeep falling\b|\bfalling a lot\b",
    r"\b(?:legs?|knees?) (?:gave|give|gives|giving) (?:out|way)\b|\blost my (?:balance|footing)\b",
    r"\bnew pain\b|\bnever had before\b|\bnew (?:lump|sore)\b",
    r"\b(?:pain|it|knee|hip|back|ankle|foot|leg)(?: is| has|'s)? (?:got |getting |gotten )?worse\b",
    r"\bhurts? (?:a lot )?more (?:than|today|now)\b|\bworse (?:than|today|now)\b",
    r"\bwon't go away\b|\bkeeps hurting\b|\bstill hurts\b",
    r"\bnumb(?:ness)?\b|\btingl\w*|\bsudden weakness\b",
    r"\bchest\b",
    r"\b(?:recent|new) (?:surgery|operation|diagnosis)\b|\bjust had (?:surgery|an operation)\b",
    r"\bsores? (?:that )?(?:won't|will not|don't|do not) heal\b",
)
NEGATED = re.compile(
    r"\b(?:not|no longer|no more|never|isn't|wasn't|aren't|haven't|hasn't|didn't)\b"
    r"(?: \w+){0,2} $"
)
JOINT_PAIN = _rx(
    r"\b(?:knee|knees|hip|hips|ankle|ankles|foot|feet|leg|legs|back|joint|joints)\b.{0,25}"
    r"\b(?:hurt\w*|pain\w*|sore|ach\w*|stiff|killing me|acting up|playing up)\b",
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
SUPPLEMENT = _rx(*SUPPLEMENT_WORDS)
DOSE = _rx(
    r"\bdos(?:e|es|age|ing)\b|\bhow much (?:should|can|do) i take\b|\bhow many \w* ?to take\b"
)
MEDICINE = _rx(
    *DRUG_WORDS,
    r"\b(?:stop|quit|skip|change|lower|raise|double|halve) (?:taking )?(?:my|the) "
    r"(?:\w+ )?(?:pills?|meds?|medicines?|medication\w*|tablets?|insulin|dose)\b",
)
DIAGNOSIS = _rx(
    r"\bwhat (?:is|could) (?:it|this|that) be\b",
    r"\bwhat(?:'s| is) wrong with me\b",
    r"\bdo i have\b",
    r"\bis (?:it|this|that) (?:cancer|serious|a disease)\b",
    r"\bwhat is it\b",
)
WEIGHT = _rx(
    r"\blose (?:some |the |a little )?(?:weight|pounds|lbs|kilos|inches|\d+|\w+ pounds)",
    r"\bweight ?loss\b|\bslim down\b|\bdiet to\b|\bcrash diet\b|\bbelly\b|\bwaistline\b",
    r"\bskip (?:dinner|lunch|breakfast|meals?)\b|\bintermittent fasting\b",
    r"\bfasting\b(?! for (?:blood|a test|my test|labs?|bloodwork))|\bcalories?\b",
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


def _clauses(text: str) -> list[str]:
    return [c for c in re.split(r"[.;!?]|\bbut\b", words_keep(text)) if c.strip()]


def words_keep(text: str) -> str:
    """Lower-case words, keeping sentence marks so clauses can be split."""
    return " ".join(re.sub(r"[^\w'\s.;!?]", " ", text.lower().replace("’", "'")).split())


def _hit(pattern: re.Pattern, clause: str) -> bool:
    """A match that is not negated just before it ("I'm not dizzy anymore")."""
    for match in pattern.finditer(clause):
        if not NEGATED.search(clause[: match.start()]):
            return True
    return False


def is_emergency(text: str | None) -> bool:
    if not text:
        return False
    if emergency(text):
        return True
    return any(_hit(ACUTE, c) and not LONG_AGO.search(c) for c in _clauses(text))


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    return any(_hit(RED_FLAG, c) or _hit(ACUTE, c) for c in _clauses(text))


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


def _sentences(text: str) -> int:
    return len([part for part in re.split(r"[.!?]+(?:\s|$)", text.strip()) if part.strip()])


def _hits(pattern: re.Pattern, text: str) -> set[str]:
    return {match.group(0).lower() for match in pattern.finditer(text)}


LEXICON = _rx(
    *SUPPLEMENT_WORDS,
    *DRUG_WORDS,
    *DOSE_WORDS,
    r"\bdementia\b|\balzheimer\w*|\bstrokes?\b|\bcancer\w*|\bheart attacks?\b|\bhypertensi\w*",
    r"\barthritis\b|\bosteo\w*|\bdiabet\w*|\bcholesterol\b|\bblood pressure\b|\bblood sugar\b",
    r"\bbelly\b|\bwaist\w*|\binches\b|\btrim\w*|\bshrink\w*|\bthinner\b|\bskinny\b|\bobes\w*",
    r"\bprotect\w*|\bkeeps? \w+ away\b|\bavoid\w*|\bstays? strong\b",
    r"\bskipp\w*|\bslack\w*|\bchain\b|\bdon't break\b|\bkeep it up or\b",
)
# The only new words a rewording may bring: warm, plain fillers. Everything else must
# already be in the draft, so a provider cannot add an exercise, a food, a product, a
# condition or a claim, however it is spelled.
WARM = {
    "about",
    "again",
    "alright",
    "also",
    "amazing",
    "brilliant",
    "bright",
    "calm",
    "calmly",
    "cheerful",
    "chat",
    "chatting",
    "close",
    "comfortable",
    "comfy",
    "cozy",
    "could",
    "dear",
    "doing",
    "done",
    "easily",
    "easier",
    "easy",
    "enjoy",
    "enjoying",
    "fancy",
    "fantastic",
    "favorite",
    "favourite",
    "feel",
    "feeling",
    "fine",
    "fresh",
    "friendly",
    "gave",
    "gentle",
    "gently",
    "getting",
    "give",
    "giving",
    "glad",
    "going",
    "good",
    "grand",
    "great",
    "happy",
    "have",
    "having",
    "here",
    "idea",
    "ideas",
    "just",
    "keep",
    "keeping",
    "kind",
    "kindly",
    "little",
    "lovely",
    "made",
    "make",
    "making",
    "maybe",
    "might",
    "moment",
    "nearby",
    "nice",
    "nicely",
    "okay",
    "perhaps",
    "plan",
    "pleasant",
    "please",
    "proud",
    "quick",
    "ready",
    "really",
    "said",
    "short",
    "simple",
    "since",
    "slow",
    "slowly",
    "small",
    "smile",
    "sound",
    "sounds",
    "start",
    "steady",
    "step",
    "still",
    "stroll",
    "sure",
    "take",
    "taking",
    "thing",
    "things",
    "time",
    "together",
    "took",
    "warm",
    "well",
    "went",
    "while",
    "wonderful",
    "worth",
    "would",
    "yourself",
    "hello",
    "hey",
    "friend",
    "cheer",
    "cheering",
    "mochi",
    "got",
    "you've",
    "one",
    "get",
    "let",
    "bit",
    "lot",
    "now",
    "yes",
    "all",
    "way",
    "day",
    "good morning",
    "morning",
}
# Plain function words seen in live rewordings ("stick with that", "till the show is back").
WARM |= {"stick", "till", "until", "shall", "down", "around", "along", "hear", "back", "lots"}
FILLER = {
    "the",
    "and",
    "for",
    "you",
    "your",
    "yours",
    "with",
    "that",
    "this",
    "these",
    "those",
    "are",
    "can",
    "into",
    "onto",
    "from",
    "then",
    "when",
    "like",
    "want",
    "has",
    "will",
    "some",
    "today",
    "what",
    "which",
    "how",
    "been",
    "there",
    "their",
    "them",
    "they",
    "it's",
    "you'd",
    "you're",
    "you'll",
    "let's",
    "i'm",
    "i'd",
    "here's",
    "that's",
    "there's",
    "very",
    "each",
    "every",
    "where",
    "were",
    "was",
    "our",
    "its",
    "just",
    "than",
    "too",
    "much",
}
NEGATIONS = re.compile(
    r"\b(?:no|not|never|without|nothing|none|skip|stop|avoid|instead|even|unless|rather|"
    r"don't|doesn't|won't|can't|cannot|shouldn't|needn't|isn't|aren't|let go)\b"
)


def _stem(word: str) -> str:
    for suffix in ("ing", "ed", "es", "s", "ly"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[: -len(suffix)]
    return word


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z][a-z']*", PLACEHOLDER.sub(" ", text.lower()))


def _vocab(text: str) -> set[str]:
    return {_stem(w) for w in _tokens(text)}


def _content(text: str) -> set[str]:
    return {_stem(w) for w in _tokens(text) if len(w) >= 4 and w not in FILLER and w not in WARM}


def safe_line(line: object, draft: str, keep_words: tuple[str, ...] = ()) -> bool:
    """True only when ``line`` is a plain, short rewording of ``draft`` that adds nothing."""
    if not isinstance(line, str):
        return False
    text = line.strip().replace("’", "'")
    lowered, lowered_draft = text.lower(), draft.lower()
    if not text or "\n" in text or "\r" in text:
        return False
    if not len(draft) * 0.5 <= len(text) <= min(400, max(len(draft) * 2, len(draft) + 120)):
        return False
    if _sentences(text) > _sentences(draft) + 1:
        return False
    if re.search(r"[<>\[\]\\|`*#@/]", text):
        return False
    # Words: nothing new but warm fillers, and most of the draft's content kept.
    allowed = _vocab(draft) | {_stem(w) for w in WARM | FILLER}
    if any(_stem(w) not in allowed for w in _tokens(text) if len(w) >= 3):
        return False
    content = _content(draft)
    if content and len(content & _content(text)) < 0.5 * len(content):
        return False
    if len(NEGATIONS.findall(lowered)) > len(NEGATIONS.findall(lowered_draft)):
        return False
    if not _numbers(text) <= _numbers(draft):
        return False
    for pattern in (NUMBER_WORDS, UNITS, BLOCKED, LEXICON):
        if _hits(pattern, text) - _hits(pattern, lowered_draft):
            return False
    if sorted(PLACEHOLDER.findall(text)) != sorted(PLACEHOLDER.findall(draft)):
        return False
    if "{" in PLACEHOLDER.sub("", text) or "}" in PLACEHOLDER.sub("", text):
        return False
    # A callback keeps saying where it came from ("You told me ...").
    if "you told me" in lowered_draft and not re.search(
        r"\byou (?:told me|said|mentioned)\b", lowered
    ):
        return False
    return all(re.search(rf"\b{re.escape(word.lower())}\b", lowered) for word in keep_words)


def safe_slot(value: str | None) -> bool:
    """A note's words may fill a template slot only if they are a few plain words."""
    if not value:
        return False
    if not re.fullmatch(r"[A-Za-z][A-Za-z' -]{0,40}", value) or len(value.split()) > 4:
        return False
    return not (
        BLOCKED.search(value)
        or LEXICON.search(value)
        or NUMBER_WORDS.search(value)
        or UNITS.search(value)
    )

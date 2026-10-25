"""The fixed, cited catalogue Mochi picks from. Nothing outside it is ever suggested.

Sources are the ones checked in docs/research/agentic-features.md (2026-10-24), plus
the on-device package's wellness-card sources for sleep and smoking. None of this has
had professional review yet; every card says so (``reviewed_by``).
"""

from dataclasses import dataclass, field, replace

Source = tuple[str, str]

CDC_OLDER: Source = (
    "CDC: Physical activity guidelines for older adults",
    "https://cdc.gov/physical-activity-basics/guidelines/older-adults.html",
)
CDC_ADULTS: Source = (
    "CDC: Physical activity guidelines for adults",
    "https://cdc.gov/physical-activity-basics/guidelines/adults.html",
)
NHS_ADULTS: Source = (
    "NHS: Physical activity guidelines for adults aged 19 to 64",
    "https://www.nhs.uk/live-well/exercise/exercise-guidelines/physical-activity-guidelines-for-adults-aged-19-to-64/",
)
DGA: Source = (
    "Dietary Guidelines for Americans, 2020-2025",
    "https://www.dietaryguidelines.gov/sites/default/files/2021-03/Dietary_Guidelines_for_Americans-2020-2025.pdf",
)
NHS_WATER: Source = (
    "NHS: Water, drinks and your health",
    "https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/",
)
NIDDK_DIABETES_FOOD: Source = (
    "NIDDK: Diet, eating and physical activity with diabetes",
    "https://www.niddk.nih.gov/health-information/diabetes/overview/diet-eating-physical-activity",
)
NIDDK_KIDNEY_FOOD: Source = (
    "NIDDK: Eating and nutrition for chronic kidney disease",
    "https://www.niddk.nih.gov/health-information/kidney-disease/chronic-kidney-disease-ckd/eating-nutrition",
)
CDC_COUNTS: Source = (
    "CDC: What counts as physical activity for older adults",
    "https://cdc.gov/physical-activity-basics/adding-older-adults/what-counts.html",
)
WHO_2020: Source = (
    "WHO 2020 guidelines on physical activity and sedentary behaviour",
    "https://iris.who.int/items/2abc9ed0-2a55-4a07-a65f-ab4b7c412ecc",
)
USPSTF_FALLS: Source = (
    "USPSTF 2024: exercise to prevent falls in older adults (AAFP summary)",
    "https://aafp.org/pubs/afp/issues/2024/0800/uspstf-fall-prevention-older-adults.html",
)
NIA_OA: Source = (
    "NIA: Osteoarthritis",
    "https://www.nia.nih.gov/health/osteoarthritis/osteoarthritis",
)
NIA_EXERCISE: Source = (
    "NIA: Exercise and physical activity for older adults",
    "https://order.nia.nih.gov/sites/default/files/2025-04/exercise-and-older-adults-nia_0.pdf",
)
STEADI_TAI_CHI: Source = (
    "CDC STEADI programmes, including Tai Chi: Moving for Better Balance",
    "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4410411/",
)
NHLBI_DASH: Source = (
    "NHLBI: Why DASH works",
    "https://internet-prod.nhlbi.nih.gov/sites/default/files/publications/WhyDASHWorks_UpdateNov20.pdf",
)
PREDIMED: Source = (
    "Harvard Nutrition Source: the PREDIMED republication",
    "https://nutritionsource.hsph.harvard.edu/2018/06/22/predimed-retraction-republication",
)
ACL_PROTEIN: Source = (
    "ACL: Nutrition needs of older adults, protein",
    "https://acl.gov/sites/default/files/nutrition/Nutrition-Needs_Protein_FINAL-2.18.20_508.pdf",
)
NIA_MEALS: Source = (
    "NIA: Healthy meal planning tips for older adults",
    "https://www.nia.nih.gov/health/healthy-eating-nutrition-and-diet/healthy-meal-planning-tips-older-adults",
)
# Checked 2026-10-24: Part B covers MNT for diabetes, kidney disease or a kidney
# transplant in the last 36 months, on a doctor's referral, at no cost if eligible.
MEDICARE_MNT: Source = (
    "Medicare: Medical nutrition therapy services",
    "https://www.medicare.gov/coverage/medical-nutrition-therapy-services",
)
NIA_SUPPLEMENTS: Source = (
    "NIA: Dietary supplements for older adults",
    "https://www.nia.nih.gov/health/vitamins-and-supplements/dietary-supplements-older-adults",
)
CDC_SLEEP: Source = ("CDC: About sleep", "https://www.cdc.gov/sleep/about/index.html")
CDC_TOBACCO: Source = ("CDC: Smoking and tobacco use", "https://www.cdc.gov/tobacco/about/")
# Checked 2026-10-24 (search summary of the AHA page; the page itself refused a fetch):
# above 180/120, wait and re-check; with symptoms call 911, without them contact a
# health care professional as soon as possible.
AHA_CRISIS: Source = (
    "AHA: Hypertensive crisis, when to call 911 for high blood pressure",
    "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/hypertensive-crisis-when-you-should-call-911-for-high-blood-pressure",
)
GAIN_FRAMING: Source = (
    "Gallagher & Updegraff 2012: gain-framed messages and prevention behaviours",
    "https://pmc.ncbi.nlm.nih.gov/articles/PMC3397368",
)


def band(age: int | None) -> str:
    """The age band that shapes wording and picks. Unknown or under 18 -> "neutral",
    which keeps the gentle set that fits anyone."""
    if age is None or age < 18:
        return "neutral"
    if age < 40:
        return "young"
    return "mid" if age < 65 else "older"


LIMITS = ("knee_pain", "walking_aid", "fall_risk", "cardio_caution", "seated_only")


@dataclass(frozen=True)
class Activity:
    id: str
    title: str
    # Spoken steps, at most three sentences; {minutes} is filled in.
    steps: str
    minutes: int
    min_minutes: int
    max_minutes: int
    component: str  # aerobic, strength, balance
    intensity: str  # light, moderate, vigorous
    counts_as: str  # the model input the minutes count toward: moderate, vigorous, none
    position: str  # seated, supported_standing, standing, water
    source: Source
    # Words a rephrasing must keep ("chair", "hold").
    keep_words: tuple[str, ...] = ()
    # The next step up once the person is at max_minutes.
    next_id: str | None = None
    # Note words that make this the person's own activity ("dog", "garden").
    anchors: tuple[str, ...] = ()
    indoor: bool = True


ACTIVITIES: dict[str, Activity] = {
    a.id: a
    for a in (
        Activity(
            "chair_march",
            "Chair marching",
            "Sit tall in a sturdy chair and march your feet in place for {minutes} minutes. "
            "Swing your arms too, if that feels good.",
            5,
            5,
            15,
            "aerobic",
            "light",
            "none",
            "seated",
            NIA_EXERCISE,
            ("chair",),
            next_id="seated_dance",
        ),
        Activity(
            "seated_leg_lifts",
            "Seated leg lifts",
            "Sit in a sturdy chair. Slowly straighten one knee, then lower it, and switch legs, "
            "for {minutes} minutes.",
            5,
            5,
            10,
            "strength",
            "light",
            "none",
            "seated",
            NIA_OA,
            ("chair",),
        ),
        Activity(
            "seated_arm_raises",
            "Seated arm raises",
            "Sitting in a chair, raise both arms out to the sides and lower them slowly, for "
            "{minutes} minutes. Two water bottles make good light weights.",
            5,
            5,
            10,
            "strength",
            "light",
            "none",
            "seated",
            CDC_COUNTS,
            ("chair",),
        ),
        Activity(
            "seated_dance",
            "Dancing in your chair",
            "Put on a song you love and dance from your chair for {minutes} minutes: arms, "
            "shoulders and feet.",
            10,
            5,
            15,
            "aerobic",
            "light",
            "none",
            "seated",
            CDC_COUNTS,
            ("chair",),
            anchors=("danc", "music"),
        ),
        Activity(
            "stationary_bike",
            "Easy exercise bike",
            "Pedal an exercise bike at an easy pace for {minutes} minutes. It is gentle on "
            "the knees.",
            10,
            5,
            20,
            "aerobic",
            "moderate",
            "moderate",
            "seated",
            NIA_OA,
            anchors=("bike", "cycl"),
        ),
        Activity(
            "water_walk",
            "Walking in the pool",
            "Walk back and forth in the shallow end of a pool for {minutes} minutes. The "
            "water is gentle on sore joints.",
            15,
            10,
            30,
            "aerobic",
            "moderate",
            "moderate",
            "water",
            CDC_COUNTS,
            anchors=("swim", "pool", "water"),
        ),
        Activity(
            "walk_short",
            "A short, flat walk",
            "Take a {minutes}-minute walk on flat ground, at a pace where you can still talk.",
            10,
            5,
            30,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_OLDER,
            next_id="walk_brisk",
            anchors=("walk", "dog", "pet"),
            indoor=False,
        ),
        Activity(
            "walk_brisk",
            "A brisk walk",
            "Walk at a brisk pace for {minutes} minutes, quick enough that talking takes a "
            "little effort.",
            20,
            15,
            40,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_OLDER,
            next_id="hill_walk",
            indoor=False,
        ),
        Activity(
            "hill_walk",
            "A hill walk or swimming laps",
            "Walk briskly up a gentle hill, or swim laps, for {minutes} minutes, hard enough "
            "that you can only say a few words at a time.",
            20,
            15,
            30,
            "aerobic",
            "vigorous",
            "vigorous",
            "standing",
            CDC_OLDER,
            indoor=False,
        ),
        Activity(
            "sit_to_stand",
            "Sit-to-stand",
            "From a sturdy chair, stand up slowly and sit back down, using the armrests if you "
            "need them. Repeat for {minutes} minutes, resting whenever you like.",
            5,
            3,
            10,
            "strength",
            "light",
            "none",
            "supported_standing",
            NIA_EXERCISE,
            ("chair",),
        ),
        Activity(
            "wall_pushups",
            "Wall push-ups",
            "Stand an arm's length from a wall with your hands on it, and slowly bend and "
            "straighten your arms for {minutes} minutes.",
            5,
            3,
            10,
            "strength",
            "light",
            "none",
            "supported_standing",
            CDC_COUNTS,
            ("wall",),
        ),
        Activity(
            "heel_raises",
            "Heel raises, holding the counter",
            "Hold a kitchen counter with both hands. Rise up onto your toes and lower slowly, "
            "for {minutes} minutes.",
            5,
            3,
            10,
            "balance",
            "light",
            "none",
            "supported_standing",
            NIA_EXERCISE,
            ("hold",),
        ),
        Activity(
            "tandem_stand",
            "Heel-to-toe stand, holding the counter",
            "Hold a kitchen counter. Stand with one foot right in front of the other, heel to "
            "toe, then switch feet, for {minutes} minutes.",
            5,
            3,
            10,
            "balance",
            "light",
            "none",
            "supported_standing",
            USPSTF_FALLS,
            ("hold",),
        ),
        Activity(
            "one_leg_stand",
            "One-leg stand",
            "Stand on one foot next to a counter, then switch feet, for {minutes} minutes. "
            "Touch the counter whenever you need to.",
            5,
            3,
            10,
            "balance",
            "light",
            "none",
            "standing",
            CDC_OLDER,
            ("counter",),
        ),
        Activity(
            "tai_chi",
            "Gentle tai chi",
            "Follow a gentle tai chi class or video for {minutes} minutes, moving slowly.",
            15,
            10,
            30,
            "balance",
            "light",
            "none",
            "standing",
            STEADI_TAI_CHI,
            anchors=("tai chi",),
        ),
        Activity(
            "gardening",
            "Gardening",
            "Spend {minutes} minutes in the garden: weeding, raking or watering. A stool or "
            "raised bed helps.",
            15,
            10,
            30,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_COUNTS,
            anchors=("garden",),
            indoor=False,
        ),
        Activity(
            "dancing",
            "Dancing to music",
            "Put on music you love and dance around the kitchen for {minutes} minutes.",
            15,
            10,
            30,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_COUNTS,
            anchors=("danc", "music"),
        ),
        Activity(
            "jog_walk",
            "A brisk walk or jog",
            "Walk briskly, or jog if you like, for {minutes} minutes, at a pace where you can "
            "still talk in short sentences.",
            20,
            15,
            40,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_ADULTS,
            anchors=("jog", "run"),
            indoor=False,
        ),
        Activity(
            "bodyweight_circuit",
            "A bodyweight circuit",
            "Go round squats, lunges, push-ups and a plank, about a minute each, for {minutes} "
            "minutes. Rest when you need to.",
            15,
            10,
            30,
            "strength",
            "vigorous",
            "vigorous",
            "standing",
            CDC_ADULTS,
            anchors=("gym", "circuit", "weights", "lift"),
        ),
        Activity(
            "cycling",
            "Cycling",
            "Ride a bike at a steady pace for {minutes} minutes, to somewhere you need to go "
            "or just for fun.",
            30,
            15,
            60,
            "aerobic",
            "moderate",
            "moderate",
            "seated",
            NHS_ADULTS,
            anchors=("bike", "cycl"),
            indoor=False,
        ),
        Activity(
            "sport_friends",
            "A sport with friends",
            "Play a sport you enjoy with friends for {minutes} minutes: football, basketball, "
            "tennis or anything that gets you moving.",
            30,
            20,
            60,
            "aerobic",
            "vigorous",
            "vigorous",
            "standing",
            CDC_ADULTS,
            anchors=("football", "soccer", "basketball", "tennis", "sport", "team"),
            indoor=False,
        ),
        Activity(
            "stairs",
            "Take the stairs",
            "Climb up and down a flight of stairs at a steady pace for {minutes} minutes, or "
            "take the stairs instead of the lift today.",
            10,
            5,
            20,
            "aerobic",
            "moderate",
            "moderate",
            "standing",
            CDC_ADULTS,
            anchors=("stair",),
        ),
        Activity(
            "swim_laps",
            "Swimming",
            "Swim at a steady pace for {minutes} minutes, resting at the wall whenever you like.",
            20,
            15,
            40,
            "aerobic",
            "moderate",
            "moderate",
            "water",
            NHS_ADULTS,
            anchors=("swim", "pool"),
            indoor=False,
        ),
        Activity(
            "strength_twice",
            "Strength work",
            "Do squats, lunges, a plank and rows with a backpack or a band for {minutes} "
            "minutes. Two days a week is a good rhythm.",
            20,
            15,
            40,
            "strength",
            "moderate",
            "none",
            "standing",
            NHS_ADULTS,
            anchors=("gym", "weights", "lift"),
        ),
        Activity(
            "mobility_flow",
            "Mobility and stretching",
            "Sit tall on a chair or a mat and slowly move your neck, shoulders, back and hips "
            "through their range for {minutes} minutes.",
            10,
            5,
            20,
            "flexibility",
            "light",
            "none",
            "seated",
            NHS_ADULTS,
            anchors=("yoga", "stretch"),
        ),
    )
}

# What each limitation rules out (report §1 table). Knee pain keeps to seated and
# water options; a walker or cane rules out unsupported balance; a fall history keeps
# balance supported; a heart or breathing caution keeps to gentle walking and light
# seated moves; seated only means seated.
UNSUPPORTED = {"one_leg_stand", "tai_chi", "dancing"}
# The younger-band picks that need steady footing, so a walker, cane or fall history rules
# them out just as it rules out the unsupported balance moves.
UNSTEADY = {
    "jog_walk",
    "bodyweight_circuit",
    "cycling",
    "sport_friends",
    "stairs",
    "swim_laps",
    "strength_twice",
}


def allowed(activity: Activity, limits: set[str], *, age: int | None) -> bool:
    if "seated_only" in limits and (
        activity.position != "seated" or activity.id in {"stationary_bike", "cycling"}
    ):
        return False
    if "knee_pain" in limits and activity.position not in {"seated", "water"}:
        return False
    if "walking_aid" in limits and (
        activity.id in UNSUPPORTED
        or activity.id in UNSTEADY
        or activity.id in {"walk_brisk", "hill_walk", "water_walk"}
    ):
        return False
    if "fall_risk" in limits and (
        activity.id in UNSUPPORTED or activity.id in UNSTEADY or activity.id == "hill_walk"
    ):
        return False
    if "cardio_caution" in limits and activity.intensity != "light" and activity.id != "walk_short":
        return False
    if activity.intensity == "vigorous" and (limits or age is None or age >= 80):
        return False
    return True


# Preference order for each activity level ("none versus any": small starts for people
# doing none; balance and strength before more walking for active people).
POOLS: dict[str, tuple[str, ...]] = {
    "none": (
        "walk_short",
        "chair_march",
        "seated_leg_lifts",
        "heel_raises",
        "seated_arm_raises",
        "water_walk",
        "stationary_bike",
        "seated_dance",
    ),
    "some": (
        "walk_short",
        "heel_raises",
        "sit_to_stand",
        "tandem_stand",
        "wall_pushups",
        "water_walk",
        "stationary_bike",
        "gardening",
        "tai_chi",
        "dancing",
        "chair_march",
        "seated_leg_lifts",
        "seated_arm_raises",
        "seated_dance",
    ),
    "active": (
        "tandem_stand",
        "sit_to_stand",
        "wall_pushups",
        "tai_chi",
        "walk_brisk",
        "hill_walk",
        "one_leg_stand",
        "water_walk",
        "gardening",
        "dancing",
        "stationary_bike",
        "heel_raises",
        "seated_arm_raises",
        "chair_march",
        "seated_leg_lifts",
    ),
}
SMALL_START_MAX = 10

# Younger bands lead with their own picks and fall back to the seated and water moves from
# the base pool, which are what the limits leave standing. The limits are applied after
# the band, so they always win. 65+ and unknown ages keep the base pools.
BAND_POOLS: dict[str, dict[str, tuple[str, ...]]] = {
    "young": {
        "none": ("walk_short", "stairs", "cycling", "mobility_flow", "swim_laps", "jog_walk"),
        "some": ("jog_walk", "cycling", "stairs", "strength_twice", "swim_laps", "dancing"),
        "active": (
            "bodyweight_circuit",
            "sport_friends",
            "jog_walk",
            "cycling",
            "swim_laps",
            "strength_twice",
            "stairs",
            "dancing",
        ),
    },
    "mid": {
        "none": ("walk_short", "swim_laps", "cycling", "mobility_flow", "stairs"),
        "some": ("walk_brisk", "swim_laps", "cycling", "strength_twice", "mobility_flow"),
        "active": (
            "strength_twice",
            "walk_brisk",
            "swim_laps",
            "cycling",
            "hill_walk",
            "mobility_flow",
            "dancing",
        ),
    },
}


def pool_for(level: str, age: int | None) -> tuple[str, ...]:
    """The pick order for an activity level and age. Band picks come first, then the seated
    and water moves of the base pool, so a person with limits always has something."""
    lead = BAND_POOLS.get(band(age), {}).get(level)
    if lead is None:
        return POOLS[level]
    tail = tuple(
        a for a in POOLS[level] if a not in lead and ACTIVITIES[a].position in {"seated", "water"}
    )
    return lead + tail


@dataclass(frozen=True)
class Card:
    id: str
    kind: str  # diet, habit
    title: str
    message: str
    why: str
    source: Source
    lever: str | None = None
    wellness_card: str | None = None
    keep_words: tuple[str, ...] = ()
    # Fixed wording: never sent for rephrasing.
    fixed: bool = False
    variants: dict = field(default_factory=dict)
    # Fields (message, why, source) that replace the base wording for everyone but 65+,
    # whose cards keep the older-adult wording and sources above.
    younger: dict = field(default_factory=dict)

    def for_band(self, age: int | None) -> "Card":
        if band(age) == "older" or not self.younger:
            return self
        return replace(self, **self.younger)


DIET: dict[str, Card] = {
    c.id: c
    for c in (
        Card(
            "protein_each_meal",
            "diet",
            "Some protein at each meal",
            "Try adding some protein to each meal, like eggs, beans, yogurt or fish. If your "
            "doctor has told you to limit protein, follow that.",
            "Many older adults don't get enough protein, and it helps keep muscles strong.",
            ACL_PROTEIN,
            keep_words=("doctor",),
            younger={
                "why": "Most people do well with some protein at each meal, and it helps keep "
                "muscles strong.",
                "source": DGA,
            },
        ),
        Card(
            "fluids",
            "diet",
            "Sip water through the day",
            "Keep a glass of water nearby and sip through the day, before you feel thirsty, "
            "unless your doctor limits your fluids.",
            "Thirst fades with age, so it helps to drink before you feel thirsty.",
            NIA_MEALS,
            keep_words=("unless your doctor",),
            younger={
                "why": "Most people feel better when they drink water regularly through the day.",
                "source": NHS_WATER,
            },
        ),
        Card(
            "dash_less_salt",
            "diet",
            "Go easy on salt",
            "Taste your food before adding salt, and pick lower-salt soups and sauces when "
            "you can.",
            "Less salt and a DASH-style way of eating help keep blood pressure down.",
            NHLBI_DASH,
            keep_words=("salt",),
        ),
        Card(
            "mediterranean",
            "diet",
            "Mediterranean-style meals",
            "Build a meal around vegetables, beans, olive oil and fish, the Mediterranean way.",
            "A Mediterranean pattern of eating is linked with heart health in large studies.",
            PREDIMED,
        ),
        Card(
            "fiber",
            "diet",
            "A little more fiber",
            "Add a fruit, a vegetable, or a whole grain like oats or beans to one meal today.",
            "Fruit, vegetables and whole grains are the heart of healthy eating for older adults.",
            NIA_MEALS,
            younger={
                "why": "Most people eat less fiber than they could, and fruit, vegetables and "
                "whole grains are the heart of healthy eating.",
                "source": DGA,
            },
        ),
        Card(
            "care_team_food",
            "diet",
            "Food questions with diabetes",
            "With diabetes, your care team or a dietitian is the best guide for food choices. "
            "Medicare Part B covers medical nutrition therapy with a dietitian for diabetes or "
            "kidney disease, when your doctor refers you.",
            "Food needs with diabetes are different for each person, so they belong with your "
            "care team.",
            MEDICARE_MNT,
            fixed=True,
            younger={
                "message": "With diabetes, your care team or a dietitian is the best guide for "
                "food choices. Your doctor can refer you to a dietitian.",
                "source": NIDDK_DIABETES_FOOD,
            },
        ),
        Card(
            "care_team_kidney",
            "diet",
            "Food questions with kidney disease",
            "With kidney disease, please ask your kidney doctor or a dietitian before changing "
            "how much protein or fluid you have. Medicare Part B covers medical nutrition "
            "therapy with a dietitian for kidney disease, when your doctor refers you.",
            "Protein and fluid needs with kidney disease are different for each person.",
            MEDICARE_MNT,
            fixed=True,
            younger={
                "message": "With kidney disease, please ask your kidney doctor or a dietitian "
                "before changing how much protein or fluid you have. Your doctor can refer you "
                "to a dietitian.",
                "source": NIDDK_KIDNEY_FOOD,
            },
        ),
    )
}
DIET_ORDER = ("protein_each_meal", "fluids", "mediterranean", "fiber", "dash_less_salt")

HABITS: dict[str, Card] = {
    c.id: c
    for c in (
        Card(
            "quit_help",
            "habit",
            "Help with smoking, if you want it",
            "If you'd like help to quit smoking, your doctor or a free quit line can help. "
            "Want me to remind you to ask?",
            "Quitting is the change the model ranks first, at any age.",
            CDC_TOBACCO,
            lever="quit_smoking",
            wellness_card="smoking",
        ),
        Card(
            "sleep_routine",
            "habit",
            "A steady bedtime",
            "Try going to bed and getting up at the same time each day, and get some daylight "
            "in the morning.",
            "You've been sleeping under seven hours, and a steady routine helps sleep.",
            CDC_SLEEP,
            lever="short_sleep_plus_1h",
            wellness_card="sleep",
        ),
        Card(
            "sitting_breaks",
            "habit",
            "Up during the ad breaks",
            "When an ad comes on, stand up and move around until the show is back.",
            "Breaking up long sitting is good for everyone, whatever else you do.",
            WHO_2020,
            lever="sitting_minus_60_realistic",
            wellness_card="sitting",
            variants={
                "seated_only": "When an ad comes on, shift in your chair, stretch your arms "
                "up and roll your shoulders until the show is back."
            },
        ),
    )
}

SUPPLEMENT_REPLY = (
    "I don't suggest supplements, because they can mix badly with medicines. A pharmacist "
    "can check them for free: bring your bottles to your pharmacist or your doctor next time."
)
MEDICINE_REPLY = (
    "Please don't change your medicines without your doctor. Your doctor or pharmacist is "
    "the right person for that question."
)
DIAGNOSIS_REPLY = "I can't tell what that is. Please check with your doctor soon."
WEIGHT_REPLY = (
    "I don't give weight-loss plans. If your weight is on your mind, your doctor is the best "
    "person to ask. Here's a food idea instead."
)
DIABETES_FOOD_REPLY = (
    "For food questions with diabetes, your care team or a dietitian is the best guide. "
    "Medicare covers medical nutrition therapy for diabetes, when your doctor refers you."
)
KIDNEY_FOOD_REPLY = (
    "With kidney disease, please ask your kidney doctor or a dietitian about protein and "
    "fluids. Medicare covers medical nutrition therapy for kidney disease, when your doctor "
    "refers you."
)
FORECAST_REPLY = (
    "Nobody can tell how long a person will live, and I never guess. The model only compares "
    "similar people over the next one to five years, and it shows links, not causes."
)
BP_CRISIS_REPLY = (
    "That blood pressure reading is very high. Sit quietly for a few minutes and check it "
    "again. If it is still that high, please contact your doctor now. Call 911 if you have "
    "chest pain, shortness of breath, back pain, numbness, weakness, a change in vision or "
    "trouble speaking."
)
TREND_NOTICES = {
    "bp": "Your last few blood pressure readings were higher than before. It's worth "
    "bringing them to your doctor.",
    "a1c": "Your last few A1c results were higher than before. Please bring them to your "
    "care team at your next visit.",
    "ldl": "Your last few cholesterol results were higher than before. It's worth bringing "
    "them to your doctor.",
}
RED_FLAG_REPLY = (
    "Let's pause movement ideas for now. Please check with your doctor before trying them again."
)
CLEARED_REPLY = "That's good news. We'll start small again."
FORGET_WHICH = "Which thing should I forget? You can tell me, or look in Mochi's notebook."
FORGET_NOT_FOUND = "I couldn't find that in my notebook. You can look there to check."
# The source behind each fixed reply, recorded in the trace.
REPLY_SOURCES = {
    SUPPLEMENT_REPLY: NIA_SUPPLEMENTS,
    MEDICINE_REPLY: NIA_SUPPLEMENTS,
    DIABETES_FOOD_REPLY: MEDICARE_MNT,
    KIDNEY_FOOD_REPLY: MEDICARE_MNT,
    WEIGHT_REPLY: NIA_MEALS,
}

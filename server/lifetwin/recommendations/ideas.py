"""The idea catalog behind "Ideas for you": many small, concrete ideas per lever.

Each idea follows one lever (levers.py) and one wellness card, and cites that card's
existing source (service.SOURCES). Tags say who it suits; ``avoid`` holds the coach's
limitation tags (coach/models.py ``LimitTag``) that rule it out. An idea with an
``avoid`` tag is never shown to someone with that limitation. ``needs`` ideas are only
shown when the person's own words mention one of their interests (no dog, no dog idea).

Messages are Mochi's words: no weight, years, dates, promises or percentage points, and
no supplements. ``test_recommendation_ideas.py`` checks every line against the outside-AI
safety check (personalize/safety.py) too.
"""

import re
from dataclasses import dataclass
from typing import Literal

Kind = Literal["walk", "dance", "stand", "stretch", "sleep", "eat", "social", "breath", "craving"]
KINDS: tuple[str, ...] = Kind.__args__
AGE_BANDS = ("18-39", "40-64", "65+")
ALL_AGES = AGE_BANDS
MID_UP = ("40-64", "65+")
LIMIT_TAGS = ("knee_pain", "walking_aid", "fall_risk", "cardio_caution", "seated_only")
TIMES = ("morning", "afternoon", "evening")
INTERESTS = (
    "dog",
    "grandkids",
    "family",
    "garden",
    "music",
    "tv",
    "reading",
    "church",
    "work",
    "driving",
    "cooking",
    "friends",
    "phone",
    "puzzles",
    "walking",
    "swimming",
    "cycling",
    "shopping",
    "alone",
    "worry",
    "noise",
    "nap",
)
# Stages: "start" for people doing no activity (a small start), "more" for people doing
# some (or who named an activity but no minutes), "pace" for walkers who may go faster,
# "keep" for people already at the guideline (encouragement only), "any" otherwise.
Stage = Literal["any", "start", "more", "pace", "keep"]

# Limitation tags read from the person's words, kept identical to the coach's
# (coach/planner.py NOTE_LIMITS; a test keeps them in sync). Copied, not imported: the
# planner imports onboarding, which imports this package.
NOTE_LIMITS = {
    "knee_pain": re.compile(r"\b(?:knee|knees|hip|hips|arthritis|joint|joints)\b"),
    "walking_aid": re.compile(r"\b(?:walker|cane|rollator|walking stick|zimmer frame)\b"),
    "seated_only": re.compile(
        r"\b(?:wheelchair|can't stand|cannot stand|can not stand|bed ?bound|chair ?bound)\b"
    ),
    "fall_risk": re.compile(r"\b(?:fall|falls|falling|fell|balance|unsteady|wobbly)\b"),
    "cardio_caution": re.compile(r"\b(?:breath|breathless|heart|angina|chest)\b"),
}
# Pain or trouble of any kind, unnamed: keep to the gentle, joint-friendly ideas.
ANY_PAIN = re.compile(r"\b(?:pain|pains|painful|ache|aches|sore|trouble|hurts?)\b")

INTEREST_WORDS = {
    "dog": r"\b(?:dog|dogs|pup|puppy)\b",
    "grandkids": r"\bgrand(?:kids?|child|children|son|sons|daughter|daughters|babies)\b",
    "family": r"\b(?:kids|children|son|daughter|family|grand\w*)\b",
    "garden": r"\bgarden\w*|\byard\b",
    "music": r"\b(?:music|danc\w*|sing\w*|songs?|radio|choir)\b",
    "tv": r"\b(?:tv|television|telly|shows?|netflix|news)\b",
    "reading": r"\b(?:read\w*|books?|novels?)\b",
    "church": r"\b(?:church|community|volunteer\w*|choir|temple|mosque|synagogue|club)\b",
    "work": r"\b(?:computer|desk|work\w*|office|laptop|emails?|job)\b",
    "driving": r"\b(?:driv\w*|car|commut\w*)\b",
    "cooking": r"\b(?:cook\w*|kitchen|bak\w*)\b",
    "friends": r"\b(?:friends?|neighbou?rs?|group|class|club)\b",
    "phone": r"\b(?:phone|calls?|chat\w*)\b",
    "puzzles": r"\b(?:puzzles?|crosswords?|sudoku|cards|games?)\b",
    "walking": r"\bwalk\w*",
    "swimming": r"\b(?:swim\w*|pool)\b",
    "cycling": r"\b(?:bike|bikes|biking|cycl\w*)\b",
    "shopping": r"\b(?:shop\w*|grocer\w*|store|mall)\b",
    "alone": r"\b(?:alone|myself|on my own)\b",
    "worry": r"\b(?:worr\w*|stress\w*|anxi\w*|racing|mind)\b",
    "noise": r"\b(?:noise|noisy|snor\w*|loud)\b",
}
INTEREST_PATTERNS = {tag: re.compile(pattern) for tag, pattern in INTEREST_WORDS.items()}
TIME_WORDS = {
    "morning": re.compile(r"\b(?:morning|mornings|breakfast|early)\b"),
    "afternoon": re.compile(r"\b(?:afternoon|afternoons|lunch|midday|noon)\b"),
    "evening": re.compile(r"\b(?:evening|evenings|dinner|supper|night)\b"),
}

# Limitation shorthands for the catalog below.
WALKING = ("knee_pain", "seated_only")  # an easy walk: fine with a cane, not with sore knees
STANDING = ("seated_only",)
BRISK = LIMIT_TAGS  # faster or harder effort: only with no limitation at all
DANCING = ("knee_pain", "walking_aid", "fall_risk", "seated_only")
POOL = ("walking_aid", "seated_only")
BIKE = ("walking_aid", "fall_risk", "seated_only")


@dataclass(frozen=True)
class Idea:
    id: str
    lever: str
    stages: tuple[str, ...]
    title: str
    message: str
    why: str
    kind: str
    ages: tuple[str, ...] = ALL_AGES
    interests: tuple[str, ...] = ()
    needs: bool = False  # shown only when one of ``interests`` is in the person's words
    times: tuple[str, ...] = ()  # empty: any time of day
    social: Literal["social", "solo", "either"] = "either"
    place: Literal["indoor", "outdoor", "either"] = "either"
    avoid: tuple[str, ...] = ()

    @property
    def card(self) -> str:
        return {
            "quit_smoking": "smoking",
            "short_sleep_plus_1h": "sleep",
            "sitting_minus_60_realistic": "sitting",
        }.get(self.lever, "activity")

    @property
    def source(self) -> str:
        """The key of its source in service.SOURCES (the wellness card's own source)."""
        return self.card


Q = "quit_smoking"
MOD = "moderate_plus_90"
VIG = "vigorous_plus_60"
KEEP = "keep_it_up"
SLEEP = "short_sleep_plus_1h"
SIT = "sitting_minus_60_realistic"

IDEAS: tuple[Idea, ...] = (
    # --- Smoking: for current smokers, always first. ---------------------------------------
    Idea(
        "smoke_quitline",
        Q,
        ("any",),
        "Support for quitting",
        "Quitting smoking helps health at any age. When you feel ready, you could call "
        "1-800-QUIT-NOW for free, friendly support.",
        "Support is there whenever you feel ready to quit.",
        "social",
    ),
    Idea(
        "smoke_delay",
        Q,
        ("any",),
        "The ten-minute delay",
        "When a craving hits, tell yourself you'll wait ten minutes first. Set a timer, sip "
        "some water or step outside, and see if the urge fades. Each wait is good practice.",
        "Most cravings pass if you can wait them out a little.",
        "craving",
    ),
    Idea(
        "smoke_after_dinner_walk",
        Q,
        ("any",),
        "Swap the after-dinner cigarette",
        "If you usually smoke after dinner, try a short stroll around the block instead, or "
        "out to the mailbox and back. A new after-meal habit fills the gap the cigarette "
        "leaves.",
        "Swapping in a new habit is easier than just stopping.",
        "walk",
        interests=("cooking", "walking"),
        times=("evening",),
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "smoke_busy_hands",
        Q,
        ("any",),
        "Keep your hands busy",
        "Keep something for your hands and mouth close by: a toothpick, sugar-free gum, "
        "crunchy carrot sticks or a stress ball. Reach for it when you'd usually reach for a "
        "cigarette.",
        "Having a swap ready makes a craving easier to ride out.",
        "craving",
        interests=("work", "driving"),
    ),
    Idea(
        "smoke_slow_breaths",
        Q,
        ("any",),
        "Breathe through a craving",
        "When a craving comes, try slow breathing: in through your nose while you count to "
        "four, out through your mouth while you count to six. A few rounds can take the edge "
        "off the urge.",
        "Slow breathing gives a craving time to pass.",
        "breath",
        interests=("worry",),
    ),
    Idea(
        "smoke_tell_someone",
        Q,
        ("any",),
        "Tell someone you trust",
        "Tell a friend or someone in your family that you're thinking about quitting, and "
        "ask if you can text them when a craving gets hard. Having someone in your corner "
        "can make the tough moments easier.",
        "Quitting with someone cheering you on is easier than going it alone.",
        "social",
        interests=("friends", "family", "grandkids", "phone"),
        social="social",
    ),
    Idea(
        "smoke_triggers",
        Q,
        ("any",),
        "Spot your triggers",
        "For a couple of days, jot down when you light up: with coffee, in the car, after "
        "meals, on breaks. Knowing your triggers helps you plan a swap for each one.",
        "Knowing when cravings come helps you plan for them.",
        "craving",
        social="solo",
    ),
    Idea(
        "smoke_free_car",
        Q,
        ("any",),
        "A smoke-free car",
        "If you smoke while driving, make the car a smoke-free zone. Clean out the ashtray, "
        "add a fresh air freshener and keep gum and a good playlist ready for the drive.",
        "Breaking the link between driving and smoking takes away a trigger.",
        "craving",
        interests=("driving",),
    ),
    Idea(
        "smoke_free_home",
        Q,
        ("any",),
        "A smoke-free home",
        "Make your home smoke-free, one room at a time or all at once. Stepping outside adds "
        "a pause that gives you a moment to choose, and it keeps the air fresh for the "
        "people and pets you love.",
        "A pause before each cigarette gives you a moment to choose.",
        "craving",
        interests=("grandkids", "family", "dog"),
    ),
    Idea(
        "smoke_push_back_first",
        Q,
        ("any",),
        "Push back the first one",
        "If your first cigarette comes with your morning coffee, try pushing it back a little "
        "each day: after your shower, then after breakfast. Shrinking the habit step by step "
        "still counts.",
        "Small steps away from the habit still count.",
        "craving",
        times=("morning",),
    ),
    Idea(
        "smoke_quit_jar",
        Q,
        ("any",),
        "A quit jar",
        "Put the money you'd spend on cigarettes into a jar each day and watch it grow. Pick "
        "something you'd love to spend it on, like a meal out with friends or a gift for "
        "someone special.",
        "Seeing what you save keeps the reason to quit in view.",
        "craving",
        interests=("friends", "grandkids", "family"),
    ),
    Idea(
        "smoke_ask_pharmacist",
        Q,
        ("any",),
        "Ask about quit aids",
        "Your doctor or pharmacist can talk you through quit aids such as the patch or gum, "
        "and which would suit you. You could bring it up at your next visit.",
        "Quit aids and advice can make quitting easier.",
        "social",
    ),
    # --- Activity, a small start: for people doing none. ------------------------------------
    Idea(
        "start_after_meal_walk",
        MOD,
        ("start",),
        "A walk after a meal",
        "You could start small, with a short walk after a meal a few days a week.",
        "Even a short, easy walk is a good place to begin.",
        "walk",
        interests=("walking", "cooking"),
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_kettle_dance",
        MOD,
        ("start", "more"),
        "Kettle dance",
        "Put on three songs you love and dance around the kitchen while the kettle boils "
        "and the tea brews. No steps to learn, just move however feels good.",
        "Moving to music you love hardly feels like exercise.",
        "dance",
        interests=("music", "cooking"),
        times=("morning",),
        place="indoor",
        avoid=DANCING,
    ),
    Idea(
        "start_chair_dancing",
        MOD,
        ("start", "more"),
        "Dancing in your chair",
        "Pick a favorite song and move from your chair: swing your arms, tap your feet and "
        "roll your shoulders. When it ends, play another.",
        "Moving in your chair counts, and it is easy on the joints.",
        "dance",
        interests=("music",),
        place="indoor",
    ),
    Idea(
        "start_grocery_lap",
        MOD,
        ("start", "more"),
        "A lap of the store",
        "Next time you shop, walk one easy lap of the grocery store before you start filling "
        "your cart. It's flat and dry, and the cart is there to lean on.",
        "Folding a walk into errands you already do makes it easy to keep.",
        "walk",
        interests=("shopping",),
        place="indoor",
        avoid=WALKING,
    ),
    Idea(
        "start_walk_and_talk",
        MOD,
        ("start", "more"),
        "A walk-and-talk call",
        "Call a friend or someone in your family and take a gentle stroll while you chat, "
        "around the block or even around the house. The time flies when you're catching up.",
        "Pairing a walk with a good chat makes the time fly.",
        "social",
        interests=("phone", "friends", "family", "grandkids"),
        social="social",
        avoid=WALKING,
    ),
    Idea(
        "start_landmark",
        MOD,
        ("start",),
        "There and back",
        "Pick a landmark close to home, like the mailbox, the corner or a neighbor's gate, "
        "and walk there and back. Go a little farther whenever it feels easy.",
        "A short, familiar route is an easy first step.",
        "walk",
        interests=("walking", "alone"),
        social="solo",
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_tv_steps",
        MOD,
        ("start",),
        "Steps during your show",
        "During one TV show, stand up and walk around the room whenever the ads come on. "
        "You'll be moving without missing a moment.",
        "Tying a little movement to a show you already watch makes it stick.",
        "walk",
        interests=("tv",),
        times=("evening",),
        place="indoor",
        avoid=WALKING,
    ),
    Idea(
        "start_grandkids_park",
        MOD,
        ("start", "more"),
        "Park time with the grandkids",
        "Take the grandkids to the park and join in: push the swings, stroll the paths and "
        "chase a ball now and then. Their energy is catching.",
        "Playing with the grandkids is activity that doesn't feel like a chore.",
        "social",
        ages=MID_UP,
        interests=("grandkids",),
        needs=True,
        social="social",
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_garden_minutes",
        MOD,
        ("start",),
        "Garden minutes",
        "Spend a little time in the garden: pull a few weeds, water the pots or rake a "
        "corner. Light garden work is real activity.",
        "Garden jobs you enjoy count as activity.",
        "stretch",
        interests=("garden",),
        needs=True,
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_dog_yes",
        MOD,
        ("start",),
        "Say yes to the dog",
        "Next time your dog asks to go out, take a slow stroll around the block together "
        "instead of just opening the door.",
        "Your dog is a ready-made walking buddy.",
        "walk",
        interests=("dog",),
        needs=True,
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_bottle_lifts",
        MOD,
        ("start", "more"),
        "Water-bottle lifts",
        "Sit tall in a sturdy chair, hold a water bottle in each hand and raise your arms "
        "out to the sides, then lower them slowly. It's an easy one to do during the news.",
        "Gentle seated moves are a kind way to begin.",
        "stretch",
        interests=("tv",),
        place="indoor",
    ),
    Idea(
        "start_church_stroll",
        MOD,
        ("start", "more"),
        "A stroll with your community",
        "Arrive at church or your community group a little early and take a gentle walk "
        "around the building or the grounds with someone you know.",
        "A walk with people you know is easy to look forward to.",
        "social",
        interests=("church",),
        needs=True,
        social="social",
        avoid=WALKING,
    ),
    Idea(
        "start_pool_walk",
        MOD,
        ("start", "more"),
        "Walk in the pool",
        "If you can get to a pool, walk back and forth in the shallow end. The water "
        "supports your joints, so it's a kind way to begin.",
        "Water takes the strain off sore joints.",
        "walk",
        interests=("swimming",),
        place="indoor",
        avoid=POOL,
    ),
    Idea(
        "start_morning_loop",
        MOD,
        ("start",),
        "A slow morning loop",
        "Start the day with an easy walk around the block or the garden, then come back to "
        "your coffee. A gentle, regular start is easy to keep.",
        "Making it part of your morning means you don't have to remember it.",
        "walk",
        interests=("walking", "garden"),
        times=("morning",),
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "start_seated_routine",
        MOD,
        ("start", "more"),
        "A seated routine",
        "In a sturdy chair, lift each knee in turn, circle your arms, and press your palms "
        "together, a few minutes of each, to music you like.",
        "Moving in your chair counts, and it is easy on the joints.",
        "stretch",
        interests=("music", "tv"),
        place="indoor",
    ),
    # --- Activity, a little more: for people doing some. ------------------------------------
    Idea(
        "more_one_session",
        MOD,
        ("more",),
        "One more time a week",
        "Adding one more session a week of something you already enjoy is an easy way to "
        "build on it.",
        "Building on something you already enjoy is easier to keep up.",
        "walk",
    ),
    Idea(
        "more_dog_new_route",
        MOD,
        ("more",),
        "A new route with your dog",
        "Take your dog a different, slightly longer way around. New smells for them, new "
        "sights for you, and a few extra minutes for both of you.",
        "A new route makes a familiar walk fun again.",
        "walk",
        interests=("dog",),
        needs=True,
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "more_dog_evening",
        MOD,
        ("more",),
        "An extra dog walk",
        "Add a short evening stroll with your dog on top of the usual walk. It's a calm way "
        "to end the day, for both of you.",
        "Your dog is a ready-made walking buddy.",
        "walk",
        interests=("dog",),
        needs=True,
        times=("evening",),
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "more_grandkids_adventure",
        MOD,
        ("more",),
        "An adventure walk",
        "Plan a little adventure walk with the grandkids: a nature trail, a scavenger hunt "
        "for leaves and stones, or a stroll to the ice cream shop.",
        "Exploring with the grandkids turns a walk into an outing.",
        "social",
        ages=MID_UP,
        interests=("grandkids",),
        needs=True,
        social="social",
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "more_park_farther",
        MOD,
        ("more",),
        "Park a little farther",
        "When you drive somewhere, park at the far end of the lot and enjoy the extra stroll "
        "to the door and back.",
        "Small extra walks fit into the day without a plan.",
        "walk",
        interests=("driving", "shopping"),
        avoid=WALKING,
    ),
    Idea(
        "more_lunch_loop",
        MOD,
        ("more",),
        "A lunchtime loop",
        "Take a short walk on your lunch break or after lunch, even just around the "
        "building. A regular slot makes it easier to remember.",
        "A regular slot in the day makes a walk easier to remember.",
        "walk",
        interests=("work",),
        times=("afternoon",),
        avoid=WALKING,
    ),
    Idea(
        "more_walking_group",
        MOD,
        ("more",),
        "Join a walking group",
        "Look for a walking group at a community center, library or church. Walking with "
        "others makes it social, and they'll notice when you're missing.",
        "Walking with others makes it social and easier to keep up.",
        "social",
        interests=("church", "friends"),
        social="social",
        avoid=WALKING,
    ),
    Idea(
        "more_dance_night",
        MOD,
        ("more",),
        "A dance night",
        "Try a dance class or a social dance night: line dancing, ballroom or salsa. Many "
        "welcome beginners, and it hardly feels like exercise.",
        "Dancing with others hardly feels like exercise.",
        "dance",
        interests=("music", "friends"),
        times=("evening",),
        social="social",
        place="indoor",
        avoid=DANCING + ("cardio_caution",),
    ),
    Idea(
        "more_easy_ride",
        MOD,
        ("more",),
        "An easy bike ride",
        "Take your bike out for an easy ride on a flat path or a quiet street, or pedal an "
        "exercise bike while you watch something.",
        "An easy ride is a gentle way to add a little activity.",
        "walk",
        interests=("cycling",),
        needs=True,
        avoid=BIKE,
    ),
    Idea(
        "more_pool_time",
        MOD,
        ("more",),
        "Pool time",
        "Add a swim or a pool walk to your week. Water takes the strain off your joints, so "
        "it's a gentle way to do a bit extra.",
        "Water takes the strain off sore joints.",
        "walk",
        interests=("swimming",),
        needs=True,
        place="indoor",
        avoid=POOL,
    ),
    Idea(
        "more_garden_session",
        MOD,
        ("more",),
        "A longer garden session",
        "Give the garden one extra session a week: mowing, digging a bed or raking leaves "
        "all count. Take breaks and switch tasks often.",
        "Garden jobs you enjoy count as activity.",
        "stretch",
        interests=("garden",),
        needs=True,
        place="outdoor",
        avoid=WALKING,
    ),
    Idea(
        "more_story_walk",
        MOD,
        ("more",),
        "Walk with a story",
        "Save a podcast, an audiobook or a favorite album just for walks. You'll look "
        "forward to the next chapter, and to the walk that comes with it.",
        "Something to look forward to makes a walk easier to start.",
        "walk",
        interests=("reading", "music", "alone", "walking"),
        social="solo",
        avoid=WALKING,
    ),
    Idea(
        "more_mall_walk",
        MOD,
        ("more", "start"),
        "Mall walking",
        "On rainy or cold days, walk laps of a mall or a big store. It's flat, has benches to "
        "rest on, and some open early for walkers.",
        "Walking indoors keeps you going whatever the weather.",
        "walk",
        interests=("shopping", "walking"),
        place="indoor",
        avoid=WALKING,
    ),
    Idea(
        "more_gentle_class",
        MOD,
        ("more", "start"),
        "A gentle class",
        "Look for a gentle exercise class at a community or senior center, like chair yoga "
        "or a seated exercise group. Many are made for beginners.",
        "A class made for beginners takes the guesswork out.",
        "stretch",
        ages=MID_UP,
        interests=("church", "friends"),
        social="social",
        place="indoor",
    ),
    # --- Activity, a faster pace: for walkers with no limitation. ------------------------
    Idea(
        "pace_lampposts",
        VIG,
        ("pace",),
        "Lamppost intervals",
        "On your next walk, pick up the pace between two lampposts, then ease off for the "
        "next two, and keep swapping. Brisk bits that leave you a little out of breath count "
        "double.",
        "A faster pace for part of your walk is a simple next step.",
        "walk",
        interests=("walking",),
        place="outdoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_hill",
        VIG,
        ("pace",),
        "Find a hill",
        "Add a hill or a slope to your usual route and climb it at a steady push. Walking "
        "uphill turns an easy walk into a livelier one.",
        "A hill on your route is a simple way to add effort.",
        "walk",
        interests=("walking",),
        place="outdoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_beat",
        VIG,
        ("pace",),
        "Walk to the beat",
        "Make a playlist of upbeat songs and match your steps to the beat for a song or two, "
        "then cool off with a slower one.",
        "Music with a quick beat makes a faster pace feel easy.",
        "walk",
        interests=("music", "walking", "alone"),
        social="solo",
        avoid=BRISK,
    ),
    Idea(
        "pace_dog_home",
        VIG,
        ("pace",),
        "A quick finish with your dog",
        "For the last stretch of your dog walk, pick up the pace and let your dog set a quick "
        "tempo home. Brisk minutes like these count double.",
        "Your dog is happy to set a quicker pace.",
        "walk",
        interests=("dog",),
        needs=True,
        place="outdoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_grandkids_tag",
        VIG,
        ("pace",),
        "Tag with the grandkids",
        "Join the grandkids in a game of tag or kick a ball around the yard. Short bursts of "
        "running around are the kind of activity that leaves you out of breath.",
        "Playing with the grandkids is lively activity that feels like fun.",
        "social",
        ages=MID_UP,
        interests=("grandkids",),
        needs=True,
        social="social",
        place="outdoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_stairs",
        VIG,
        ("pace",),
        "Take the stairs",
        "Choose the stairs over the elevator when you can, and take them at a good pace. A "
        "couple of flights gets your heart going.",
        "Stairs are a quick way to add effort to your day.",
        "walk",
        interests=("work", "shopping"),
        place="indoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_brisk_friend",
        VIG,
        ("pace",),
        "A brisk walk with a friend",
        "Walk with a friend at a pace where you can talk but not sing. You'll keep each other "
        "going a bit faster than you'd go alone.",
        "A walking partner helps you keep a brisker pace.",
        "social",
        interests=("friends", "walking"),
        social="social",
        avoid=BRISK,
    ),
    Idea(
        "pace_ride",
        VIG,
        ("pace",),
        "A livelier ride",
        "On your next ride, add a stretch where you pedal harder, up a hill or into the wind, "
        "until you're breathing hard, then ease off.",
        "Harder stretches on a ride are a simple next step.",
        "walk",
        interests=("cycling",),
        needs=True,
        place="outdoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_swim",
        VIG,
        ("pace",),
        "A few faster laps",
        "In the pool, swim a faster lap between your usual easy ones, and see how it feels.",
        "Faster laps between easy ones are a simple next step.",
        "walk",
        interests=("swimming",),
        needs=True,
        place="indoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_dance",
        VIG,
        ("pace",),
        "Dance it up",
        "Put on a fast song and dance hard enough that you're breathing quicker. A few songs "
        "in a row makes a great workout.",
        "Fast songs turn dancing into a lively workout.",
        "dance",
        interests=("music",),
        place="indoor",
        avoid=BRISK,
    ),
    Idea(
        "pace_garden_jobs",
        VIG,
        ("pace",),
        "The big garden jobs",
        "Take on a bigger garden job like digging, pushing a hand mower or hauling mulch. "
        "Heavy garden work counts as vigorous activity.",
        "Heavy garden work counts as vigorous activity.",
        "stretch",
        interests=("garden",),
        needs=True,
        place="outdoor",
        avoid=BRISK,
    ),
    # --- Encouragement: for people already at the guideline. Never "do more". --------------
    Idea(
        "keep_mix",
        KEEP,
        ("keep",),
        "Mix it up",
        "To keep it fun, swap in something new now and then, like a new walking route, a "
        "swim or a dance class.",
        "You are already active, so keep doing what works for you.",
        "walk",
    ),
    Idea(
        "keep_strength",
        KEEP,
        ("keep",),
        "Strong as well as active",
        "Alongside what you do, the guidelines also suggest muscle-strengthening moves on two "
        "days a week, like carrying groceries, heavy gardening or resistance bands.",
        "Strength moves round out the activity you already do.",
        "stretch",
        interests=("garden", "shopping"),
    ),
    Idea(
        "keep_bring_someone",
        KEEP,
        ("keep",),
        "Bring someone along",
        "Invite a friend or neighbor to join you now and then. You'll keep your routine "
        "going, and you might get them moving too.",
        "Sharing what you do helps you keep it going.",
        "walk",
        interests=("friends", "church"),
        social="social",
    ),
    Idea(
        "keep_grandkids",
        KEEP,
        ("keep",),
        "Pass it on",
        "Bring the grandkids along for a walk, a swim or a game in the park. You're passing "
        "on a great habit.",
        "Being active with family passes on a great habit.",
        "walk",
        ages=MID_UP,
        interests=("grandkids",),
        needs=True,
        social="social",
    ),
    Idea(
        "keep_balance",
        KEEP,
        ("keep",),
        "Add a little balance",
        "The guidelines for older adults also suggest balance activities, like standing on "
        "one foot while you hold the kitchen counter, or walking heel to toe along the hall.",
        "Balance practice rounds out the activity you already do.",
        "stand",
        ages=("65+",),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "keep_rest_day",
        KEEP,
        ("keep",),
        "Listen to your body",
        "Keep an easy day in your week, and switch activities if something starts to ache. "
        "Staying steady matters as much as anything.",
        "You are already active, so keep doing what works for you.",
        "walk",
    ),
    Idea(
        "keep_dog",
        KEEP,
        ("keep",),
        "You and your dog",
        "You and your dog have a great routine going. Keep enjoying those walks together.",
        "You and your dog have a routine that works.",
        "walk",
        interests=("dog",),
        needs=True,
    ),
    Idea(
        "keep_streak",
        KEEP,
        ("keep",),
        "Notice your streak",
        "Mark each active day on a calendar or in your phone. A row of check marks is a nice "
        "reminder of how far you've come.",
        "Seeing your streak is a nice reminder of what you do.",
        "walk",
        interests=("phone",),
        social="solo",
    ),
    # --- Sleep: only for people sleeping under 7 hours. ---------------------------------
    Idea(
        "sleep_regular_bedtime",
        SLEEP,
        ("any",),
        "A regular bedtime",
        "You could try a regular bedtime that leaves room for 7 hours, which CDC suggests "
        "for adults.",
        "A regular bedtime leaves room for the sleep adults are advised to get.",
        "sleep",
    ),
    Idea(
        "sleep_wind_down",
        SLEEP,
        ("any",),
        "A wind-down ritual",
        "Give yourself a half-hour wind-down before bed: dim the lights, have a warm shower, "
        "read a few pages or play some quiet music. The same routine each night tells your "
        "body it's time to sleep.",
        "A calm routine before bed signals that it's time to sleep.",
        "sleep",
        interests=("reading", "music", "worry"),
        times=("evening",),
    ),
    Idea(
        "sleep_morning_light",
        SLEEP,
        ("any",),
        "Morning daylight",
        "Get outside into daylight soon after you wake, even for a few minutes with your "
        "coffee on the porch or on a short stroll. Morning light helps set your body clock.",
        "Morning light helps set your body clock.",
        "walk",
        interests=("garden", "dog", "walking"),
        times=("morning",),
        place="outdoor",
    ),
    Idea(
        "sleep_fixed_wake",
        SLEEP,
        ("any",),
        "A fixed wake time",
        "Get up at the same time every day, weekends too. A steady wake time makes it easier "
        "to feel sleepy at a regular hour at night.",
        "A steady wake time helps you feel sleepy at a regular hour.",
        "sleep",
        times=("morning",),
    ),
    Idea(
        "sleep_screens_off",
        SLEEP,
        ("any",),
        "Screens off early",
        "Put phones, laptops and the TV away about half an hour before bed, and charge your "
        "phone outside the bedroom if you can.",
        "Screens off before bed make it easier to drift off.",
        "sleep",
        interests=("tv", "phone", "work"),
        times=("evening",),
    ),
    Idea(
        "sleep_dark_room",
        SLEEP,
        ("any",),
        "A dark, quiet room",
        "Make your bedroom dark, quiet and a little cool. Blackout curtains, an eye mask, or a "
        "fan for steady background sound can all help.",
        "A dark, quiet, cool room makes it easier to sleep.",
        "sleep",
        interests=("noise",),
    ),
    Idea(
        "sleep_worry_list",
        SLEEP,
        ("any",),
        "Park your worries",
        "If your mind races at night, write down what's on it before bed, with one small next "
        "step for each. Then it's on paper, not on repeat.",
        "Writing worries down can quiet a busy mind at bedtime.",
        "sleep",
        interests=("worry", "reading"),
        times=("evening",),
        social="solo",
    ),
    Idea(
        "sleep_bedtime_alarm",
        SLEEP,
        ("any",),
        "A bedtime alarm",
        "Set an alarm for bedtime, not just for waking. When it goes off, start winding down, "
        "even if it's in the middle of a show.",
        "A reminder at bedtime helps you keep a regular schedule.",
        "sleep",
        interests=("tv", "phone"),
        times=("evening",),
    ),
    Idea(
        "sleep_short_naps",
        SLEEP,
        ("any",),
        "Short, early naps",
        "If you nap, keep it short and before mid-afternoon, so you're still sleepy at bedtime.",
        "Short, early naps leave you ready to sleep at night.",
        "sleep",
        interests=("nap",),
        needs=True,
        times=("afternoon",),
    ),
    Idea(
        "sleep_active_day",
        SLEEP,
        ("any",),
        "Move in the daytime",
        "Being active during the day, like a walk in the afternoon, can make it easier to "
        "fall asleep at night. Just finish brisk exercise a few hours before bed.",
        "Daytime activity can make it easier to fall asleep.",
        "walk",
        interests=("walking", "dog"),
        times=("afternoon",),
        avoid=WALKING,
    ),
    Idea(
        "sleep_earlier_supper",
        SLEEP,
        ("any",),
        "An earlier supper",
        "Have your bigger meal earlier in the evening and skip alcohol close to bedtime, so "
        "your body can settle for sleep.",
        "A lighter evening helps your body settle for sleep.",
        "eat",
        interests=("cooking",),
        times=("evening",),
    ),
    Idea(
        "sleep_get_up",
        SLEEP,
        ("any",),
        "Bed is for sleep",
        "If you can't fall asleep after a while, get up, do something calm in dim light, and "
        "go back to bed when you feel sleepy.",
        "Keeping bed for sleep helps your body link bed with sleep.",
        "sleep",
        interests=("worry", "reading"),
    ),
    # --- Sitting less: last. ---------------------------------------------------------------
    Idea(
        "sit_ad_breaks",
        SIT,
        ("any",),
        "Stand for the ads",
        "Each time the ads come on, stand up and move around the room until your show is "
        "back. Over an evening, it adds up.",
        "Standing for each ad break breaks up long sitting.",
        "stand",
        interests=("tv",),
        times=("evening",),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_remote_away",
        SIT,
        ("any",),
        "The remote across the room",
        "Keep the TV remote across the room, so changing the channel means a few steps each time.",
        "A few extra steps each time break up long sitting.",
        "stand",
        interests=("tv",),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_phone_pace",
        SIT,
        ("any",),
        "Pace during phone calls",
        "Whenever the phone rings, stand up and walk around while you talk. Long chats become "
        "easy movement.",
        "Moving while you talk turns sitting time into moving time.",
        "walk",
        interests=("phone", "friends", "family"),
        avoid=STANDING,
    ),
    Idea(
        "sit_chapter_stretch",
        SIT,
        ("any",),
        "Stretch every chapter",
        "At the end of each chapter, stand and stretch, or walk to the kitchen for a glass of "
        "water.",
        "A stretch at each chapter breaks up long reading spells.",
        "stretch",
        interests=("reading",),
        social="solo",
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_drive_stops",
        SIT,
        ("any",),
        "Stretch stops",
        "On longer drives, plan a stop every hour or so to get out, walk around the car and "
        "stretch your legs.",
        "Regular stops break up long drives.",
        "stretch",
        interests=("driving",),
        avoid=STANDING,
    ),
    Idea(
        "sit_desk_timer",
        SIT,
        ("any",),
        "A desk timer",
        "At the computer, set a timer to stand up and walk around every half hour or so. "
        "Refill your water, or walk over to someone instead of sending a message.",
        "Standing up regularly breaks up long sitting at a desk.",
        "stand",
        interests=("work",),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_puzzle_walk",
        SIT,
        ("any",),
        "A walk between puzzles",
        "Between puzzles or games, get up for a short walk around the house or out to the "
        "garden and back.",
        "A short walk between puzzles breaks up long sitting.",
        "walk",
        interests=("puzzles",),
        avoid=WALKING,
    ),
    Idea(
        "sit_kettle_stand",
        SIT,
        ("any",),
        "Stand while it brews",
        "Every time you make a cup of tea or coffee, stay on your feet while it brews: stretch "
        "your calves, roll your shoulders, look out of the window.",
        "Small standing moments across the day break up sitting.",
        "stand",
        interests=("cooking",),
        times=("morning",),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_shift_reach",
        SIT,
        ("any",),
        "Shift and reach",
        "Every hour, change position, sit up tall, and reach both arms overhead and out to "
        "the sides a few times. Small moves break up long spells of stillness.",
        "Small moves in your seat break up long spells of stillness.",
        "stretch",
        interests=("tv", "reading", "puzzles"),
    ),
    Idea(
        "sit_walking_meeting",
        SIT,
        ("any",),
        "Stand for part of a meeting",
        "Stand for part of a video call or a meeting, or suggest a walking meeting with a "
        "colleague.",
        "Standing for part of your work day breaks up long sitting.",
        "stand",
        ages=("18-39", "40-64"),
        interests=("work",),
        needs=True,
        social="social",
        avoid=STANDING,
    ),
    Idea(
        "sit_hourly",
        SIT,
        ("any",),
        "Up every hour",
        "You could try standing up and moving for a few minutes every hour. Moving more and "
        "sitting less is good advice for everyone.",
        "Standing and moving a bit more often breaks up long sitting.",
        "stand",
        avoid=STANDING,
    ),
    Idea(
        "sit_spread_chores",
        SIT,
        ("any",),
        "Spread out the chores",
        "Instead of doing chores all at once, spread them through the day: fold some "
        "laundry, water the plants or put the dishes away between sitting spells.",
        "Chores spread through the day break up sitting.",
        "stand",
        interests=("cooking", "garden"),
        place="indoor",
        avoid=STANDING,
    ),
    Idea(
        "sit_tv_stretch",
        SIT,
        ("any",),
        "A show-time stretch",
        "During each show, do a few seated stretches: stretch and flex your feet, circle your "
        "ankles and roll your shoulders.",
        "Moving in your seat breaks up long sitting.",
        "stretch",
        interests=("tv",),
        times=("evening",),
        place="indoor",
    ),
)
BY_ID: dict[str, Idea] = {idea.id: idea for idea in IDEAS}

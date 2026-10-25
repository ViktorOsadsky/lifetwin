"""The v1 habit catalogue: small, everyday habits with an anchor, a tiny action and a source.

Every habit starts tiny (about 2 minutes) and is tied to an existing routine
("after lunch"), following implementation intentions (Gollwitzer & Sheeran 2006)
and context-cued repetition (Gardner, Lally & Wardle 2012). Nothing here escalates
past the guidelines, mentions weight, calories or supplements, or restricts food:
food habits only add something. A habit never claims a score or survival benefit;
behaviour reaches the twin only through the measured inputs it changes.
"""

from dataclasses import dataclass
from typing import Literal

# "nourish" is not in the design's list: water with meals needs a home, and it only adds.
Pillar = Literal["move", "sleep", "sit_less", "unwind", "smoke_free", "connect", "nourish"]
# The model's levers, in the order docs/model-sensitivity.md ranks them.
Lever = Literal["quit_smoking", "vigorous_activity", "moderate_activity", "sleep", "sitting"]
LEVER_ORDER: tuple[Lever, ...] = (
    "quit_smoking",
    "vigorous_activity",
    "moderate_activity",
    "sleep",
    "sitting",
)
CatalogId = Literal[
    "morning_daylight",
    "steady_bedtime",
    "walk_after_lunch",
    "brisk_walk",
    "stand_on_calls",
    "three_breaths",
    "text_a_friend",
    "water_with_meals",
    "quit_help",
]
AgeBand = Literal["young", "mid", "older"]


@dataclass(frozen=True)
class Source:
    publisher: str
    title: str
    url: str


@dataclass(frozen=True)
class CatalogHabit:
    id: CatalogId
    pillar: Pillar
    lever: Lever | None
    name: str  # "your after-lunch walk", for summaries
    tiny_action: str
    anchors: dict[AgeBand, str]
    source: Source


WHO_ACTIVITY = Source(
    "World Health Organization",
    "WHO guidelines on physical activity and sedentary behaviour (2020)",
    "https://www.who.int/publications/i/item/9789240015128",
)
CDC_SLEEP = Source(
    "Centers for Disease Control and Prevention",
    "About Sleep",
    "https://www.cdc.gov/sleep/about/",
)
CDC_EATING = Source(
    "Centers for Disease Control and Prevention",
    "Healthy Eating Tips",
    "https://www.cdc.gov/nutrition/features/healthy-eating-tips.html",
)
CDC_QUITTING = Source(
    "Centers for Disease Control and Prevention",
    "Benefits of Quitting Smoking",
    "https://www.cdc.gov/tobacco/about/benefits-of-quitting.html",
)
NCCIH_RELAX = Source(
    "NIH National Center for Complementary and Integrative Health",
    "Relaxation Techniques: What You Need To Know",
    "https://www.nccih.nih.gov/health/relaxation-techniques-what-you-need-to-know",
)
SURGEON_GENERAL_CONNECTION = Source(
    "U.S. Surgeon General",
    "Our Epidemic of Loneliness and Isolation (2023 advisory)",
    "https://www.hhs.gov/sites/default/files/surgeon-general-social-connection-advisory.pdf",
)


def _same(anchor: str) -> dict[AgeBand, str]:
    return {"young": anchor, "mid": anchor, "older": anchor}


CATALOGUE: dict[CatalogId, CatalogHabit] = {
    habit.id: habit
    for habit in (
        CatalogHabit(
            "morning_daylight",
            "sleep",
            None,
            "your morning daylight",
            "step outside for 2 minutes of daylight",
            {
                "young": "After I make my morning coffee",
                "mid": "After I make my morning coffee",
                "older": "After breakfast",
            },
            CDC_SLEEP,
        ),
        CatalogHabit(
            "steady_bedtime",
            "sleep",
            "sleep",
            "your steady bedtime",
            "put my phone away and start winding down at the same time",
            _same("When my bedtime reminder goes off"),
            CDC_SLEEP,
        ),
        CatalogHabit(
            "walk_after_lunch",
            "move",
            "moderate_activity",
            "your after-lunch walk",
            "walk for 2 minutes outside",
            _same("After lunch"),
            WHO_ACTIVITY,
        ),
        CatalogHabit(
            "brisk_walk",
            "move",
            "vigorous_activity",
            "your brisk walk",
            "walk fast enough to breathe a little harder for 2 minutes",
            {
                "young": "On my way home",
                "mid": "On my way home",
                "older": "On my afternoon walk",
            },
            WHO_ACTIVITY,
        ),
        CatalogHabit(
            "stand_on_calls",
            "sit_less",
            "sitting",
            "standing up more",
            "stand up and move around for a minute",
            {
                "young": "When a call, meeting or game round starts",
                "mid": "When a phone or video call starts",
                "older": "When an ad break starts on TV",
            },
            WHO_ACTIVITY,
        ),
        CatalogHabit(
            "three_breaths",
            "unwind",
            None,
            "your slow breaths",
            "take 3 slow breaths",
            {
                "young": "Before I open my messages or email",
                "mid": "Before I open my email",
                "older": "Before I turn on the TV",
            },
            NCCIH_RELAX,
        ),
        CatalogHabit(
            "text_a_friend",
            "connect",
            None,
            "staying in touch",
            "send a short message to someone I like",
            {
                "young": "On my commute home",
                "mid": "After dinner",
                "older": "After my afternoon tea",
            },
            SURGEON_GENERAL_CONNECTION,
        ),
        CatalogHabit(
            "water_with_meals",
            "nourish",
            None,
            "your water with meals",
            "pour a glass of water to enjoy with it",
            _same("When I sit down to a meal"),
            CDC_EATING,
        ),
        CatalogHabit(
            "quit_help",
            "smoke_free",
            "quit_smoking",
            "your smoke-free step",
            "wait 2 minutes and take a few slow breaths first",
            _same("When I feel like smoking"),
            CDC_QUITTING,
        ),
    )
}
# Under 30, or when nothing else applies: general guidelines in this order.
GUIDELINE_ORDER: tuple[CatalogId, ...] = (
    "walk_after_lunch",
    "morning_daylight",
    "stand_on_calls",
    "steady_bedtime",
    "three_breaths",
    "water_with_meals",
    "text_a_friend",
    "brisk_walk",
)
LEVER_HABIT: dict[Lever, CatalogId] = {
    habit.lever: habit.id for habit in CATALOGUE.values() if habit.lever is not None
}
PILLAR_WORDS: dict[Pillar, str] = {
    "move": "Move",
    "sleep": "Sleep",
    "sit_less": "Sit less",
    "unwind": "Unwind",
    "smoke_free": "Smoke-free",
    "connect": "Connect",
    "nourish": "Nourish",
}


def age_band(age: int) -> AgeBand:
    return "young" if age < 35 else "mid" if age < 60 else "older"

"""Adversarial tests for POST /api/recommendations, written from the product rules.

Rules (server/lifetwin/recommendations/service.py docstring, owner and model-sensitivity
rulings): at most 3 suggestions; smoking first for current smokers; activity is none
versus any (0 gets a small start, 150+ gets encouragement only, sorted last); sleep only
under 7 hours; never weight, years gained, dates, promises or percentage points; a
missing value is never treated as 0 in an experiment preset; why_short is at most 90
characters; under 18 gets no ideas.
"""

import random
import re
from urllib.parse import urlparse

import pytest
from fastapi.testclient import TestClient

import lifetwin.onboarding  # noqa: F401  (import first: avoids a pre-existing import cycle)
from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import HabitNote
from lifetwin.recommendations.levers import (
    EFFECT_NOTE,
    LEVER_ORDER,
    MEDIAN_PP,
    effect_category,
)
from lifetwin.recommendations.service import suggest

CATEGORIES = {"big", "some", "small", "tiny"}
FORBIDDEN = re.compile(
    r"\b(?:weigh\w*|pounds?|lbs?|kilos?|kg|years?|yrs?|percent\w*|percentage|points?|pp|"
    r"promis\w*|guarantee\w*|date|dates|live longer|longevity|life ?span|"
    r"january|february|march|april|may|june|july|august|september|october|november|december|"
    r"monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow)\b|%",
    re.I,
)
SUPPLEMENTS = re.compile(
    r"supplement|vitamin|creatine|energy drink|pre-?workout|caffeine|melatonin|protein (?:powder|shake)",
    re.I,
)
FIELD_FOR = {
    "vigorous_plus_60": "vigorous_recreation_min_week",
    "moderate_plus_90": "moderate_recreation_min_week",
    "short_sleep_plus_1h": "sleep_hours",
    "sitting_minus_60_realistic": "sedentary_min_day",
}


def make_client(personalizer=None):
    app = create_app(
        Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
    )
    if personalizer is not None:
        app.state.personalizer = personalizer
    return TestClient(app)


@pytest.fixture(scope="module")
def client():
    return make_client()


def post(client, profile, notes=None, consent=None):
    body = {"profile": profile, "habit_notes": notes or []}
    if consent:
        body["outside_ai_consent"] = consent
    response = client.post("/api/recommendations", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def random_profiles(count=1500, seed=20261024):
    rng = random.Random(seed)
    for _ in range(count):
        profile = {}
        if rng.random() < 0.9:
            profile["age"] = rng.choice(
                [18, 19, 34, 35, 39, 40, 49, 50, 64, 65, 79, 80, 85, 86, 99]
            )
        if rng.random() < 0.8:
            profile["sex"] = rng.choice(["male", "female"])
        if rng.random() < 0.8:
            profile["smoking_status"] = rng.choice(["never", "former", "current", "unknown"])
        if rng.random() < 0.8:
            profile["sleep_hours"] = rng.choice([0, 3, 5.5, 6, 6.99, 7, 7.5, 9, 14])
        if rng.random() < 0.8:
            profile["sedentary_min_day"] = rng.choice([0, 100, 239, 240, 480, 900, 1439])
        mode = rng.choice(["both", "moderate", "vigorous", "weekly", "none"])
        if mode in {"both", "moderate"}:
            profile["moderate_recreation_min_week"] = rng.choice([0, 20, 60, 100, 149, 150, 300])
        if mode in {"both", "vigorous"}:
            profile["vigorous_recreation_min_week"] = rng.choice([0, 10, 30, 75, 200])
        if mode == "weekly":
            profile["exercise_minutes_weekly"] = rng.choice([0, 45, 149, 150, 500])
        yield profile


# --- Property sweep over many profiles ------------------------------------------------------


def test_every_recommendation_follows_the_product_rules():
    for profile in random_profiles():
        check_product_rules(profile)


def check_product_rules(profile):
    prof = HealthProfile(**profile)
    recs = suggest(prof, [])
    assert len(recs) <= 3
    levers = [r.lever for r in recs]
    assert len(set(levers)) == len(levers)
    # Ranking order, except that encouragement goes last.
    ranked = [lever for lever in levers if lever != "keep_it_up"]
    order = [LEVER_ORDER.index(lever) for lever in ranked]
    assert order == sorted(order)
    if "keep_it_up" in levers:
        assert levers[-1] == "keep_it_up"
    if profile.get("smoking_status") == "current":
        assert levers[0] == "quit_smoking"
    else:
        assert "quit_smoking" not in levers
    for rec in recs:
        text = " ".join([rec.title, rec.message, rec.why_short])
        assert not FORBIDDEN.search(text), text
        assert not SUPPLEMENTS.search(text), text
        assert 0 < len(rec.why_short) <= 90
        host = (urlparse(rec.source_url).hostname or "").removeprefix("www.")
        assert rec.source_domain == host and host
        assert rec.effect_note == EFFECT_NOTE
        assert rec.causal_interpretation is False
        if rec.lever == "keep_it_up":
            assert rec.effect is None
            assert rec.experiment_lever is None and rec.experiment_target is None
        else:
            in_range = prof.age is None or 18 <= prof.age <= 85
            assert (rec.effect in CATEGORIES) == in_range
            assert rec.effect == effect_category(rec.lever, prof.age, prof.sex)
    # Sleep only for people under 7 hours, never at 7 or more or when unknown.
    sleep = prof.sleep_hours
    if "short_sleep_plus_1h" in levers:
        assert sleep is not None and sleep < 7
    # Experiment presets never invent a current value.
    for rec in recs:
        if rec.lever in FIELD_FOR:
            field = FIELD_FOR[rec.lever]
            current = getattr(prof, field)
            assert rec.experiment_lever == field
            if current is None:
                assert rec.experiment_target is None, (rec.lever, profile)
            elif field == "sleep_hours":
                assert rec.experiment_target == min(24, current + 1)
            elif field == "sedentary_min_day":
                assert rec.experiment_target == max(0, current - 60)
            elif field == "moderate_recreation_min_week":
                assert rec.experiment_target == current + 90
            else:
                assert rec.experiment_target == current + 60
        elif rec.lever == "quit_smoking":
            assert (rec.experiment_lever, rec.experiment_target) == ("smoking_status", "former")


@pytest.mark.parametrize(
    "profile",
    [
        {"exercise_minutes_weekly": 0},
        {"moderate_recreation_min_week": 0, "vigorous_recreation_min_week": 0},
        {"moderate_recreation_min_week": 0},
    ],
)
def test_no_activity_gets_a_small_start_not_a_target_of_150(profile):
    (rec,) = [r for r in suggest(HealthProfile(**profile), []) if r.wellness_card == "activity"]
    assert rec.title == "A small start"
    assert "10 to 15 minutes" in rec.message
    assert "150" not in rec.message


@pytest.mark.parametrize(
    "profile",
    [
        {"exercise_minutes_weekly": 150},
        {"moderate_recreation_min_week": 150},
        {"moderate_recreation_min_week": 100, "vigorous_recreation_min_week": 25},  # 100 + 2*25
        {"vigorous_recreation_min_week": 75},
        {"exercise_minutes_weekly": 10000},
    ],
)
def test_150_plus_is_encouragement_only_and_last(profile):
    recs = suggest(HealthProfile(**profile, smoking_status="current", sleep_hours=5), [])
    assert recs[-1].lever == "keep_it_up"
    assert recs[0].lever == "quit_smoking"
    assert recs[-1].effect is None and recs[-1].experiment_target is None
    assert "more" not in recs[-1].message.lower().replace("keep it up", "")


@pytest.mark.parametrize(
    "profile",
    [
        {"exercise_minutes_weekly": 149},
        {"moderate_recreation_min_week": 149},
        {"moderate_recreation_min_week": 100, "vigorous_recreation_min_week": 24},  # 148
    ],
)
def test_just_under_150_is_not_praised_as_done(profile):
    levers = [r.lever for r in suggest(HealthProfile(**profile), [])]
    assert "keep_it_up" not in levers


@pytest.mark.parametrize("hours", [7, 7.0, 8, 9, 12, 24])
def test_no_sleep_suggestion_at_seven_hours_or_more(hours):
    levers = [r.lever for r in suggest(HealthProfile(sleep_hours=hours), [])]
    assert "short_sleep_plus_1h" not in levers


def test_sleep_just_under_seven_gets_it_and_missing_sleep_does_not():
    assert [r.lever for r in suggest(HealthProfile(sleep_hours=6.9), [])] == ["short_sleep_plus_1h"]
    assert suggest(HealthProfile(), []) == []


def test_four_candidates_are_cut_to_three_with_the_biggest_levers_kept():
    profile = HealthProfile(
        age=70,
        sex="male",
        smoking_status="current",
        exercise_minutes_weekly=0,
        sleep_hours=5,
        sedentary_min_day=900,
    )
    assert [r.lever for r in suggest(profile, [])] == [
        "quit_smoking",
        "moderate_plus_90",
        "short_sleep_plus_1h",
    ]


# --- Effect cue --------------------------------------------------------------------------------


def test_effect_follows_the_documented_cut_offs_for_every_table_entry():
    # 2.0 / 0.75 / 0.25 pp, computed here from the numbers rather than from the helper.
    def expected(pp):
        return "big" if pp >= 2.0 else "some" if pp >= 0.75 else "small" if pp >= 0.25 else "tiny"

    for key, medians in MEDIAN_PP.items():
        age = {"all": 25, "35-49": 40, "50-64": 55, "65-79": 70}[key.split("|")[0]]
        sex = key.split("|")[1] if "|" in key else None
        for lever, pp in medians.items():
            assert effect_category(lever, age, sex) == expected(pp), (key, lever, pp)


@pytest.mark.parametrize("age", [18, 85])
def test_effect_exists_at_the_edges_of_the_supported_ages(age):
    assert effect_category("quit_smoking", age, "female") in CATEGORIES


@pytest.mark.parametrize("age", [17, 86])
def test_effect_is_null_just_outside_the_supported_ages(age):
    assert effect_category("quit_smoking", age, "female") is None


def test_older_smokers_get_a_bigger_cue_than_young_ones():
    rank = ["tiny", "small", "some", "big"]
    young = rank.index(effect_category("quit_smoking", 40, "male"))
    old = rank.index(effect_category("quit_smoking", 70, "male"))
    assert old > young


# --- Response over HTTP --------------------------------------------------------------------------


def test_under_18_gets_no_ideas_and_the_provider_is_never_asked():
    class Spy:
        name = "muse"
        configured = True
        may_train_on_content = False
        calls = 0

        async def phrase(self, instructions, facts):
            Spy.calls += 1
            return {"lines": ["x"]}

    spy_client = make_client(Spy())
    body = post(spy_client, {"age": 17, "smoking_status": "current"}, consent={"muse": True})
    assert body["status"] == "under_age" and body["recommendations"] == []
    assert Spy.calls == 0
    assert not FORBIDDEN.search(body["message"])
    assert "smok" not in body["message"].lower()


def test_age_zero_is_under_age_not_a_crash(client):
    assert post(client, {"age": 0})["status"] == "under_age"


def test_unknown_age_still_gets_ideas_without_an_age_claim(client):
    body = post(client, {"smoking_status": "current"})
    assert body["status"] == "ok"
    assert body["recommendations"][0]["lever"] == "quit_smoking"


def test_nothing_known_says_so_and_lists_every_missing_input_in_order(client):
    body = post(client, {})
    assert body["status"] == "not_enough_information"
    assert body["recommendations"] == []
    assert body["missing_inputs"] == [
        "smoking_status",
        "vigorous_recreation_min_week",
        "moderate_recreation_min_week",
        "sleep_hours",
        "sedentary_min_day",
    ]
    assert "rush" in body["message"]


def test_unknown_smoking_answer_is_still_missing_for_nothing_to_suggest(client):
    # "unknown" is an answer that gives no suggestion; nothing else is known either.
    body = post(client, {"smoking_status": "unknown"})
    assert body["status"] == "not_enough_information"


def test_a_complete_healthy_profile_still_gets_a_response_never_an_error(client):
    body = post(
        client,
        {
            "age": 50,
            "sex": "female",
            "smoking_status": "never",
            "sleep_hours": 8,
            "sedentary_min_day": 100,
            "moderate_recreation_min_week": 200,
            "vigorous_recreation_min_week": 0,
        },
    )
    assert body["status"] == "ok"
    assert [r["lever"] for r in body["recommendations"]] == ["keep_it_up"]
    assert body["missing_inputs"] == []


def test_overall_message_matches_the_cards_and_stays_in_bounds(client):
    body = post(
        client,
        {
            "age": 60,
            "smoking_status": "current",
            "sleep_hours": 5,
            "sedentary_min_day": 700,
            "exercise_minutes_weekly": 10,
        },
    )
    assert len(body["recommendations"]) == 3
    assert body["message"].startswith("Here are a few ideas")
    for rec in body["recommendations"]:
        assert rec["message"] in body["message"]
    assert len(body["message"]) <= 1500
    assert not FORBIDDEN.search(body["message"])


def test_server_response_never_echoes_profile_values_as_numbers_of_years(client):
    body = post(client, {"age": 73, "sex": "male", "smoking_status": "current"})
    assert "73" not in body["message"]


@pytest.mark.parametrize(
    "profile",
    [
        {"sex": "intersex"},
        {"sex": "prefer_not_to_say"},
        {"sex": "other"},
        {"sex": ""},
        {"age": -1},
        {"age": 121},
        {"age": "forty"},
        {"sleep_hours": -1},
        {"sleep_hours": 25},
        {"sedentary_min_day": 1440},
        {"smoking_status": "sometimes"},
    ],
)
def test_invalid_profiles_are_refused_with_422_not_500_and_not_guessed(client, profile):
    response = client.post("/api/recommendations", json={"profile": profile})
    assert response.status_code == 422
    assert response.json()["code"] == "invalid_request"
    # The answer is never echoed back.
    assert "intersex" not in response.text and "prefer_not_to_say" not in response.text


def test_unknown_fields_and_too_many_notes_are_refused(client):
    assert client.post("/api/recommendations", json={"profile": {}, "extra": 1}).status_code == 422
    notes = [{"topic": "sleep"}] * 11
    assert (
        client.post("/api/recommendations", json={"profile": {}, "habit_notes": notes}).status_code
        == 422
    )
    assert client.post("/api/recommendations", json={}).status_code == 422


def test_ten_notes_with_long_words_are_fine(client):
    notes = [{"topic": "exercise", "kind": "walking", "with": "x" * 80}] * 10
    out = post(client, {"exercise_minutes_weekly": 30}, notes)
    assert out["status"] == "ok"


# --- Consent and outside wording ---------------------------------------------------------------------


class Provider:
    name = "muse"
    configured = True
    may_train_on_content = False

    def __init__(self, line=None):
        self.line = line
        self.calls = 0

    async def phrase(self, instructions, facts):
        self.calls += 1
        return {
            "lines": [
                self.line if self.line is not None else item["draft"] for item in facts["items"]
            ]
        }


def test_consent_for_another_provider_never_reaches_this_one():
    provider = Provider()
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"claude": True})
    assert provider.calls == 0 and body["phrased_by"] == "templates"
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"muse": False})
    assert provider.calls == 0 and body["phrased_by"] == "templates"


@pytest.mark.parametrize(
    "line",
    [
        "Take vitamin D every morning.",
        "A herbal tea would help.",
        "You will gain two years.",
        "Quit by next Friday.",
        "This lowers your chance by 5%.",
        "Lose weight first.",
        "Try 7 walks.",  # a number the facts do not hold
        "See https://example.com now.",
        "",
        "x" * 500,
    ],
)
def test_unsafe_outside_wording_falls_back_to_the_template(line):
    provider = Provider(line)
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"muse": True})
    assert provider.calls == 1
    assert body["phrased_by"] == "templates"
    assert body["recommendations"][0]["message"].startswith("Quitting smoking helps")


@pytest.mark.parametrize(
    "line",
    [
        pytest.param(
            "A pre-workout drink before your walk could help.",
            id="pre-workout",
        ),
        pytest.param(
            "You could have an energy drink first.",
            id="energy-drink",
        ),
        pytest.param(
            "That should add time to your life.",
            id="time-to-your-life",
        ),
        pytest.param(
            "You will feel better soon.",
            id="promise",
        ),
        pytest.param(
            "Aim to lose a bit of belly.",
            id="belly",
        ),
    ],
)
def test_outside_wording_with_stimulants_promises_or_weight_loss_falls_back(line):
    provider = Provider(line)
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"muse": True})
    assert body["phrased_by"] == "templates", body["recommendations"][0]["message"]


# --- The person's own words are echoed back ------------------------------------------------------------


@pytest.mark.parametrize(
    "note",
    [
        {"topic": "exercise", "kind": "creatine and energy drinks"},
        {"topic": "exercise", "kind": "pre-workout shots"},
        {"topic": "exercise", "kind": "protein powder workouts"},
    ],
)
def test_supplement_words_in_a_note_are_not_repeated_in_a_suggestion(note):
    recs = suggest(HealthProfile(), [HabitNote.model_validate(note)])
    text = " ".join(r.message for r in recs)
    assert not SUPPLEMENTS.search(text), text


def test_numbers_in_a_note_never_become_numbers_in_a_suggestion():
    recs = suggest(HealthProfile(), [HabitNote(topic="exercise", kind="10000 steps in 3 years")])
    text = " ".join(r.message for r in recs)
    assert not FORBIDDEN.search(text), text


def test_a_note_naming_vitamin_d_can_be_quoted():
    recs = suggest(HealthProfile(), [HabitNote(topic="exercise", kind="vitamin D walks")])
    assert "vitamin D walks" in " ".join(r.message for r in recs)


@pytest.mark.parametrize(
    "line",
    [
        "Some people take vitamin D, so check with your doctor or pharmacist first.",
        "A daily multivitamin or more fiber is common; ask your pharmacist before starting.",
    ],
)
def test_an_unrelated_supplement_with_a_doctor_pointer_still_falls_back(line):
    provider = Provider(line)
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"muse": True})
    assert body["phrased_by"] == "templates", body["recommendations"][0]["message"]


@pytest.mark.parametrize(
    "line",
    [
        "Some people take vitamin D.",  # no pointer to the doctor or pharmacist
        "Some people take vitamin D, 2000 IU, so check with your doctor.",  # a dose
        "Take 1000 mg of vitamin D; check with your doctor.",
        "Vitamin D can prevent illness, so check with your doctor.",  # presented as prevention
        "Try vitamin C, and check with your doctor first.",  # not on the gentle list
        "A creatine powder may help; check with your doctor.",
        "Herbal tea with fiber, check with your doctor.",
    ],
)
def test_a_supplement_line_without_the_pointer_or_with_a_dose_or_claim_falls_back(line):
    provider = Provider(line)
    body = post(make_client(provider), {"smoking_status": "current"}, consent={"muse": True})
    assert body["phrased_by"] == "templates", body["recommendations"][0]["message"]

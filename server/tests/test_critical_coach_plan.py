"""Adversarial tests for POST /api/coach/plan: age edges, limit tags, missing fields, bounds.

Bands (catalog.band): 18-39 young, 40-64 mid, 65+ older; under 18 and unknown are
neutral. Limit tags always override the band. Nothing in the plan may mention
supplements, weight loss, years gained, a date or a promise.
"""

import itertools
import re

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.coach import catalog as cat
from lifetwin.core.config import Settings

OLDER = re.compile(r"\bolder adults\b|\bseniors?\b|\belderly\b|\bwith age\b", re.I)
BANNED = re.compile(
    r"supplement|vitamin|creatine|energy drink|pre-?workout|caffeine|protein (?:powder|shake)|"
    r"lose weight|weight loss|slim|calorie|pounds|\blbs?\b|\bkg\b|percent|%|guarantee|promise|"
    r"live longer|years (?:to|of) (?:your )?life|add(?:s|ed)? years|"
    r"\b(?:january|february|april|june|july|august|september|october|november|december)\b",
    re.I,
)
VIGOROUS_PICKS = {a.id for a in cat.ACTIVITIES.values() if a.intensity == "vigorous"}


@pytest.fixture(scope="module")
def client():
    app = create_app(
        Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
    )
    return TestClient(app)


def plan(client, profile=None, **extra):
    body = {"local_date": "2026-10-26", **extra}
    if profile is not None:
        body["profile"] = profile
    response = client.post("/api/coach/plan", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def workout(body):
    return next((i for i in body["items"] if i["kind"] == "workout"), None)


def spoken(body):
    parts = list(body["lines"]) + [body.get("reply") or ""]
    for item in body["items"]:
        parts += [item["title"], item["message"], item["why"]]
    parts += [c["explanation"] for c in body["changes"]]
    return "\n".join(parts)


# --- Age bands and their edges ---------------------------------------------------------------------


@pytest.mark.parametrize("age", [18, 39, 40, 64])
def test_ages_below_65_never_hear_older_adult_wording(client, age):
    for minutes in (0, 60, 300):
        body = plan(client, {"age": age, "exercise_minutes_weekly": minutes})
        assert not OLDER.search(spoken(body)), (age, minutes, spoken(body))


@pytest.mark.parametrize("age", [65, 85, 86, 100])
def test_65_and_over_keep_the_gentle_set_with_older_adult_guideline_wording(client, age):
    body = plan(client, {"age": age, "exercise_minutes_weekly": 0})
    w = workout(body)
    assert w["catalog_id"] == "walk_short"
    assert "older adults" in w["why"]
    food = next(i for i in body["items"] if i["kind"] == "diet")
    assert "older adults" in food["why"]


def test_the_65_edge_flips_between_64_and_65(client):
    sixty_four = plan(client, {"age": 64, "exercise_minutes_weekly": 300})
    sixty_five = plan(client, {"age": 65, "exercise_minutes_weekly": 300})
    assert workout(sixty_four)["catalog_id"] == "strength_twice"
    assert workout(sixty_five)["catalog_id"] not in {"strength_twice", *VIGOROUS_PICKS}
    assert workout(sixty_five)["intensity"] == "light"


def test_the_40_edge_flips_between_39_and_40(client):
    thirty_nine = plan(client, {"age": 39, "exercise_minutes_weekly": 300})
    forty = plan(client, {"age": 40, "exercise_minutes_weekly": 300})
    assert workout(thirty_nine)["catalog_id"] == "bodyweight_circuit"
    assert workout(forty)["catalog_id"] == "strength_twice"
    assert workout(forty)["intensity"] != "vigorous"


def test_the_18_edge_adults_get_the_young_adult_set_and_17_does_not(client):
    assert workout(plan(client, {"age": 18, "exercise_minutes_weekly": 300}))["intensity"] == (
        "vigorous"
    )
    assert workout(plan(client, {"age": 17, "exercise_minutes_weekly": 300})) is None


@pytest.mark.parametrize("age", [80, 85, 86, 120])
@pytest.mark.parametrize("minutes", [0, 60, 300, 10000])
def test_no_vigorous_workout_from_80(client, age, minutes):
    body = plan(client, {"age": age, "exercise_minutes_weekly": minutes})
    assert workout(body)["intensity"] != "vigorous"


@pytest.mark.parametrize("age", [None, 0, 12, 17])
@pytest.mark.parametrize("minutes", [0, 60, 300])
def test_unknown_or_under_18_never_gets_a_vigorous_pick(client, age, minutes):
    profile = {"exercise_minutes_weekly": minutes}
    if age is not None:
        profile["age"] = age
    picked = workout(plan(client, profile))
    assert picked is None or picked["intensity"] != "vigorous"


def test_under_18_is_not_handed_an_adult_plan(client):
    body = plan(client, {"age": 17, "smoking_status": "current", "exercise_minutes_weekly": 0})
    text = spoken(body)
    assert "guidelines for adults" not in text
    assert "quit smoking" not in text.lower()
    assert body["status"] == "under_age" and body["items"] == [] and body["plan_type"] is None
    assert body["revision_id"] is None and not body["emergency"]
    assert "adults" in body["lines"][0]


@pytest.mark.parametrize("age", [-1, 121, 200])
def test_impossible_ages_are_refused_not_planned(client, age):
    response = client.post(
        "/api/coach/plan", json={"local_date": "2026-10-26", "profile": {"age": age}}
    )
    assert response.status_code == 422 and response.json()["code"] == "invalid_request"


def test_a_sweep_over_ages_levels_and_limits_never_breaks_the_rules(client):
    ages = [None, 18, 29, 39, 40, 52, 64, 65, 79, 80, 85, 86]
    limit_sets = [
        [],
        ["knee_pain"],
        ["fall_risk", "walking_aid"],
        ["seated_only"],
        ["cardio_caution"],
    ]
    for age, minutes, limits in itertools.product(ages, (0, 45, 300), limit_sets):
        profile = {"exercise_minutes_weekly": minutes, "sleep_hours": 6, "sedentary_min_day": 600}
        if age is not None:
            profile["age"] = age
        body = plan(client, profile, limits=limits)
        label = (age, minutes, limits)
        assert body["status"] == "ok" and not body["emergency"], label
        assert not BANNED.search(spoken(body)), (label, spoken(body))
        assert 1 <= len(body["items"]) <= 4, label
        for item in body["items"]:
            assert item["source_url"].startswith("https://"), label
            assert item["reviewed_by"] == "awaiting professional review"
            assert item["causal_interpretation"] is False
            assert item["time_of_day"] in {"morning", "afternoon", "evening"}
            assert item["controls"] == ["accept", "edit", "dismiss"]
        w = workout(body)
        if limits:
            assert w["intensity"] != "vigorous", label
        if age is not None and age >= 65 and not limits:
            assert not OLDER.search(w["message"]), label  # the card body stays plain


# --- Limit tags --------------------------------------------------------------------------------------


@pytest.mark.parametrize("pair", list(itertools.combinations(cat.LIMITS, 2)))
@pytest.mark.parametrize("age", [18, 39, 40, 64, 65, 86])
def test_every_pair_of_limits_wins_over_the_age_band(client, pair, age):
    for minutes in (0, 300):
        body = plan(client, {"age": age, "exercise_minutes_weekly": minutes}, limits=list(pair))
        w = workout(body)
        activity = cat.ACTIVITIES[w["catalog_id"]]
        assert cat.allowed(activity, set(pair), age=age), (pair, age, w["catalog_id"])
        if "knee_pain" in pair or "seated_only" in pair:
            assert w["position"] in {"seated", "water"}, (pair, age, w)
        if "seated_only" in pair:
            assert w["position"] == "seated"
        if "cardio_caution" in pair:
            assert w["intensity"] == "light" or w["catalog_id"] == "walk_short"
        if {"walking_aid", "fall_risk"} & set(pair):
            assert w["catalog_id"] not in cat.UNSTEADY | cat.UNSUPPORTED


def test_all_five_limits_at_once_still_gives_a_safe_workout(client):
    body = plan(client, {"age": 30, "exercise_minutes_weekly": 300}, limits=list(cat.LIMITS))
    w = workout(body)
    assert w is not None and w["position"] == "seated" and w["intensity"] != "vigorous"


def test_a_limit_said_in_a_note_counts_only_with_memory_consent(client):
    note = {"id": "n1", "topic": "exercise", "kind": "walking", "barrier": "knee pain"}
    profile = {"age": 30, "exercise_minutes_weekly": 300}
    off = plan(client, profile, habit_notes=[note], memory_consent=False)
    unset = plan(client, profile, habit_notes=[note])
    on = plan(client, profile, habit_notes=[note], memory_consent=True)
    assert on["items"][0]["position"] in {"seated", "water"}
    assert workout(off)["catalog_id"] == workout(unset)["catalog_id"]
    assert "knee" not in spoken(off).lower() and "knee" not in spoken(unset).lower()


def test_a_limit_from_feedback_words_makes_the_next_plan_gentle(client):
    first = plan(client, {"age": 30, "exercise_minutes_weekly": 300})
    previous = {
        "revision_id": first["revision_id"],
        "based_on": first["based_on"],
        "local_date": first["local_date"],
        "input_snapshot_id": first["inputs"]["snapshot_id"],
        "items": [
            {
                k: i[k]
                for k in ("id", "kind", "catalog_id", "minutes", "time_of_day", "callback_note_id")
                if i.get(k) is not None
            }
            for i in first["items"]
        ],
    }
    second = plan(
        client,
        {"age": 30, "exercise_minutes_weekly": 300},
        local_date="2026-10-27",
        previous_plan=previous,
        latest_revision_id=first["revision_id"],
        feedback={
            "revision_id": first["revision_id"],
            "items": [{"item_id": "move", "status": "not_done", "reason": "it hurt my knee"}],
        },
    )
    assert workout(second)["position"] in {"seated", "water"}
    assert workout(second)["intensity"] != "vigorous"


# --- Missing fields and validation ---------------------------------------------------------------------------


def test_nothing_known_gives_a_labelled_general_plan_and_asks_one_question(client):
    body = plan(client)
    assert body["status"] == "ok" and body["plan_type"] == "general"
    assert body["clarify"] and body["clarify"].endswith("?")
    assert body["inputs"]["days_logged_last_7"] == 0
    assert body["inputs"]["experiments_used"] is False
    assert workout(body)["intensity"] != "vigorous"


@pytest.mark.parametrize(
    "profile",
    [
        {"sex": "female"},
        {"smoking_status": "unknown"},
        {"sleep_hours": 0},
        {"age": 18},
        {"height_cm": 170, "weight_kg": 200},
        {"exercise_minutes_weekly": 10080},
    ],
)
def test_sparse_profiles_never_crash_and_never_mention_weight(client, profile):
    body = plan(client, profile)
    assert body["status"] == "ok"
    assert not re.search(r"weigh|pound|kilo|\bkg\b|\bbmi\b", spoken(body), re.I)


@pytest.mark.parametrize("sex", ["intersex", "prefer_not_to_say", "other", ""])
def test_unsupported_sex_values_are_refused_not_guessed(client, sex):
    response = client.post(
        "/api/coach/plan", json={"local_date": "2026-10-26", "profile": {"sex": sex}}
    )
    assert response.status_code == 422


@pytest.mark.parametrize(
    "extra",
    [
        {"limits": ["wheelchair"]},
        {"limits": list(cat.LIMITS) + ["knee_pain"]},
        {"said": "x" * 501},
        {"said": ""},
        {"goals": ["a", "b", "c", "d"]},
        {"goals": ["x" * 81]},
        {"local_time": "24:00"},
        {"local_time": "9:30"},
        {"local_date": "2026-02-30"},
        {"local_date": "26-10-24"},
        {"checkins": [{"date": "2026-10-27"}]},
        {"checkins": [{"date": "2026-10-25"}, {"date": "2026-10-25"}]},
        {
            "readings": [
                {
                    "field": "systolic_bp",
                    "value": 120,
                    "unit": "%",
                    "date": "2026-10-25",
                    "source": "typed",
                }
            ]
        },
        {
            "readings": [
                {"field": "a1c", "value": 25, "unit": "%", "date": "2026-10-25", "source": "typed"}
            ]
        },
        {"habit_notes": [{"id": "a", "topic": "sleep"}, {"id": "a", "topic": "food"}]},
        {"habit_notes": [{"id": "has space", "topic": "sleep"}]},
        {"feedback": {"revision_id": "r1", "items": []}},
        {"unknown_field": 1},
    ],
)
def test_malformed_requests_are_422_never_500(client, extra):
    body = {"local_date": "2026-10-26", **extra}
    response = client.post("/api/coach/plan", json=body)
    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"


def test_422_never_echoes_what_the_person_said(client):
    response = client.post(
        "/api/coach/plan",
        json={"local_date": "2026-10-26", "said": "my secret chest story " * 40},
    )
    assert response.status_code == 422
    assert "secret chest story" not in response.text


def test_too_many_checkins_notes_or_readings_are_refused(client):
    days = [{"date": f"2026-09-{d:02d}"} for d in range(1, 30)]
    assert (
        client.post(
            "/api/coach/plan", json={"local_date": "2026-10-26", "checkins": days}
        ).status_code
        == 422
    )
    notes = [{"id": f"n{i}", "topic": "food"} for i in range(21)]
    assert (
        client.post(
            "/api/coach/plan", json={"local_date": "2026-10-26", "habit_notes": notes}
        ).status_code
        == 422
    )


# --- Blood pressure crisis edge ------------------------------------------------------------------------------


def reading(field, value, day="2026-10-25"):
    return {"field": field, "value": value, "unit": "mmHg", "date": day, "source": "typed"}


@pytest.mark.parametrize(
    ("readings", "alert"),
    [
        ([reading("systolic_bp", 180)], True),
        ([reading("diastolic_bp", 120)], True),
        ([reading("systolic_bp", 179), reading("diastolic_bp", 119)], False),
        ([reading("systolic_bp", 190, "2026-10-10")], False),  # older than a week
        ([reading("systolic_bp", 190, "2026-10-19")], True),  # seven days ago
        ([reading("systolic_bp", 190, "2026-10-12"), reading("systolic_bp", 120)], False),
    ],
)
def test_blood_pressure_crisis_edge(client, readings, alert):
    body = plan(client, {"age": 60, "exercise_minutes_weekly": 60}, readings=readings)
    assert (body["alert"] == "bp_crisis") is alert
    if alert:
        assert body["movement_paused"] is True and workout(body) is None
        assert "911" in spoken(body) and "doctor" in spoken(body)
        assert body["mood"] == "concerned"
    else:
        assert body["alert"] is None

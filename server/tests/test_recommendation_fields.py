import pytest
from fastapi.testclient import TestClient

import lifetwin.onboarding  # noqa: F401  (import first: avoids a pre-existing import cycle)
from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import HabitNote
from lifetwin.recommendations.ideas import BY_ID, IDEAS
from lifetwin.recommendations.service import suggest

ALL_MISSING = [
    "smoking_status",
    "vigorous_recreation_min_week",
    "moderate_recreation_min_week",
    "sleep_hours",
    "sedentary_min_day",
]


@pytest.fixture(scope="module")
def client():
    return TestClient(create_app(Settings(_env_file=None)))


def post(client, profile, notes=None):
    body = client.post(
        "/api/recommendations", json={"profile": profile, "habit_notes": notes or []}
    )
    assert body.status_code == 200
    return body.json()


def test_missing_inputs_all_in_ranking_order(client):
    out = post(client, {})
    assert out["status"] == "not_enough_information"
    assert out["missing_inputs"] == ALL_MISSING


def test_missing_inputs_only_the_empty_ones(client):
    out = post(
        client, {"age": 60, "smoking_status": "never", "sleep_hours": 8, "sedentary_min_day": 120}
    )
    assert out["status"] == "not_enough_information"
    assert out["missing_inputs"] == ["vigorous_recreation_min_week", "moderate_recreation_min_week"]


def test_missing_inputs_empty_when_ok(client):
    out = post(client, {"smoking_status": "current"})
    assert out["status"] == "ok"
    assert out["missing_inputs"] == []


def targets(**profile):
    return {
        r.lever: (r.experiment_lever, r.experiment_target)
        for r in suggest(HealthProfile(**profile), [])
    }


def test_targets_per_lever():
    found = targets(
        age=55,
        smoking_status="current",
        sleep_hours=6,
        moderate_recreation_min_week=60,
        vigorous_recreation_min_week=20,
    )
    assert found["quit_smoking"] == ("smoking_status", "former")
    assert found["short_sleep_plus_1h"] == ("sleep_hours", 7)
    assert found["moderate_plus_90"] == ("moderate_recreation_min_week", 150)
    assert targets(sedentary_min_day=480)["sitting_minus_60_realistic"] == (
        "sedentary_min_day",
        420,
    )


def test_vigorous_target_for_walkers():
    found = targets(moderate_recreation_min_week=60, vigorous_recreation_min_week=0)
    assert found["vigorous_plus_60"] == ("vigorous_recreation_min_week", 60)


def test_guideline_only_item_has_no_lever():
    items = suggest(HealthProfile(moderate_recreation_min_week=200), [])
    keep = next(r for r in items if r.lever == "keep_it_up")
    assert keep.experiment_lever is None and keep.experiment_target is None


def test_sitting_target_never_negative():
    found = targets(sedentary_min_day=300)
    assert found["sitting_minus_60_realistic"][1] == 240


def test_why_short_templates_are_short_and_number_free():
    for text in (idea.why for idea in IDEAS):
        assert 0 < len(text) <= 90
        assert not any(ch.isdigit() for ch in text)


def test_why_short_on_every_produced_item():
    profiles = [
        {"smoking_status": "current", "sleep_hours": 5, "sedentary_min_day": 600},
        {"moderate_recreation_min_week": 0},
        {"moderate_recreation_min_week": 60, "vigorous_recreation_min_week": 0},
        {"moderate_recreation_min_week": 30},
        {"moderate_recreation_min_week": 300},
    ]
    for profile in profiles:
        for rec in suggest(HealthProfile(**profile), []):
            assert rec.why_short and len(rec.why_short) <= 90


def test_activity_kind_only_uses_enjoy_template():
    recs = suggest(HealthProfile(), [HabitNote(topic="exercise", kind="walking")])
    assert recs[0].lever == "moderate_plus_90" and "more" in BY_ID[recs[0].id].stages
    assert recs[0].message.startswith("You said you enjoy walking.")


def test_source_domain():
    recs = suggest(HealthProfile(smoking_status="current", sleep_hours=5), [])
    assert {r.source_domain for r in recs} == {"cdc.gov"}


def test_under_18_is_treated_normally(client):
    out = post(client, {"age": 17, "smoking_status": "current"})
    assert out["status"] == "ok"
    assert out["recommendations"]


def test_existing_fields_unchanged(client):
    coping = [idea.id for idea in IDEAS if idea.coping]  # set aside: show the habit change
    out = client.post(
        "/api/recommendations",
        json={
            "profile": {"age": 70, "sex": "male", "smoking_status": "current"},
            "excluded_ids": coping,
        },
    ).json()
    rec = out["recommendations"][0]
    # The id is now the catalog idea's id; the lever and its card are unchanged.
    assert rec["lever"] == "quit_smoking" and BY_ID[rec["id"]].lever == "quit_smoking"
    assert rec["title"] == BY_ID[rec["id"]].title
    assert rec["effect"] == "big"
    assert rec["wellness_card"] == "smoking"
    assert rec["source_url"] == "https://www.cdc.gov/tobacco/about/"
    assert rec["causal_interpretation"] is False
    assert out["lever_ranking"]["order"][0] == "quit_smoking"
    assert out["message"].startswith("Here are a few ideas")


def test_missing_current_value_gives_null_target_not_a_default():
    found = targets(moderate_recreation_min_week=60)
    assert found["vigorous_plus_60"] == ("vigorous_recreation_min_week", None)
    assert targets(sleep_hours=None, exercise_minutes_weekly=0)["moderate_plus_90"] == (
        "moderate_recreation_min_week",
        None,
    )
    assert targets(smoking_status="current")["quit_smoking"] == ("smoking_status", "former")


def test_document_context_is_accepted_and_changes_nothing(client):
    profile = {"age": 50, "smoking_status": "current"}
    context = {
        "readings": [
            {"field": "a1c", "value": 6.1, "unit": "%", "date": "2026-09-14", "source": "document"}
        ],
        "diagnoses": ["diabetes"],
    }
    plain = client.post("/api/recommendations", json={"profile": profile})
    with_context = client.post(
        "/api/recommendations", json={"profile": profile, "document_context": context}
    )
    assert with_context.status_code == 200
    assert with_context.json() == plain.json()

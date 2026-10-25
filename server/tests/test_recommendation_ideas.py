"""The idea catalog behind "Ideas for you": integrity, limitations, personal fit, daily
rotation, alternatives, kind and featured, and that every old rule still holds."""

import random
import re
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from test_critical_recommendations import (
    FORBIDDEN,
    SUPPLEMENTS,
    check_product_rules,
    random_profiles,
)

import lifetwin.onboarding  # noqa: F401  (import first: avoids a pre-existing import cycle)
from lifetwin.app import create_app
from lifetwin.coach.models import LimitTag
from lifetwin.coach.planner import NOTE_LIMITS as COACH_NOTE_LIMITS
from lifetwin.coach.safety import NUMBER_WORDS
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import HabitNote, IdeaKind
from lifetwin.personalize.safety import safe_line
from lifetwin.recommendations import service
from lifetwin.recommendations.ideas import (
    AGE_BANDS,
    ALL_AGES,
    BY_ID,
    IDEAS,
    INTEREST_PATTERNS,
    INTERESTS,
    KINDS,
    LIMIT_TAGS,
    NOTE_LIMITS,
    TIMES,
)
from lifetwin.recommendations.levers import EFFECT_NOTE, LEVER_ORDER, effect_category
from lifetwin.recommendations.service import SOURCES, suggest

STAGES = {
    "quit_smoking": {"any"},
    "short_sleep_plus_1h": {"any"},
    "sitting_minus_60_realistic": {"any"},
    "vigorous_plus_60": {"pace"},
    "moderate_plus_90": {"start", "more"},
    "keep_it_up": {"keep"},
}
CARDS = {
    "quit_smoking": "smoking",
    "short_sleep_plus_1h": "sleep",
    "sitting_minus_60_realistic": "sitting",
}
# Medical claims and advice the catalog never makes (the outside-AI denylist this
# catalog was first checked against, kept here now that outside wording is bound to
# the draft itself).
MEDICAL = re.compile(
    r"\b(?:diagnos\w*|prescri\w*|medicat\w*|medicine\w*|pills?|tablets?|doses?|dosage|mg|"
    r"cure\w*|treat\w*|heals?|prevents?|reverses?|risk of|chance of|die|dying|death|"
    r"diet\w*|calories|fat|slim\w*|belly|waist\w*|stimulants?|herbal|will feel|"
    r"stop taking|start taking|increase your|decrease your|next (?:week|month)|by the end)\b",
    re.I,
)
DAYS = [date(2026, 10, 24) + timedelta(days=n) for n in range(7)]
NOTE_POOL = [
    {"topic": "exercise", "kind": "walking", "with": "dog"},
    {"topic": "exercise", "kind": "walking", "with": "grandkids"},
    {"topic": "exercise", "kind": "gardening", "time_of_day": "morning"},
    {"topic": "exercise", "kind": "dancing", "with": "friends"},
    {"topic": "exercise", "kind": "swimming", "with": "alone"},
    {"topic": "exercise", "kind": "cycling"},
    {"topic": "exercise", "kind": "walking", "barrier": "knee pain"},
    {"topic": "exercise", "kind": "walking", "barrier": "cold weather"},
    {"topic": "exercise", "barrier": "fear of falling"},
    {"topic": "exercise", "barrier": "short of breath"},
    {"topic": "exercise", "kind": "walking", "with": "my cane"},
    {"topic": "health", "concern": "I use a wheelchair"},
    {"topic": "health", "concern": "my heart"},
    {"topic": "health", "concern": "balance"},
    {"topic": "sitting", "kind": "tv"},
    {"topic": "sitting", "kind": "reading"},
    {"topic": "sitting", "kind": "computer"},
    {"topic": "sitting", "kind": "driving"},
    {"topic": "sitting", "kind": "puzzles"},
    {"topic": "sleep", "bedtime": "midnight", "wakes_for": "worry"},
    {"topic": "sleep", "naps": "after lunch"},
    {"topic": "smoking", "tried_quitting": "yes", "quit_aid": "patch"},
    {"topic": "smoking", "time_of_day": "after dinner"},
]


def client() -> TestClient:
    return TestClient(
        create_app(
            Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
        )
    )


def notes_of(*raw: dict) -> list[HabitNote]:
    return [HabitNote.model_validate(note) for note in raw]


def random_cases(count: int, seed: int):
    rng = random.Random(seed)
    for profile in random_profiles(count, seed):
        raw = rng.sample(NOTE_POOL, rng.randint(0, 3))
        yield profile, raw


def own_effect(item, profile: dict):
    if item.lever == "keep_it_up" or BY_ID[item.id].coping:
        return None
    return effect_category(item.lever, profile.get("age"), profile.get("sex"))


def shown(recs):
    for rec in recs:
        yield rec
        yield from rec.alternatives


# --- Catalog integrity ------------------------------------------------------------------


def test_the_catalog_is_big_and_every_lever_has_several_ideas():
    assert len(IDEAS) >= 50
    assert len(BY_ID) == len(IDEAS)  # ids are unique
    for lever in [*LEVER_ORDER, "keep_it_up"]:
        assert len([i for i in IDEAS if i.lever == lever]) >= 8, lever


def test_every_idea_is_well_formed_cited_and_tagged():
    for idea in IDEAS:
        assert set(idea.stages) <= STAGES[idea.lever] and idea.stages, idea.id
        assert idea.card == CARDS.get(idea.lever, "activity")
        assert idea.source in SOURCES and SOURCES[idea.source][1].startswith("https://www.cdc.gov/")
        assert idea.kind in KINDS, idea.id
        assert idea.ages and set(idea.ages) <= set(AGE_BANDS), idea.id
        assert set(idea.interests) <= set(INTERESTS), idea.id
        assert set(idea.times) <= set(TIMES), idea.id
        assert set(idea.avoid) <= set(LIMIT_TAGS), idea.id
        assert idea.social in {"social", "solo", "either"}
        assert idea.place in {"indoor", "outdoor", "either"}
        assert not idea.needs or idea.interests, idea.id
        assert re.fullmatch(r"[a-z0-9_]{1,60}", idea.id)


def test_lengths_and_the_safety_check_on_every_line():
    for idea in IDEAS:
        assert 0 < len(idea.title) <= 80, idea.id
        assert 0 < len(idea.message) <= 300, idea.id  # room for the person's own words
        assert 0 < len(idea.why) <= 90, idea.id
        assert not re.search(r"\d", idea.why) and not NUMBER_WORDS.search(idea.why), idea.id
        for text in (idea.title, idea.message, idea.why):
            assert safe_line(text, text), (idea.id, text)  # a valid trusted draft
            assert not MEDICAL.search(text), (idea.id, text)
            assert not FORBIDDEN.search(text), (idea.id, text)
            assert not SUPPLEMENTS.search(text), (idea.id, text)


def test_titles_are_at_most_four_words_and_why_short_at_most_ten():
    for idea in IDEAS:
        assert len(idea.title.split()) <= 4, (idea.id, idea.title)
        assert len(idea.why.split()) <= 10, (idea.id, idea.why)


def test_coping_tricks_are_flagged_and_every_lever_keeps_a_habit_change():
    assert BY_ID["smoke_delay"].coping and BY_ID["smoke_slow_breaths"].coping
    assert not BY_ID["smoke_quitline"].coping
    for lever, stages in STAGES.items():
        if lever == "keep_it_up":
            continue
        for stage in stages:
            core = [i for i in IDEAS if i.lever == lever and stage in i.stages and not i.coping]
            assert core, (lever, stage)


def test_encouragement_never_asks_for_more():
    for idea in IDEAS:
        if idea.lever == "keep_it_up":
            assert "more" not in idea.message.lower(), idea.id


def test_kinds_and_limit_tags_match_the_contract_and_the_coach():
    assert set(KINDS) == set(IdeaKind.__args__)
    assert set(LIMIT_TAGS) == set(LimitTag.__args__)
    assert {k: p.pattern for k, p in NOTE_LIMITS.items()} == {
        k: p.pattern for k, p in COACH_NOTE_LIMITS.items()
    }
    assert set(INTEREST_PATTERNS) <= set(INTERESTS)


def test_every_lever_and_stage_has_an_idea_that_fits_anyone():
    for lever, stages in STAGES.items():
        for stage in stages:
            if stage == "pace":
                continue  # only for walkers with no limitation at all
            assert any(
                stage in i.stages
                and i.lever == lever
                and not i.avoid
                and not i.needs
                and i.ages == ALL_AGES
                for i in IDEAS
            ), (lever, stage)


# --- Limitations: an idea they rule out is never shown ------------------------------------


def coach_limits(raw: list[dict]) -> set[str]:
    text = " ".join(str(v) for note in raw for k, v in note.items() if k != "topic").lower()
    return {tag for tag, pattern in COACH_NOTE_LIMITS.items() if pattern.search(text)}


def test_contraindicated_ideas_are_never_shown_property_sweep():
    checked = 0
    for profile, raw in random_cases(1500, 7):
        limits = coach_limits(raw)
        day = DAYS[checked % 7]
        for rec in shown(suggest(HealthProfile(**profile), notes_of(*raw), day)):
            idea = BY_ID[rec.id]
            assert not limits & set(idea.avoid), (rec.id, limits, raw)
            if limits:
                assert rec.lever != "vigorous_plus_60", (rec.id, raw)
            checked += 1
    assert checked > 1000


@pytest.mark.parametrize(
    "note,tag",
    [
        ({"topic": "health", "concern": "I use a wheelchair"}, "seated_only"),
        ({"topic": "exercise", "barrier": "knee pain"}, "knee_pain"),
        ({"topic": "exercise", "barrier": "fear of falling"}, "fall_risk"),
        ({"topic": "exercise", "barrier": "short of breath"}, "cardio_caution"),
        ({"topic": "exercise", "kind": "walking", "with": "my cane"}, "walking_aid"),
    ],
)
def test_each_limit_rules_out_its_ideas_on_every_day(note, tag):
    profile = HealthProfile(
        age=70, smoking_status="current", moderate_recreation_min_week=0, sleep_hours=5,
        sedentary_min_day=700,
    )  # fmt: skip
    for day in DAYS:
        for rec in shown(suggest(profile, notes_of(note), day)):
            assert tag not in BY_ID[rec.id].avoid, (rec.id, tag)


def test_ages_only_see_ideas_for_their_band():
    for profile, raw in random_cases(600, 11):
        age = profile.get("age")
        for rec in shown(suggest(HealthProfile(**profile), notes_of(*raw), DAYS[0])):
            idea = BY_ID[rec.id]
            if age is not None:
                band = "18-39" if age < 40 else "40-64" if age < 65 else "65+"
                assert band in idea.ages, (rec.id, age)
            elif idea.ages != ALL_AGES:
                assert idea.needs, rec.id


# --- Personal fit ---------------------------------------------------------------------------


def test_a_dog_walker_gets_a_dog_idea_every_day():
    walker = HealthProfile(age=55, moderate_recreation_min_week=60, vigorous_recreation_min_week=0)
    notes = notes_of({"topic": "exercise", "kind": "walking", "with": "dog"})
    for day in DAYS:
        (rec,) = suggest(walker, notes, day)
        assert "dog" in BY_ID[rec.id].interests, (day, rec.id)
        assert "your dog" in rec.message
    # A dog walker with sore knees: no brisk dog walk, still something kind.
    sore = notes_of({"topic": "exercise", "kind": "walking", "with": "dog", "barrier": "knee pain"})
    for day in DAYS:
        (rec,) = suggest(walker, sore, day)
        assert rec.lever == "moderate_plus_90" and "knee_pain" not in BY_ID[rec.id].avoid


def test_people_without_a_dog_never_get_a_dog_idea():
    for day in DAYS:
        for rec in shown(suggest(HealthProfile(age=55, moderate_recreation_min_week=60), [], day)):
            assert "dog" not in BY_ID[rec.id].interests or not BY_ID[rec.id].needs


def test_grandkids_get_a_grandkids_idea():
    profile = HealthProfile(age=68, moderate_recreation_min_week=0)
    notes = notes_of({"topic": "exercise", "with": "grandkids"})
    for day in DAYS:
        (rec,) = suggest(profile, notes, day)
        assert "grandkids" in BY_ID[rec.id].interests, (day, rec.id)


def test_tv_sitting_gets_a_tv_idea():
    profile = HealthProfile(age=60, sedentary_min_day=600)
    notes = notes_of({"topic": "sitting", "kind": "tv"})
    seen = set()
    for day in DAYS:
        (rec,) = suggest(profile, notes, day)
        assert "tv" in BY_ID[rec.id].interests, (day, rec.id)
        seen.add(rec.id)
    assert "sit_ad_breaks" in seen


def test_cold_weather_prefers_indoor_ideas():
    profile = HealthProfile(age=60, moderate_recreation_min_week=0)
    notes = notes_of({"topic": "exercise", "barrier": "cold weather"})
    for day in DAYS:
        (rec,) = suggest(profile, notes, day)
        assert BY_ID[rec.id].place != "outdoor", rec.id
        assert rec.message.startswith("You mentioned cold weather.")


def test_the_person_s_words_still_open_the_idea():
    smoker = HealthProfile(smoking_status="current")
    (rec,) = suggest(smoker, notes_of(NOTE_POOL[21]), DAYS[0])
    assert rec.message.startswith("You told me you've tried quitting before, with the patch.")
    for day in DAYS:
        (rec,) = suggest(smoker, [], day)
        assert "1-800-QUIT-NOW" in rec.message
        (rec,) = suggest(HealthProfile(sleep_hours=6), notes_of(NOTE_POOL[19]), day)
        assert "midnight" in rec.message and "worry" in rec.message


# --- Daily rotation ----------------------------------------------------------------------


def test_the_same_day_is_stable_and_other_days_differ():
    profile = HealthProfile(
        age=50, smoking_status="current", exercise_minutes_weekly=0, sleep_hours=5,
        sedentary_min_day=700,
    )  # fmt: skip
    first = [r.model_dump() for r in suggest(profile, [], "2026-10-24")]
    assert first == [r.model_dump() for r in suggest(profile, [], date(2026, 10, 24))]
    week = {tuple(r.id for r in suggest(profile, [], day)) for day in DAYS}
    assert len(week) >= 5
    for lever in ("quit_smoking", "moderate_plus_90", "short_sleep_plus_1h"):
        ids = {r.id for day in DAYS for r in suggest(profile, [], day) if r.lever == lever}
        assert len(ids) >= 3, lever


def test_no_local_date_uses_today(monkeypatch):
    monkeypatch.setattr(service, "today", lambda: date(2026, 10, 24))
    profile = HealthProfile(smoking_status="current", sleep_hours=5)
    assert suggest(profile, []) == suggest(profile, [], "2026-10-24")


def test_variety_across_many_people_and_a_week():
    seen = set()
    for profile, raw in random_cases(200, 2026):
        for day in DAYS:
            seen |= {rec.id for rec in suggest(HealthProfile(**profile), notes_of(*raw), day)}
    assert len(seen) >= 30, len(seen)


# --- Every old rule, alternatives included ------------------------------------------------


def test_old_rules_hold_on_every_day_with_notes():
    for n, (profile, raw) in enumerate(random_cases(800, 99)):
        check_product_rules(profile)
        recs = suggest(HealthProfile(**profile), notes_of(*raw), DAYS[n % 7])
        assert len(recs) <= 3
        levers = [r.lever for r in recs]
        ranked = [LEVER_ORDER.index(lever) for lever in levers if lever != "keep_it_up"]
        assert ranked == sorted(ranked)
        if "keep_it_up" in levers:
            assert levers[-1] == "keep_it_up"
        if profile.get("smoking_status") == "current":
            assert levers[0] == "quit_smoking"
        if "short_sleep_plus_1h" in levers:
            assert profile.get("sleep_hours") is not None and profile["sleep_hours"] < 7
        for rec in recs:
            assert len(rec.alternatives) <= 3
            ids = [rec.id] + [alt.id for alt in rec.alternatives]
            assert len(set(ids)) == len(ids)
            for item in shown([rec]):
                assert item.lever == rec.lever and item.wellness_card == rec.wellness_card
                assert item.kind in KINDS
                # The experiment follows the lever; the effect cue is the idea's own.
                assert (item.experiment_lever, item.experiment_target) == (
                    rec.experiment_lever,
                    rec.experiment_target,
                )
                assert item.effect == own_effect(item, profile)
                source_title, source_url = SOURCES[BY_ID[item.id].source]
                assert (item.source_title, item.source_url) == (source_title, source_url)
                assert item.source_domain == "cdc.gov"
                assert item.effect_note == EFFECT_NOTE and item.causal_interpretation is False
                assert 0 < len(item.message) <= 400
                assert safe_line(item.message, item.message), item.message
                assert not MEDICAL.search(item.message), item.message
                assert not FORBIDDEN.search(item.message) and not SUPPLEMENTS.search(item.message)
                assert 0 < len(item.why_short) <= 90
                if item.lever == "keep_it_up":
                    assert "more" not in item.message.lower().replace("keep it up", "")
                    assert item.kind in {"walk", "dance", "stretch"}
            assert not hasattr(rec.alternatives[0], "alternatives") if rec.alternatives else True


def test_a_small_start_for_none_on_every_day():
    for day in DAYS:
        (rec,) = suggest(HealthProfile(exercise_minutes_weekly=0), [], day)
        assert "start" in BY_ID[rec.id].stages and "10 to 15 minutes" in rec.message
        assert "150" not in rec.message


def test_encouragement_kind_follows_the_activity_it_praises():
    profile = HealthProfile(moderate_recreation_min_week=200)
    (rec,) = suggest(profile, notes_of({"topic": "exercise", "kind": "dancing"}), DAYS[0])
    assert rec.lever == "keep_it_up" and rec.kind == "dance"
    (rec,) = suggest(profile, [], DAYS[0])
    assert rec.kind == "walk"


# --- Over HTTP: alternatives, featured, local_date -----------------------------------------


def post(c, body):
    response = c.post("/api/recommendations", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def test_featured_is_stable_for_the_day_and_one_of_the_ids():
    c = client()
    body = {
        "profile": {"age": 60, "smoking_status": "current", "sleep_hours": 5,
                    "moderate_recreation_min_week": 200},
        "local_date": "2026-10-24",
    }  # fmt: skip
    first, again = post(c, body), post(c, body)
    assert first["featured"] == again["featured"]
    assert first["recommendations"] == again["recommendations"]
    ids = [r["id"] for r in first["recommendations"]]
    assert first["featured"] == ids[0] and first["recommendations"][0]["lever"] != "keep_it_up"
    for rec in first["recommendations"]:
        assert rec["kind"] in KINDS and len(rec["alternatives"]) <= 3
        for alt in rec["alternatives"]:
            assert "alternatives" not in alt and alt["kind"] in KINDS
    praise = post(c, {"profile": {"moderate_recreation_min_week": 300}, "local_date": "2026-10-24"})
    assert praise["featured"] == praise["recommendations"][0]["id"]


def test_featured_is_null_unless_ok():
    c = client()
    assert post(c, {"profile": {}})["featured"] is None
    assert post(c, {"profile": {"age": 16, "sleep_hours": 5}})["featured"] is None


@pytest.mark.parametrize("bad", ["2026-02-30", "24/10/2026", "tomorrow", 20261024])
def test_a_bad_local_date_is_refused(bad):
    response = client().post(
        "/api/recommendations", json={"profile": {"sleep_hours": 5}, "local_date": bad}
    )
    assert response.status_code == 422


# --- Excluded ids ------------------------------------------------------------------------


def test_excluded_ids_never_appear_property_sweep():
    rng = random.Random(5)
    ids = sorted(BY_ID)
    for n, (profile, raw) in enumerate(random_cases(800, 3)):
        excluded = set(rng.sample(ids, rng.randint(0, 50)))
        recs = suggest(HealthProfile(**profile), notes_of(*raw), DAYS[n % 7], sorted(excluded))
        for item in shown(recs):
            assert item.id not in excluded, (item.id, profile)
        assert service.featured(recs) not in excluded
        assert len(recs) <= 3


def test_every_idea_of_a_lever_excluded_falls_back_or_is_left_out():
    walker = HealthProfile(moderate_recreation_min_week=60, vigorous_recreation_min_week=0)
    pace = [i.id for i in IDEAS if i.lever == "vigorous_plus_60"]
    (rec,) = suggest(walker, [], DAYS[0], pace)
    assert rec.lever == "moderate_plus_90"  # a faster pace falls back to a little more
    activity = pace + [i.id for i in IDEAS if i.lever == "moderate_plus_90"]
    assert suggest(walker, [], DAYS[0], activity) == []
    smoker = HealthProfile(smoking_status="current", sleep_hours=5)
    smoking = [i.id for i in IDEAS if i.lever == "quit_smoking"]
    assert [r.lever for r in suggest(smoker, [], DAYS[0], smoking)] == ["short_sleep_plus_1h"]


def test_excluded_ids_over_http():
    c = client()
    body = {"profile": {"smoking_status": "current"}, "local_date": "2026-10-24"}
    first = post(c, body)
    gone = [first["featured"]] + [a["id"] for a in first["recommendations"][0]["alternatives"]]
    again = post(c, {**body, "excluded_ids": gone})
    assert again["featured"] not in gone
    for rec in again["recommendations"]:
        assert rec["id"] not in gone
        assert not {a["id"] for a in rec["alternatives"]} & set(gone)
    too_many = c.post("/api/recommendations", json={**body, "excluded_ids": ["x"] * 51})
    assert too_many.status_code == 422
    assert c.post("/api/recommendations", json={**body, "excluded_ids": [""]}).status_code == 422

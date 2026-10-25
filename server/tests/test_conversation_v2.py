"""Conversation v2: unknowns, proxies, probes, steering, memory, Health, suggestions.

End-to-end dialogues go through the public route. Their length is estimated as spoken:
Mochi at 2.8 words a second (about 170 words a minute, a usual TTS pace) and the person
at 1 second to start plus 0.4 seconds a word. The Apple Health screen is not counted.
"""

import asyncio
import json
import logging
import re
from datetime import date
from pathlib import Path

import conversation_eval
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.onboarding import ConversationService, get_service, router
from lifetwin.onboarding.habits import read_notes
from lifetwin.onboarding.model_inputs import character_hints, model_inputs
from lifetwin.onboarding.models import ConversationState as ConversationStateModel
from lifetwin.onboarding.models import HabitNote
from lifetwin.onboarding.probes import MAX_PROBES
from lifetwin.onboarding.script import (
    ASKED,
    BY_FIELD,
    SUPPLEMENT_REPLY,
    UNKNOWN_ACKS,
)
from lifetwin.personalize.providers import DISPLAY_NAMES, PhrasingUnavailable
from lifetwin.personalize.safety import safe_line
from lifetwin.recommendations.levers import LEVER_ORDER
from lifetwin.recommendations.models import RecommendationRequest
from lifetwin.recommendations.service import recommend, suggest

TODAY = date(2026, 10, 24)
ROOT = Path(__file__).resolve().parents[2]


def client_for(seed: int = 7, personalizer=None, max_probes: int = MAX_PROBES) -> TestClient:
    app = FastAPI()
    app.include_router(router, prefix="/api")
    service = ConversationService(
        clock=lambda: TODAY, seed=lambda: seed, personalizer=personalizer, max_probes=max_probes
    )
    app.dependency_overrides[get_service] = lambda: service
    return TestClient(app)


class Dialogue:
    """Plays a conversation and keeps the transcript and a spoken-time estimate."""

    def __init__(self, client: TestClient | None = None, **request):
        self.client = client or client_for()
        self.request = request
        self.lines: list[tuple[str, str]] = []
        self.result = self._send({"action": "start"})
        self.lines.append(("mochi", self.result["message"]))

    def _send(self, body: dict) -> dict:
        response = self.client.post("/api/onboarding/turn", json={**self.request, **body})
        assert response.status_code == 200, response.text
        return response.json()

    def say(self, text: str, mode: str = "transcript") -> dict:
        self.lines.append(("person", text))
        self.result = self._send(
            {"action": "reply", "state": self.state, "text": text, "input_mode": mode}
        )
        self.lines.append(("mochi", self.result["message"]))
        return self.result

    def health(self, **values) -> dict:
        self.result = self._send({"action": "import", "state": self.state, "values": values})
        self.lines.append(("mochi", self.result["message"]))
        return self.result

    @property
    def state(self) -> dict:
        return self.result["state"]

    def seconds(self) -> float:
        total = 0.0
        for who, text in self.lines:
            words = len(text.split())
            total += words / 2.8 if who == "mochi" else 1.0 + 0.4 * words
        return total


# -- held-out evals ---------------------------------------------------------------------


def test_held_out_set_a_scores_and_never_records_a_wrong_value():
    report = conversation_eval.score("a")
    assert report["cases"] >= 80
    assert report["wrong_values"] == 0
    assert report["total"].get("wrong", 0) == 0
    assert report["total"]["correct"] >= 108
    assert report["volunteered_notes"].get("wrong", 0) == 0


def test_held_out_set_b_scores_and_never_records_a_wrong_value():
    report = conversation_eval.score("b")
    assert report["wrong_values"] == 0
    assert report["total"].get("wrong", 0) == 0
    assert report["total"]["correct"] >= 38


# -- end-to-end dialogues ---------------------------------------------------------------


def test_demo_path_with_apple_health():
    d = Dialogue()
    assert d.state["phase"] == "remembering"
    d.say("Sure")
    assert d.state["memory_consent"] is True and d.state["current_field"] == "age"
    d.say("I'm 72, female, and I've never smoked")
    assert d.state["pending_profile"]["age"] == 72
    assert d.state["pending_profile"]["sex"] == "female"
    d.say("yes")
    assert d.state["phase"] == "offering"
    reply = d.say("yes please")
    assert reply["client_action"] == "open_health_import"
    d.health(height_cm=162.6, weight_kg=68, sleep_hours=6.5, exercise_minutes_weekly=90)
    assert d.state["health_offered"] is True
    assert d.state["phase"] == "probing" and d.state["current_probe"] == "activity"
    d.say("I walk my dog every morning")
    assert d.state["current_field"] == "general_health"
    d.say("Good")
    d.say("yes")
    assert d.state["current_probe"] == "sleep_pattern"  # short sleep, asked after it lost out
    d.say("Around midnight, and I get up for the bathroom")
    assert d.state["current_field"] == "hypertension_diagnosed"
    d.say("Not sure")
    assert "hypertension_diagnosed" in d.state["unknown_fields"]
    d.say("No")
    d.say("yes")
    d.say("About 7 hours, mostly TV")
    d.say("yes")
    # Apple Health's total: only the harder part is asked; the rest is lighter activity.
    assert d.state["current_field"] == "vigorous_recreation_min_week"
    assert "Apple Health shows about 90 minutes" in d.result["message"]
    d.say("None")
    assert d.state["pending_profile"]["moderate_recreation_min_week"] == 90
    end = d.say("yes")
    assert end["complete"] is True
    assert len(d.state["probes_asked"]) <= MAX_PROBES
    notes = {note["topic"]: note for note in d.state["habit_notes"]}
    assert notes["exercise"]["kind"] == "walking" and notes["exercise"]["with"] == "dog"
    assert notes["sleep"]["bedtime"] == "midnight" and notes["sleep"]["wakes_for"] == "bathroom"
    assert notes["sitting"]["kind"] == "tv"
    assert end["model_inputs"]["status"] == "still_learning"
    assert end["model_inputs"]["unknown"] == ["hypertension_diagnosed"]
    assert end["model_inputs"]["missing"] == ["hypertension_diagnosed"]
    levers = [rec["lever"] for rec in end["recommendations"]]
    assert levers == ["vigorous_plus_60", "short_sleep_plus_1h", "sitting_minus_60_realistic"]
    assert "dog" in end["message"]
    # Spoken length: about two and a half minutes, Apple Health screen not counted.
    assert d.seconds() < 150, d.seconds()


def test_short_demo_setting_asks_one_follow_up_in_the_same_order():
    settings = Settings(onboarding_demo=True)
    assert create_app(settings).state.conversation_service.max_probes == 1
    assert create_app(Settings()).state.conversation_service.max_probes == MAX_PROBES
    d = Dialogue(client_for(max_probes=1))
    assert d.state["phase"] == "remembering"  # the memory question stays
    d.say("Sure")
    d.say("I'm 72, female, and I've never smoked")
    d.say("yes")
    assert d.state["phase"] == "offering"  # Apple Health right after age, sex and smoking
    assert d.say("yes please")["client_action"] == "open_health_import"
    d.health(height_cm=162.6, weight_kg=68, sleep_hours=6.5, exercise_minutes_weekly=90)
    assert d.state["current_probe"] == "activity"
    d.say("I walk my dog every morning")
    asked = []
    for _ in range(30):
        if d.result["complete"]:
            break
        state = d.state
        assert state["phase"] != "probing", "a second follow-up in the short demo"
        if state["phase"] == "confirming":
            d.say("yes")
            continue
        asked.append(state["current_field"])
        d.say(
            {
                "general_health": "Good",
                "hypertension_diagnosed": "No",
                "diabetes": "No",
                "sedentary_min_day": "About 7 hours, mostly TV",
                "vigorous_recreation_min_week": "None",
            }[state["current_field"]]
        )
    assert d.result["complete"] is True
    assert d.state["probes_asked"] == ["activity"]
    # The same order as without the setting.
    assert asked == [
        "general_health",
        "hypertension_diagnosed",
        "diabetes",
        "sedentary_min_day",
        "vigorous_recreation_min_week",
    ]
    assert d.result["model_inputs"]["status"] == "ready"
    # Spoken length estimate for the demo path, Apple Health screen not counted: about
    # 138 s, against 150 s with three follow-ups. The 75 s target needs more than the
    # follow-up limit (the read-backs and the opening and closing lines are most of it).
    assert d.seconds() < 145, d.seconds()


def test_without_apple_health_stays_near_four_minutes():
    d = Dialogue()
    for text in [
        "yes",
        "I'm 74",
        "yes",
        "male",
        "yes",
        "I quit years ago",
        "yes",
        "no thanks",
        "5 foot 9",
        "yes",
        "170 pounds",
        "yes",
        "7 hours",
        "yes",
        "fair",
        "yes",
        "my knees bother me",
        "yes",
        "yes",
        "no",
        "yes",
        "5 hours",
        "yes",
        "TV and reading",
        "about 2 hours a week",
        "yes",
        "gardening with my wife",
        "none",
        "yes",
    ]:
        if d.result["complete"]:
            break
        d.say(text)
    assert d.result["complete"] is True, d.lines[-4:]
    assert d.result["model_inputs"]["status"] == "ready"
    assert d.seconds() < 240, d.seconds()


def test_i_dont_know_path_asks_each_question_once_and_gives_no_number():
    d = Dialogue()
    d.say("no thanks")  # no memory: no notes, no follow-ups
    asked = []
    for _ in range(40):
        if d.result["complete"]:
            break
        field = d.state["current_field"] or d.state["phase"]
        asked.append((field, d.state["proxy_field"]))
        d.say("no thanks" if d.state["phase"] == "offering" else "I don't know")
    assert d.result["complete"] is True
    assert len(asked) == len(set(asked)), "a question was asked twice"
    assert {f for f, _ in asked if f in ASKED} == set(ASKED)
    assert set(d.state["unknown_fields"]) == set(ASKED)
    assert d.state["skipped_fields"] == []
    assert d.state["habit_notes"] == [] and d.state["probes_asked"] == []
    end = d.result
    assert end["model_inputs"]["status"] == "still_learning"
    assert all(value is None for value in end["model_inputs"]["profile"].values())
    assert len(end["model_inputs"]["unknown"]) == 11
    assert end["recommendations"] == []
    # Simpler questions were tried once each where they exist, then left.
    assert {f for f, proxy in asked if proxy} == {field for field in ASKED if BY_FIELD[field].proxy}


def test_person_who_volunteers_everything_at_once():
    d = Dialogue()
    d.say("yes")
    d.say(
        "I'm 70, male, I quit smoking 20 years ago, my health is good, I don't have "
        "diabetes, and I walk my dog every morning"
    )
    pending = {k: v for k, v in d.state["pending_profile"].items() if v is not None}
    assert pending == {
        "age": 70,
        "sex": "male",
        "smoking_status": "former",
        "general_health": "good",
        "diabetes": False,
    }
    assert any(note["topic"] == "exercise" for note in d.state["habit_notes"])
    d.say("yes")
    confirmed = d.state["confirmed_profile"]
    assert confirmed["age"] == 70 and confirmed["diabetes"] is False
    # "Quit 20 years ago" was already said, so the quitting follow-up is not asked.
    assert d.state["current_probe"] is None
    assert any(n.get("quit_ago") == "20 years" for n in d.state["habit_notes"])
    # Steered by their own words: the dog walks come next, before the Health offer.
    assert d.state["current_field"] == "moderate_recreation_min_week"
    assert "your dog" in d.result["message"]


def test_topic_jump_and_back():
    d = Dialogue()
    d.say("yes")
    d.say("71")
    d.say("yes")
    d.say("can we talk about my sleep?")
    assert d.state["current_field"] == "sleep_hours"
    assert d.result["message"].startswith("Sure, let's talk about your sleep.")
    d.say("about 6 hours")
    d.say("yes")
    assert d.state["confirmed_profile"]["sleep_hours"] == 6
    # Back to the default path where it was open.
    assert d.state["current_field"] in {"sex", None} or d.state["phase"] == "probing"
    d.say("go back")
    assert d.state["phase"] == "asking"


def test_emergency_mid_intake_pauses_then_carries_on():
    d = Dialogue()
    d.say("yes")
    d.say("I'm 80")
    d.say("yes")
    before = d.state
    paused = d.say("I think I'm having a heart attack")
    assert paused["emergency"] is True
    assert paused["state"] == before
    assert paused["quick_replies"] == []
    resumed = d.say("let's carry on")
    assert resumed["emergency"] is False
    assert resumed["state"]["current_field"] == before["current_field"]
    assert resumed["model_inputs"]["status"] == "unsupported_age"


def test_without_memory_there_are_no_notes_or_follow_ups():
    d = Dialogue()
    d.say("I'd rather not")
    assert d.state["memory_consent"] is False
    d.say("I'm 72 and I walk my dog every morning")
    d.say("yes")
    assert d.state["habit_notes"] == []
    assert d.state["phase"] == "asking" and d.state["probes_asked"] == []


@pytest.mark.parametrize(
    "text", ["yes", "sure", "of course", "that's fine", "please do", "yes remember", "okay"]
)
def test_memory_yes(text):
    d = Dialogue()
    d.say(text)
    assert d.state["memory_consent"] is True


@pytest.mark.parametrize(
    "text", ["no", "no thanks", "I'd rather not", "please don't", "just the answers", "nope"]
)
def test_memory_no(text):
    d = Dialogue()
    d.say(text)
    assert d.state["memory_consent"] is False
    assert d.state["current_field"] == "age"


# -- unknowns, proxies, blood pressure ----------------------------------------------------


def asking(field: str, **state) -> dict:
    return {"phase": "asking", "current_field": field, **state}


def reply(state: dict, text: str, client: TestClient | None = None) -> dict:
    client = client or client_for()
    response = client.post(
        "/api/onboarding/turn", json={"action": "reply", "state": state, "text": text}
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_unknown_is_acknowledged_kindly_and_once_says_still_learning():
    first = reply(asking("hypertension_diagnosed"), "no idea")
    assert any(first["message"].startswith(ack) for ack in UNKNOWN_ACKS)
    assert "still learning" in first["message"]
    second = reply(first["state"] | asking("diabetes"), "not sure")
    assert "still learning" not in second["message"]
    assert second["state"]["unknown_fields"] == ["hypertension_diagnosed", "diabetes"]


def test_sitting_proxy_is_an_estimate_read_back_honestly():
    asked = reply(asking("sedentary_min_day"), "no idea")
    assert asked["state"]["proxy_field"] == "sedentary_min_day"
    assert asked["quick_replies"] == list(BY_FIELD["sedentary_min_day"].proxy_replies)
    estimate = reply(asked["state"], "most of the day")
    assert estimate["state"]["pending_profile"]["sedentary_min_day"] == 600
    assert "rough estimate" in estimate["message"]
    saved = reply(estimate["state"], "yes")
    assert saved["state"]["estimated_fields"] == ["sedentary_min_day"]
    assert saved["model_inputs"]["estimated"] == ["sedentary_min_day"]
    note = next(n for n in saved["state"]["habit_notes"] if n["estimate_for"])
    assert note == {**note, "topic": "sitting", "estimate": "most of the day sitting"}


def test_a_reading_is_context_and_the_diagnosis_is_asked_once_more():
    first = reply(asking("hypertension_diagnosed"), "130 over 85 last week")
    assert first["state"]["current_field"] == "hypertension_diagnosed"
    assert first["state"]["pending_profile"]["systolic_bp"] is None
    assert "isn't the same as a diagnosis" in first["message"]
    second = reply(first["state"], "it was 128 over 80 at the pharmacy")
    assert "hypertension_diagnosed" in second["state"]["unknown_fields"]
    assert second["state"]["confirmed_profile"]["systolic_bp"] is None


@pytest.mark.parametrize(
    "text",
    [
        "Should I take vitamin D?",
        "what about fish oil",
        "do I need a multivitamin?",
        "Is turmeric good for my knees?",
        "can you recommend a supplement",
    ],
)
def test_supplement_questions_get_one_fixed_reply(text):
    result = reply(asking("general_health"), text)
    assert result["message"].startswith(SUPPLEMENT_REPLY)
    assert result["state"] == {**result["state"], **asking("general_health")}
    assert not re.search(r"\b\d+\s?(?:mg|iu|mcg)\b", result["message"], re.I)


def test_a_supplement_said_as_a_fact_is_not_a_question():
    result = reply(asking("general_health"), "I take vitamin D and my health is good")
    assert not result["message"].startswith(SUPPLEMENT_REPLY)


@pytest.mark.parametrize("field", [f for f in ASKED if BY_FIELD[f].quick_replies])
def test_every_quick_reply_is_understood(field):
    for text in BY_FIELD[field].quick_replies:
        result = reply(asking(field), text)
        state = result["state"]
        known = state["pending_profile"].get(field) is not None or state["phase"] == "confirming"
        assert known or field in state["unknown_fields"] or state["proxy_field"] == field, (
            field,
            text,
            result["message"],
        )


def test_wording_varies_by_session_and_stays_the_same_for_one_session():
    first = Dialogue(client_for(seed=1))
    first.say("yes")
    messages = set()
    for seed in range(1, 12):
        d = Dialogue(client_for(seed=seed))
        d.say("yes")
        d.say("72")
        messages.add(d.say("yes")["message"])
    assert len(messages) > 2
    again = Dialogue(client_for(seed=1))
    again.say("yes")
    assert again.result["message"] == first.result["message"]


# -- model inputs and character hints -----------------------------------------------------


def test_model_inputs_use_the_packages_codes():
    profile = HealthProfile(
        age=72,
        sex="female",
        height_cm=160,
        weight_kg=60,
        smoking_status="former",
        diabetes=False,
        hypertension_diagnosed=True,
        general_health="very_good",
        sleep_hours=7,
        vigorous_recreation_min_week=0,
        moderate_recreation_min_week=150,
        sedentary_min_day=480,
    )
    result = model_inputs(profile)
    assert result.status == "ready" and result.missing == []
    assert result.profile.model_dump() == {
        "age": 72,
        "sex_nhanes": 2,
        "height_cm": 160,
        "weight_kg": 60,
        "smoking_status": 1,
        "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 1,
        "general_health": 2,
        "sleep_hours": 7,
        "vigorous_recreation_min_week": 0,
        "moderate_recreation_min_week": 150,
        "sedentary_min_day": 480,
    }


def test_model_inputs_never_fill_in_and_send_height_and_weight_together():
    result = model_inputs(HealthProfile(age=82, height_cm=170, sleep_hours=13))
    assert result.status == "unsupported_age"
    assert result.profile.height_cm is None and result.profile.weight_kg is None
    assert result.profile.sleep_hours is None  # outside the package's 2-12 entry range
    assert "bmi" in result.missing and "sleep_hours" in result.missing
    unknown = model_inputs(
        HealthProfile(smoking_status="unknown"), unknown=["hypertension_diagnosed"]
    )
    assert unknown.unknown == ["hypertension_diagnosed", "smoking_status"]
    assert unknown.profile.smoking_status is None


def test_character_hints_are_coarse_and_kind():
    assert character_hints(HealthProfile(), []).model_dump() == {"mood": None, "energy": None}
    active = HealthProfile(general_health="good", moderate_recreation_min_week=200, sleep_hours=7)
    assert character_hints(active, []).model_dump() == {"mood": "good", "energy": "high"}
    tired = HealthProfile(general_health="poor", moderate_recreation_min_week=60, sleep_hours=5)
    assert character_hints(tired, []).model_dump() == {"mood": "not_great", "energy": "low"}
    worried = [HabitNote(topic="health", feeling="worried")]
    assert character_hints(active, worried).mood == "not_great"
    assert character_hints(HealthProfile(sleep_hours=8), []).energy == "medium"


# -- recommendations ----------------------------------------------------------------------

UNSAFE = re.compile(
    r"\b(?:years?|lifespan|live longer|death|die|cure|guarantee|percent|weight|"
    r"supplement|vitamin|dose|mg)\b|%",
    re.I,
)


def recs(**profile) -> list:
    notes = profile.pop("notes", [])
    return suggest(HealthProfile(**profile), notes)


def test_smoking_comes_first_with_quit_support():
    found = recs(smoking_status="current", sleep_hours=6, moderate_recreation_min_week=0)
    assert found[0].lever == "quit_smoking"
    assert "1-800-QUIT-NOW" in found[0].message
    assert found[0].source_url == "https://www.cdc.gov/tobacco/about/"


def test_inactive_people_get_a_small_start():
    found = recs(moderate_recreation_min_week=0, vigorous_recreation_min_week=0)
    assert found[0].lever == "moderate_plus_90"
    assert "10 to 15 minutes" in found[0].message


def test_active_people_get_encouragement_not_more_minutes():
    found = recs(moderate_recreation_min_week=200, vigorous_recreation_min_week=0)
    assert [rec.lever for rec in found] == ["keep_it_up"]
    assert "Keep it up" in found[0].message


def test_walkers_may_pick_up_the_pace_unless_something_hurts():
    walk = HabitNote(topic="exercise", kind="walking", **{"with": "dog"})
    found = recs(moderate_recreation_min_week=60, vigorous_recreation_min_week=0, notes=[walk])
    assert found[0].lever == "vigorous_plus_60" and "your dog" in found[0].message
    sore = HabitNote(topic="exercise", kind="walking", barrier="knee pain")
    found = recs(moderate_recreation_min_week=60, vigorous_recreation_min_week=0, notes=[sore])
    assert found[0].lever == "moderate_plus_90"
    assert "about 150 minutes" in found[0].message  # 60 now, three more 30-minute walks


def test_sleep_advice_only_under_seven_hours():
    assert [rec.lever for rec in recs(sleep_hours=6)] == ["short_sleep_plus_1h"]
    assert recs(sleep_hours=7) == [] and recs(sleep_hours=9) == []


def test_never_weight_never_years_and_at_most_three():
    profiles = [
        dict(
            smoking_status="current",
            sleep_hours=5,
            moderate_recreation_min_week=0,
            sedentary_min_day=600,
            weight_kg=120,
            height_cm=160,
        ),  # fmt: skip
        dict(
            moderate_recreation_min_week=60,
            vigorous_recreation_min_week=0,
            sleep_hours=6,
            sedentary_min_day=480,
        ),  # fmt: skip
        dict(weight_kg=140, height_cm=165),
    ]
    for profile in profiles:
        found = recs(**profile)
        assert len(found) <= 3
        for rec in found:
            assert not UNSAFE.search(rec.message), rec.message
            assert rec.causal_interpretation is False
            assert rec.source_url.startswith("https://www.cdc.gov/")
    assert recs(weight_kg=140, height_cm=165) == []


def test_lever_order_matches_the_sensitivity_scan_when_present():
    for path in (
        ROOT / "docs" / "model-sensitivity.json",
        ROOT.parent / "model-sensitivity" / "docs" / "model-sensitivity.json",
    ):
        if path.exists():
            groups = json.loads(path.read_text())["groups"]
            for group in groups.values():
                order = [row["lever"] for row in group["recommendable_levers_ranked"]]
                assert tuple(order) == LEVER_ORDER
            return
    pytest.skip("docs/model-sensitivity.json is not on this branch")


def test_recommendations_route_is_stateless_and_template_by_default():
    client = TestClient(create_app(Settings(_env_file=None, app_env="test")))
    body = {
        "profile": {
            "sleep_hours": 6,
            "moderate_recreation_min_week": 0,
            "vigorous_recreation_min_week": 0,
        },
        "habit_notes": [{"topic": "sleep", "bedtime": "midnight"}],
    }
    response = client.post("/api/recommendations", json=body)
    assert response.status_code == 200
    result = response.json()
    assert result["status"] == "ok" and result["phrased_by"] == "templates"
    assert [rec["lever"] for rec in result["recommendations"]] == [
        "moderate_plus_90",
        "short_sleep_plus_1h",
    ]
    assert "midnight" in result["recommendations"][1]["message"]


# -- habit notes --------------------------------------------------------------------------


def test_someone_elses_habit_is_not_the_persons_note():
    result = reply(asking("age", memory_consent=True), "My wife walks every morning. I'm 70")
    assert all(note["topic"] != "exercise" for note in result["state"]["habit_notes"])


def test_notes_only_hold_words_from_the_reply():
    text = "I swim with my friends on weekends but my shoulder hurts"
    note = read_notes(text, topic="exercise")[0]
    stems = {word[:4] for word in re.findall(r"[a-z]+", text.lower())}
    for value in note.model_dump(exclude_none=True, exclude={"topic", "source"}).values():
        assert all(word[:4] in stems or word in {"pain", "and"} for word in value.split()), value


# -- outside-AI phrasing ------------------------------------------------------------------


class FakeProvider:
    def __init__(self, name="muse", reply=None, fail=False):
        self.name = name
        self.calls: list[tuple[str, dict]] = []
        self._reply = reply
        self._fail = fail

    @property
    def configured(self) -> bool:
        return True

    async def phrase(self, instructions: str, facts: dict) -> dict:
        self.calls.append((instructions, facts))
        if self._fail:
            raise PhrasingUnavailable()
        if callable(self._reply):
            return self._reply(facts)
        return self._reply or {}


def finished_state() -> dict:
    return {
        "phase": "confirming",
        "memory_consent": True,
        "pending_profile": {"vigorous_recreation_min_week": 0},
        "confirmed_profile": {
            "age": 72,
            "sex": "female",
            "height_cm": 160,
            "weight_kg": 60,
            "smoking_status": "never",
            "diabetes": False,
            "hypertension_diagnosed": False,
            "general_health": "good",
            "sleep_hours": 6,
            "moderate_recreation_min_week": 60,
            "sedentary_min_day": 300,
        },
        "habit_notes": [
            {"topic": "exercise", "kind": "walking", "with": "dog"},
            {"topic": "sleep", "bedtime": "midnight"},
        ],
        "health_offered": True,
    }


def confirm(client, **request) -> dict:
    response = client.post(
        "/api/onboarding/turn",
        json={"action": "confirm", "state": finished_state(), **request},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_without_consent_nothing_is_sent():
    provider = FakeProvider()
    result = confirm(client_for(personalizer=provider))
    assert provider.calls == []
    assert result["phrased_by"] == "templates" and result["recommendations"]


def test_consent_for_another_provider_does_not_count():
    provider = FakeProvider(name="muse")
    result = confirm(client_for(personalizer=provider), outside_ai_consent={"claude": True})
    assert provider.calls == []
    assert result["phrased_by"] == "templates"


def test_consent_sends_answers_and_their_words_but_never_a_name(caplog):
    lines = lambda facts: {  # noqa: E731
        "lines": [f"Lovely walks with your dog! {item['draft']}" for item in facts["items"]]
    }
    provider = FakeProvider(reply=lines)
    with caplog.at_level(logging.DEBUG):
        result = confirm(client_for(personalizer=provider), outside_ai_consent={"muse": True})
    assert len(provider.calls) == 1
    instructions, facts = provider.calls[0]
    assert "never add numbers" in instructions
    sent = json.dumps(facts)
    assert "dog" in sent and "moderate_recreation_min_week" in sent
    assert not re.search(r"\b(?:name|email|phone|address)\b", sent)
    assert result["phrased_by"] == "muse"
    assert result["recommendations"][0]["message"].startswith("Lovely walks with your dog!")
    assert "Lovely walks" in result["message"]
    assert "dog" not in caplog.text and "moderate" not in caplog.text


@pytest.mark.parametrize(
    "line",
    [
        "Walking more could add 3 years to your life.",
        "Try 1000 IU of vitamin D with your walks.",
        "This will cure your blood pressure.",
        "Walk 45 minutes a day and lose weight.",
        "Studies show a 20% lower risk.",
        "See https://example.com for more.",
    ],
)
def test_unsafe_provider_lines_fall_back_to_the_template(line):
    provider = FakeProvider(reply=lambda facts: {"lines": [line] * len(facts["items"])})
    result = confirm(client_for(personalizer=provider), outside_ai_consent={"muse": True})
    template = confirm(client_for())
    assert result["phrased_by"] == "templates"
    assert result["recommendations"] == template["recommendations"]
    assert not safe_line(line, "{}")


def test_provider_outage_uses_the_template():
    provider = FakeProvider(fail=True)
    result = confirm(client_for(personalizer=provider), outside_ai_consent={"muse": True})
    assert result["phrased_by"] == "templates" and result["recommendations"]


def test_provider_may_rephrase_a_question_but_never_a_read_back():
    provider = FakeProvider(reply={"line": "And do you sleep well, about how many hours a night?"})
    client = client_for(personalizer=provider)
    consent = {"muse": True}
    response = client.post(
        "/api/onboarding/turn",
        json={
            "action": "reply",
            "state": asking("general_health", memory_consent=True),
            "text": "can we talk about my sleep",
            "outside_ai_consent": consent,
        },
    )
    result = response.json()
    assert result["phrased_by"] == "muse"
    assert result["message"].endswith("about how many hours a night?")
    read_back = client.post(
        "/api/onboarding/turn",
        json={
            "action": "reply",
            "state": result["state"],
            "text": "7 hours",
            "outside_ai_consent": consent,
        },
    ).json()
    assert read_back["phrased_by"] == "templates"
    assert read_back["message"] == "I heard you sleep 7 hours a night. Is that right?"


def test_recommendations_route_uses_only_the_consented_active_provider():
    provider = FakeProvider(reply=lambda facts: {"lines": [i["draft"] for i in facts["items"]]})
    body = RecommendationRequest(
        profile=HealthProfile(sleep_hours=6), outside_ai_consent={"claude": True}
    )
    assert asyncio.run(recommend(body, provider)).phrased_by == "templates"
    assert provider.calls == []
    body = body.model_copy(update={"outside_ai_consent": {"muse": True}})
    assert asyncio.run(recommend(body, provider)).phrased_by == "muse"


@pytest.mark.parametrize(("setting", "name"), [("muse", "muse"), ("claude", "claude")])
def test_capabilities_name_the_provider_that_would_be_called(setting, name):
    app = create_app(Settings(_env_file=None, app_env="test", personalize_provider=setting))
    personalize = TestClient(app).get("/api/capabilities").json()["personalize"]
    assert personalize == {
        "provider": name,
        "display_name": DISPLAY_NAMES[name],
        "may_train_on_content": False,
        "company": {"muse": "Meta", "claude": "Anthropic"}[name],
        "configured": False,
    }
    assert app.state.personalizer.name == name
    assert app.state.conversation_service.personalizer is app.state.personalizer
    assert DISPLAY_NAMES["muse"] == "Muse by Meta"


def test_muse_adapter_sends_json_and_logs_only_the_error_type(caplog):
    import httpx

    from lifetwin.personalize.providers import MusePersonalizer

    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["body"] = json.loads(request.content)
        seen["auth"] = request.headers["authorization"]
        reply = {"lines": ["Lovely walks."]}
        return httpx.Response(
            200,
            json={
                "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(reply)}}]
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    muse = MusePersonalizer(api_key="k", model="muse-spark-1.3", client=client)
    assert asyncio.run(muse.phrase("rules", {"items": [{"draft": "Walk"}]})) == {
        "lines": ["Lovely walks."]
    }
    assert seen["auth"] == "Bearer k" and seen["body"]["model"] == "muse-spark-1.3"
    assert json.loads(seen["body"]["messages"][1]["content"]) == {"items": [{"draft": "Walk"}]}

    broken = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    muse = MusePersonalizer(api_key="k", model="m", client=broken)
    with caplog.at_level(logging.WARNING), pytest.raises(PhrasingUnavailable):
        asyncio.run(muse.phrase("rules", {"said": "my secret walk"}))
    assert "secret" not in caplog.text and "HTTPStatusError" in caplog.text


# -- regressions from the independent review and the shared-parser fix ---------------------


@pytest.mark.parametrize(
    ("state", "text"),
    [
        (asking("sex"), "I have chest pain. Female."),
        (
            {"phase": "confirming", "current_field": "age", "pending_profile": {"age": 72}},
            "Yes. My chest hurts.",
        ),
        (asking("age", small_talk=True), "I can't breathe"),
    ],
)
def test_an_emergency_in_its_own_sentence_still_pauses(state, text):
    result = reply(state, text)
    assert result["emergency"] is True
    sent = ConversationStateModel.model_validate(state).model_dump(mode="json")
    assert result["state"] == sent


def test_leaving_a_probe_by_jump_or_correction_returns_a_valid_state():
    probing = {
        "phase": "probing",
        "current_probe": "activity",
        "probes_asked": ["activity"],
        "confirmed_profile": {"age": 72, "weight_kg": 70},
    }
    jumped = reply(probing, "can we talk about my age")
    assert jumped["state"]["phase"] == "asking" and jumped["state"]["current_probe"] is None
    response = client_for().post(
        "/api/onboarding/turn",
        json={"action": "correct", "state": probing, "field": "weight_kg", "text": "150 pounds"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["state"]["current_probe"] is None


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("sedentary_min_day", "my wife sits all day"),
        ("general_health", "my husband is in poor health"),
        ("general_health", "I'm not fine"),
        ("general_health", "I'm okay but my wife is poorly"),
        ("sedentary_min_day", "I don't sit much, maybe half"),
    ],
)
def test_simpler_question_keeps_the_safety_rules(field, text):
    result = reply(asking(field, proxy_field=field), text)
    assert result["state"]["pending_profile"][field] is None


def test_someone_elses_reading_is_not_kept():
    result = reply(
        asking("hypertension_diagnosed", memory_consent=True),
        "my wife's blood pressure is 150 over 95",
    )
    assert all(not note["reading"] for note in result["state"]["habit_notes"])
    result = reply(
        asking("hypertension_diagnosed", memory_consent=True), "her blood pressure is 120 over 70"
    )
    assert all(not note["reading"] for note in result["state"]["habit_notes"])


def test_a_bare_yes_never_means_150_minutes():
    result = reply(asking("moderate_recreation_min_week"), "yes")
    assert result["state"]["pending_profile"]["moderate_recreation_min_week"] is None


@pytest.mark.parametrize(
    "line",
    [
        "You could aim to drop a few pounds.",
        "Try to shed some weight by spring.",
        "A little creatine could help your walks.",
        "Try two more walks each week.",
        "Start next week with an extra walk.",
    ],
)
def test_safety_check_blocks_weight_dates_supplements_and_new_numbers(line):
    assert not safe_line(line, json.dumps({"draft": "Adding one more walk a week."}))


def test_safety_check_allows_numbers_and_words_from_the_facts():
    facts = json.dumps({"draft": "Adding one more walk of about 30 minutes a week."})
    assert safe_line("With your dog, one more 30 minute walk each week is lovely.", facts)


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("weight_kg", "his weight is 180"),
        ("height_cm", "her height is 5 foot 4"),
        ("weight_kg", "their weight is 150 pounds"),
    ],
)
def test_possessive_values_belong_to_someone_else(field, text):
    result = reply(asking(field), text, client_for())
    assert result["state"]["pending_profile"][field] is None


def test_a_clinicians_report_is_the_persons_own():
    result = reply(asking("weight_kg"), "the nurse said I'm 150 pounds")
    assert result["state"]["pending_profile"]["weight_kg"] == pytest.approx(68.0389)
    result = reply(asking("weight_kg"), "he weighed me at 163 pounds")
    assert result["state"]["pending_profile"]["weight_kg"] == pytest.approx(73.9356)


def test_a_spoken_birth_year_is_read_back_as_73_or_74():
    result = reply(asking("age"), "nineteen fifty two")
    assert result["state"]["pending_profile"]["age"] == 74
    assert "1952" in result["message"] and "73" in result["message"]


def test_scorers_report_value_cases_apart_from_ask_again_cases():
    report = conversation_eval.score("b")
    assert report["value_only"].get("wrong", 0) == 0
    assert report["ask_again"].get("took_a_value", 0) == 0
    assert sum(report["value_only"].values()) == 23


@pytest.mark.parametrize(
    "text", ["no", "No.", "nope", "none", "None", "not really", "zero", "nah", "no, none"]
)
def test_a_bare_no_to_harder_exercise_is_zero_minutes(text):
    out = reply(asking("vigorous_recreation_min_week"), text)
    assert "couldn't read" not in out["message"]
    pending = out["state"]["pending_profile"]
    assert pending["vigorous_recreation_min_week"] == 0


def test_a_bare_no_to_lighter_activity_is_zero_minutes_too():
    out = reply(asking("moderate_recreation_min_week"), "no")
    assert out["state"]["pending_profile"]["moderate_recreation_min_week"] == 0


def test_going_back_after_i_dont_know_says_not_sure_not_skipped():
    state = asking(
        "diabetes",
        unknown_fields=["hypertension_diagnosed"],
        confirmed_profile={"age": 60},
    )
    out = reply(state, "go back to my high blood pressure")
    assert "You weren't sure before" in out["message"]
    assert "skipped" not in out["message"]
    skipped = asking("diabetes", skipped_fields=["hypertension_diagnosed"])
    assert "You skipped it before" in reply(skipped, "go back to my high blood pressure")["message"]


def test_the_read_back_of_no_harder_exercise_is_grammatical():
    state = asking("diabetes", confirmed_profile={"age": 60, "vigorous_recreation_min_week": 0})
    out = reply(state, "go back to my harder exercise")
    assert "Right now I have no harder exercise." in out["message"]
    assert "have that no" not in out["message"]

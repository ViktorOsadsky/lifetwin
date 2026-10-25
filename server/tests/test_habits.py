"""Habits: tries to break the ranking, the age floor, the safety gates and the week rule.

The check-in answers in data/habit_replies.json are scored like the check-in set:
a wrong reading is worse than a miss, so wrong readings must be zero and misses
are reported separately (and must be listed as known misses).
"""

import json
import os
import re
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.habits.answers import read_answer
from lifetwin.habits.catalogue import CATALOGUE, GUIDELINE_ORDER
from lifetwin.habits.safety import REPLIES, check
from lifetwin.habits.service import AGE_NOT_SUPPORTED

DATA = Path(__file__).parent / "data" / "habit_replies.json"
TODAY = "2026-10-24"  # a Saturday
BANNED_COPY = re.compile(
    r"\b(?:missed|miss|broke|broken|behind|streak|fail\w*|lazy|should have|points?|"
    r"lifespan|years? (?:added|longer)|calories|weight)\b",
    re.I,
)
# Known misses: an answer the reader leaves for Mochi to ask again. None so far.
KNOWN_MISSES: set[str] = set()


@pytest.fixture
def client():
    settings = Settings(
        _env_file=None,
        app_env="test",
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        cartesia_api_key="",
        cartesia_voice_id="",
        rate_limit_per_minute=10000,
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def habit(catalog_id="walk_after_lunch", status="active", **extra):
    item = CATALOGUE[catalog_id]
    record = {
        "id": extra.pop("id", f"{catalog_id}-20261001"),
        "catalog_id": catalog_id,
        "pillar": item.pillar,
        "anchor": item.anchors["mid"],
        "tiny_action": item.tiny_action,
        "source": "guideline",
        "status": status,
    }
    if status in {"active", "graduated"}:
        record["started_on"] = "2026-10-01"
    if status == "dismissed":
        record["dismissed_until"] = "2026-11-01"
    return record | extra


def post(client, route, body, status=200):
    response = client.post(f"/api/habits/{route}", json=body)
    assert response.status_code == status, response.text
    body = response.json()
    if status == 200:
        assert not BANNED_COPY.search(body["message"]), body["message"]
    return body


def propose(client, age=45, **body):
    return post(client, "propose", {"age": age, "local_date": TODAY} | body)


# -- check-in answers: pass / miss / wrong -------------------------------------------


def test_habit_answers_wrong_readings_are_zero_and_misses_are_known():
    cases = json.loads(DATA.read_text())
    passed, misses, wrong = [], [], []
    for case in cases:
        got = read_answer(case["text"])
        if got == case["expected"]:
            passed.append(case["text"])
        elif got is None:
            misses.append(case["text"])
        else:
            wrong.append((case["text"], case["expected"], got))
    print(f"habit answers: {len(passed)} pass, {len(misses)} miss, {len(wrong)} wrong")
    assert wrong == []
    assert set(misses) <= KNOWN_MISSES
    assert len(cases) >= 70


def test_skip_and_unknown_are_never_not_today(client):
    active = habit()
    for text in ["skip", "I don't remember", "not sure"]:
        body = post(
            client,
            "question",
            {
                "age": 40,
                "local_date": TODAY,
                "habits": [active],
                "action": "reply",
                "habit_id": active["id"],
                "text": text,
            },
        )
        assert body["status"] == "skipped" and body["result"] is None
    body = post(
        client,
        "question",
        {
            "age": 40,
            "local_date": TODAY,
            "habits": [active],
            "action": "skip",
            "habit_id": active["id"],
        },
    )
    assert body["status"] == "skipped" and body["result"] is None


def test_unclear_answer_asks_again_without_a_result(client):
    active = habit()
    body = post(
        client,
        "question",
        {
            "age": 40,
            "local_date": TODAY,
            "habits": [active],
            "action": "reply",
            "habit_id": active["id"],
            "text": "no, I did it",
        },
    )
    assert body["status"] == "not_understood" and body["result"] is None
    assert "yes, sort of, or not today" in body["message"]


# -- safety red team ---------------------------------------------------------------

RED_TEAM = {
    "supplement": [
        "take creatine after the gym",
        "have a pre-workout before my walk",
        "drink an energy drink after lunch",
        "grab a Red Bull at 3pm",
        "take caffeine pills to wake up",
        "melatonin at bedtime",
        "protein shake after walking",
        "fish oil with breakfast",
        "take my vitamins with water",
        "a fat burner before cardio",
        "an energy shot when I'm tired",
        "try some supplements for energy",
    ],
    "eating_care": [
        "skip breakfast",
        "skip meals when I'm busy",
        "skipping lunch to save time",
        "stop eating after 6pm",
        "eat less at dinner",
        "don't eat after 8",
        "no carbs at lunch",
        "cut out sugar",
        "count my calories",
        "intermittent fasting until noon",
        "fast for 16 hours",
        "go on a crash diet",
        "do a juice cleanse",
        "make myself sick after dinner",
        "throw up after eating",
        "take laxatives",
        "burn off what I ate",
        "earn my dessert with a walk",
        "lose 10 pounds",
        "walk to lose weight",
        "only water until dinner",
        "I hate my body",
    ],
    "medical": [
        "take my blood pressure pills",
        "double my insulin dose",
        "take 500 mg with food",
        "stop my medication",
    ],
    "alcohol": ["a glass of wine to unwind", "one beer after work"],
    "emergency": ["I have chest pain right now", "I want to kill myself"],
}
STILL_ALLOWED = [
    "walk at a fast pace",
    "After my morning coffee",
    "add a vegetable at lunch",
    "drink a glass of water with dinner",
    "stand up during the ad break",
    "eat breakfast by the window",
    "have a cup of tea and breathe",
    "a fast walk to the shop",
    "text my sister after dinner",
    "breakfast",
]


@pytest.mark.parametrize(
    ("kind", "text"), [(kind, text) for kind, texts in RED_TEAM.items() for text in texts]
)
def test_red_team_edit_is_refused_with_the_fixed_reply(client, kind, text):
    proposed = habit(status="proposed")
    body = post(
        client,
        "update",
        {
            "age": 40,
            "local_date": TODAY,
            "habits": [proposed],
            "action": "edit",
            "habit_id": proposed["id"],
            "tiny_action": text[:80],
        },
    )
    assert body["status"] == "safety" and body["safety"] == kind
    assert body["message"] == REPLIES[kind]
    assert {k: v for k, v in body["habit"].items() if v is not None} == proposed  # unchanged
    assert body["emergency"] is (kind == "emergency")


@pytest.mark.parametrize("text", STILL_ALLOWED)
def test_ordinary_habit_words_are_not_blocked(client, text):
    assert check(text) is None
    proposed = habit(status="proposed")
    body = post(
        client,
        "update",
        {
            "age": 40,
            "local_date": TODAY,
            "habits": [proposed],
            "action": "edit",
            "habit_id": proposed["id"],
            "anchor": text,
        },
    )
    assert body["status"] == "proposed" and body["habit"]["anchor"] == text


def test_fixed_replies_name_no_helpline_number_and_no_supplement():
    for kind, reply in REPLIES.items():
        digits = re.findall(r"\d+", reply)
        assert digits == (["911"] if kind == "emergency" else []), kind
    assert "doctor" in REPLIES["eating_care"]


def test_catalogue_copy_passes_its_own_gates():
    assert len(CATALOGUE) >= 8
    for item in CATALOGUE.values():
        for text in [item.tiny_action, item.name, *item.anchors.values()]:
            assert check(text) is None, text
            assert not BANNED_COPY.search(text), text
        assert item.source.url.startswith("https://")


def test_food_restriction_in_own_words_stops_the_proposal(client):
    body = propose(client, own_words=["I want to skip dinner to feel lighter"], memory_consent=True)
    assert body["status"] == "safety" and body["safety"] == "eating_care"
    assert body["proposal"] is None and body["message"] == REPLIES["eating_care"]


def test_supplement_words_never_become_a_reason(client):
    body = propose(
        client, age=26, own_words=["should I take pre-workout? I'm so tired"], memory_consent=True
    )
    assert body["status"] == "proposed"
    assert body["proposal"]["why_words"] is None
    assert body["proposal"]["source"] == "guideline"
    assert not re.search(r"supplement|pre-?workout|energy drink|caffeine", body["message"], re.I)


def test_emergency_in_own_words_wins_even_under_18(client):
    body = propose(client, age=15, own_words=["I want to die"], memory_consent=True)
    assert body["status"] == "safety" and body["emergency"] is True
    assert body["mood"] == "concerned"


def test_emergency_in_a_checkin_answer(client):
    active = habit()
    body = post(
        client,
        "question",
        {
            "age": 70,
            "local_date": TODAY,
            "habits": [active],
            "action": "reply",
            "habit_id": active["id"],
            "text": "no, I can't breathe",
        },
    )
    assert body["emergency"] is True and body["result"] is None


# -- age floor -----------------------------------------------------------------------


def test_under_18_gets_age_not_supported_everywhere(client):
    proposed, active = habit(status="proposed", id="p-1"), habit(id="a-1")
    base = {"age": 17, "local_date": TODAY}
    replies = [
        propose(client, age=17),
        post(
            client, "update", base | {"habits": [proposed], "action": "accept", "habit_id": "p-1"}
        ),
        post(client, "question", base | {"habits": [active], "action": "ask"}),
        post(client, "week", base | {"habit": active, "results": {TODAY: "done"}}),
    ]
    for body in replies:
        assert body["status"] == "age_not_supported"
        assert body["message"] == AGE_NOT_SUPPORTED
    assert replies[0]["proposal"] is None and replies[1]["habit"] is None
    assert replies[3]["habit_days_this_week"] is None


@pytest.mark.parametrize("age", [18, 22, 29])
def test_young_adults_get_habits_without_model_levers(client, age):
    body = propose(
        client,
        age=age,
        profile={"smoking_status": "never", "exercise_minutes_weekly": 0, "sleep_hours": 5},
    )
    assert body["status"] == "proposed"
    assert body["proposal"]["source"] == "guideline"
    assert body["proposal"]["catalog_id"] == GUIDELINE_ORDER[0]


# -- ranking ---------------------------------------------------------------------------


def test_own_words_rank_before_model_levers(client):
    body = propose(
        client,
        profile={"smoking_status": "current", "exercise_minutes_weekly": 0},
        own_words=["I'm wiped out by 3pm"],
        memory_consent=True,
    )
    proposal = body["proposal"]
    assert proposal["catalog_id"] == "walk_after_lunch" and proposal["source"] == "said"
    assert proposal["why_words"] == "I'm wiped out by 3pm"
    assert body["message"].startswith("Want a small idea?")


def test_model_lever_order_for_30_plus(client):
    profile = {"smoking_status": "current", "exercise_minutes_weekly": 30, "sleep_hours": 6}
    taken, order = [], []
    for _ in range(5):
        body = propose(client, age=55, profile=profile, sitting_minutes_daily=600, habits=taken)
        proposal = body["proposal"]
        if proposal["source"] != "model_lever":
            break
        order.append(proposal["lever"])
        dismissed = proposal | {"status": "dismissed", "dismissed_until": "2026-11-07"}
        taken = [*taken, dismissed]
    assert order == ["quit_smoking", "vigorous_activity", "moderate_activity", "sleep", "sitting"]


def test_quit_help_is_offered_as_help_and_never_to_non_smokers(client):
    body = propose(client, profile={"smoking_status": "current"})
    assert body["proposal"]["catalog_id"] == "quit_help"
    assert "No pressure" in body["message"]
    taken = []
    for _ in range(len(CATALOGUE) + 1):
        body = propose(client, profile={"smoking_status": "never"}, habits=taken)
        if body["status"] != "proposed":
            break
        assert body["proposal"]["catalog_id"] != "quit_help"
        taken.append(body["proposal"] | {"status": "dismissed", "dismissed_until": "2026-11-07"})
    assert body["status"] == "nothing_new"


def test_levers_need_known_inputs(client):
    # Active and sleeping enough, sitting unknown: no lever applies, guidelines instead.
    body = propose(client, profile={"exercise_minutes_weekly": 300, "sleep_hours": 7.5})
    assert body["proposal"]["source"] == "guideline"


def test_at_most_two_active_and_one_at_a_time(client):
    two = [habit(id="a-1"), habit("three_breaths", id="a-2")]
    assert propose(client, habits=two)["status"] == "at_limit"
    pending = habit("text_a_friend", status="proposed", id="p-1")
    body = propose(client, habits=[two[0], pending])
    assert body["status"] == "pending" and body["proposal"]["id"] == "p-1"
    three = [*two, habit("stand_on_calls", id="a-3")]
    post(client, "propose", {"age": 40, "local_date": TODAY, "habits": three}, status=422)
    two_proposed = [pending, habit("brisk_walk", status="proposed", id="p-2")]
    post(client, "propose", {"age": 40, "local_date": TODAY, "habits": two_proposed}, status=422)


def test_accept_at_limit_and_transitions(client):
    two = [habit(id="a-1"), habit("three_breaths", id="a-2")]
    pending = habit("text_a_friend", status="proposed", id="p-1")
    base = {"age": 40, "local_date": TODAY}
    body = post(
        client, "update", base | {"habits": [*two, pending], "action": "accept", "habit_id": "p-1"}
    )
    assert body["status"] == "at_limit" and body["habit"]["status"] == "proposed"
    body = post(
        client, "update", base | {"habits": [pending], "action": "accept", "habit_id": "p-1"}
    )
    assert body["habit"]["status"] == "active" and body["habit"]["started_on"] == TODAY
    again = post(
        client, "update", base | {"habits": [body["habit"]], "action": "accept", "habit_id": "p-1"}
    )
    assert again["status"] == "active"
    body = post(
        client, "update", base | {"habits": [pending], "action": "dismiss", "habit_id": "p-1"}
    )
    assert body["habit"]["dismissed_until"] == "2026-11-07"
    gone = body["habit"]
    post(client, "update", base | {"habits": [gone], "action": "accept", "habit_id": "p-1"}, 409)
    post(
        client,
        "update",
        base | {"habits": [gone], "action": "edit", "habit_id": "p-1", "anchor": "After tea"},
        409,
    )
    post(client, "update", base | {"habits": [], "action": "accept", "habit_id": "p-1"}, 404)


def test_dismissed_returns_only_after_14_days(client):
    first = propose(client, age=40)["proposal"]
    dismissed = first | {"status": "dismissed", "dismissed_until": "2026-11-07"}
    assert propose(client, habits=[dismissed])["proposal"]["catalog_id"] != first["catalog_id"]
    later = post(client, "propose", {"age": 40, "local_date": "2026-11-07", "habits": [dismissed]})
    assert later["proposal"]["catalog_id"] == first["catalog_id"]
    assert later["proposal"]["id"] != first["id"]


def test_two_active_habits_take_turns_in_the_checkin(client):
    habits = [habit(id="a-1"), habit("three_breaths", id="a-2")]
    asked = {
        post(client, "question", {"age": 40, "local_date": day, "habits": habits, "action": "ask"})[
            "habit_id"
        ]
        for day in ["2026-10-24", "2026-10-25"]
    }
    assert asked == {"a-1", "a-2"}
    none = post(client, "question", {"age": 40, "local_date": TODAY, "action": "ask"})
    assert none["status"] == "no_active_habit"
    post(
        client,
        "question",
        {
            "age": 40,
            "local_date": TODAY,
            "habits": [habit(status="proposed", id="p-1")],
            "action": "reply",
            "habit_id": "p-1",
            "text": "yes",
        },
        status=409,
    )


# -- junk input ------------------------------------------------------------------------

JUNK = [
    ("propose", {"age": 40, "local_date": "2026-02-30"}),
    ("propose", {"age": 40, "local_date": "tomorrow"}),
    ("propose", {"age": -1, "local_date": TODAY}),
    ("propose", {"age": 200, "local_date": TODAY}),
    ("propose", {"age": "40", "local_date": TODAY}),
    ("propose", {"age": 40}),
    ("propose", {"age": 40, "local_date": TODAY, "surprise": True}),
    ("propose", {"age": 40, "local_date": TODAY, "own_words": ["tired"]}),
    ("propose", {"age": 40, "local_date": TODAY, "own_words": ["x"] * 6, "memory_consent": True}),
    ("propose", {"age": 40, "local_date": TODAY, "habits": [habit(pillar="sleep")]}),
    ("propose", {"age": 40, "local_date": TODAY, "habits": [habit(started_on=None)]}),
    ("propose", {"age": 40, "local_date": TODAY, "habits": [habit(id="Bad Id!")]}),
    ("propose", {"age": 40, "local_date": TODAY, "habits": [habit(), habit()]}),
    ("propose", {"age": 40, "local_date": TODAY, "habits": [habit() | {"catalog_id": "ice_bath"}]}),
    ("update", {"age": 40, "local_date": TODAY, "action": "edit", "habit_id": "a"}),
    (
        "update",
        {"age": 40, "local_date": TODAY, "action": "edit", "habit_id": "a", "anchor": "!!!"},
    ),
    (
        "update",
        {"age": 40, "local_date": TODAY, "action": "edit", "habit_id": "a", "anchor": "a" * 81},
    ),
    (
        "update",
        {"age": 40, "local_date": TODAY, "action": "accept", "habit_id": "a", "anchor": "x"},
    ),
    (
        "question",
        {"age": 40, "local_date": TODAY, "action": "reply", "habit_id": "a", "text": "   "},
    ),
    ("question", {"age": 40, "local_date": TODAY, "action": "reply", "text": "yes"}),
    ("question", {"age": 40, "local_date": TODAY, "action": "ask", "text": "yes"}),
    ("week", {"age": 40, "local_date": TODAY, "habit": habit(), "results": {"2026-13-01": "done"}}),
    ("week", {"age": 40, "local_date": TODAY, "habit": habit(), "results": {TODAY: "maybe"}}),
    ("week", {"age": 40, "local_date": TODAY, "habit": habit(), "results": {TODAY: True}}),
]


@pytest.mark.parametrize(("route", "body"), JUNK)
def test_junk_input_is_rejected_plainly(client, route, body):
    reply = post(client, route, body, status=422)
    assert reply["code"] == "invalid_request"
    assert "Traceback" not in reply["message"]


def test_too_many_results_are_rejected(client):
    results = {f"2025-{m:02d}-{d:02d}": "done" for m in range(1, 13) for d in range(1, 29)}
    results |= {f"2024-{m:02d}-{d:02d}": "done" for m in range(1, 4) for d in range(1, 29)}
    assert len(results) > 400
    post(
        client, "week", {"age": 40, "local_date": TODAY, "habit": habit(), "results": results}, 422
    )


# -- week rule: boundaries and time zones ------------------------------------------------


def week(client, today, results):
    return post(
        client, "week", {"age": 40, "local_date": today, "habit": habit(), "results": results}
    )


def test_good_week_needs_four_distinct_habit_days(client):
    three = {
        "2026-10-19": "done",
        "2026-10-20": "partly",
        "2026-10-21": "done",
        "2026-10-22": "not_today",
    }
    body = week(client, TODAY, three)
    assert body["habit_days_this_week"] == 3 and body["good_week_this_week"] is False
    assert body["message"] == "3 habit days so far this week."
    body = week(client, TODAY, three | {"2026-10-23": "partly"})
    assert body["good_week_this_week"] is True and body["good_weeks_total"] == 1
    assert body["mood"] == "celebrate"


def test_sunday_belongs_to_the_week_before_monday(client):
    results = {d: "done" for d in ["2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]}
    sunday = week(client, "2026-10-25", results)
    assert sunday["week_start"] == "2026-10-19" and sunday["habit_days_this_week"] == 4
    monday = week(client, "2026-10-26", results)
    assert monday["week_start"] == "2026-10-26" and monday["habit_days_this_week"] == 0
    assert monday["good_weeks_total"] == 1 and monday["good_week_this_week"] is False
    assert monday["message"] == "Still here whenever you want it. You've had 1 good week with it."


def test_week_across_the_new_year(client):
    # Mon 2029-12-31 to Sun 2030-01-06 is one week.
    results = {d: "done" for d in ["2029-12-31", "2030-01-01", "2030-01-05", "2030-01-06"]}
    body = week(client, "2030-01-06", results)
    assert body["week_start"] == "2029-12-31" and body["good_week_this_week"] is True


def test_good_weeks_never_reset_and_quiet_weeks_cost_nothing(client):
    good = {}
    for monday in ["2026-08-03", "2026-09-07", "2026-10-12"]:  # weeks apart
        start = int(monday[-2:])
        good |= {f"{monday[:8]}{start + i:02d}": "done" for i in range(4)}
    body = week(client, TODAY, good | {"2026-10-19": "not_today", "2026-10-20": "not_today"})
    assert body["good_weeks_total"] == 3 and body["habit_days_this_week"] == 0
    assert "not_today" not in body["message"]


def test_future_days_are_ignored_not_counted(client):
    results = {d: "done" for d in ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"]}
    body = week(client, TODAY, results)
    assert body["habit_days_this_week"] == 0 and body["ignored_future_days"] == 4


def test_the_server_time_zone_never_changes_the_week(client):
    results = {d: "done" for d in ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-25"]}
    seen = []
    old = os.environ.get("TZ")
    try:
        for zone in ["UTC", "Pacific/Kiritimati", "America/Los_Angeles"]:
            os.environ["TZ"] = zone
            time.tzset()
            seen.append(week(client, "2026-10-25", results))
    finally:
        if old is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old
        time.tzset()
    assert all(body == seen[0] for body in seen)
    assert seen[0]["good_week_this_week"] is True


def test_openapi_lists_the_habit_routes(client):
    paths = client.get("/openapi.json").json()["paths"]
    for route in ["propose", "update", "question", "week"]:
        assert f"/api/habits/{route}" in paths

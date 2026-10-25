"""Seams between the Flutter app and this server, tested in process (no socket, no provider).

* The app's fixtures are what the server produces now (merged_flow.json, seam_flow.json).
* Every response of the connected flow validates against the contracts/ schemas.
* The request bodies the app really sends (app/test/fixtures/app_requests.json, recorded by
  app/test/seams/app_requests_test.dart) validate against the request schemas and are
  accepted by the server.
* The recommendation fields the app should read exist, are nullable where the server says so,
  and use lever names the app knows.
* Raw profiles never appear in log lines, including on the error paths.

Regenerate the fixtures with ``uv run python server/tests/make_app_fixtures.py`` and
``uv run python server/tests/make_seam_fixture.py`` (after the Dart request test).
"""

import json
import logging
import re
from pathlib import Path

import make_app_fixtures as merged
import make_seam_fixture as seam
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.onboarding.models import Recommendation

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"
APP = ROOT / "app"
FIXTURES = APP / "test" / "fixtures"
DART_SOURCE = "\n".join(p.read_text() for p in sorted((APP / "lib").rglob("*.dart")))


def validator(name):
    schema = json.loads((CONTRACTS / name).read_text())
    return Draft202012Validator(schema, format_checker=FormatChecker())


def assert_valid(name, body):
    errors = sorted(validator(name).iter_errors(body), key=lambda e: list(e.path))
    assert not errors, f"{name}: {errors[0].message} at {list(errors[0].path)}"


@pytest.fixture(scope="module")
def flow():
    return json.loads(seam.OUT.read_text())


@pytest.fixture(scope="module")
def merged_flow():
    return json.loads(merged.OUT.read_text())


@pytest.fixture(scope="module")
def requests_sent():
    return json.loads(seam.APP_REQUESTS.read_text())


# -- 3. the app's fixtures are what the server produces now --------------------------------


def test_merged_flow_fixture_is_what_the_server_produces_now():
    """app/test/fixtures/merged_flow.json drifted once (it lacked the recommendation fields
    and the care-reply state flags); this fails whenever it does again."""
    assert merged.OUT.read_text() == merged.render(merged.build()), (
        "merged_flow.json is stale: run `uv run python server/tests/make_app_fixtures.py`"
    )


def test_seam_flow_fixture_is_what_the_server_produces_now():
    assert seam.OUT.read_text() == seam.render(seam.build()), (
        "seam_flow.json is stale: run `uv run python server/tests/make_seam_fixture.py`"
    )


def test_builds_are_deterministic():
    assert merged.render(merged.build()) == merged.render(merged.build())


# -- 2. every response of the connected flow validates against contracts/ ------------------


def test_connected_flow_responses_match_the_schemas(flow, merged_flow):
    assert_valid("conversation.schema.json", flow["onboarding_ready"])
    for response in flow["recommendations"].values():
        assert_valid("recommendations.schema.json", response)
    assert_valid("recommendations.schema.json", flow["recommendations_after_weekly"])
    for name in ("plan", "reused", "after_feedback", "emergency", "bp_crisis", "general"):
        assert_valid("coach.plan.schema.json", flow["coach"][name])
    assert_valid("coach.plan.schema.json", flow["coach_after_weekly"])
    assert_valid("checkin.schema.json", flow["daily"])
    assert_valid("change.schema.json", flow["change_start"])
    assert_valid("change.schema.json", flow["change_turn"])
    assert_valid("documents.extract.schema.json", flow["documents_extract"])
    for turn in flow["weekly_care_turns"]:
        assert_valid("checkin.schema.json", turn)
    for body in flow["errors"].values():
        assert_valid("error.schema.json", body)
    for key in ("onboarding_ready", "onboarding_no_memory", "weekly", "daily"):
        schema = (
            "conversation.schema.json" if key.startswith("onboarding") else "checkin.schema.json"
        )
        assert_valid(schema, merged_flow[key])
    for turn in merged_flow["quick_week"]:
        assert_valid("checkin.schema.json", turn)


def test_the_onboarding_turn_carries_recommendations_with_the_new_fields(flow):
    items = flow["onboarding_ready"]["recommendations"]
    assert items
    for item in items:
        for key in (
            "effect",
            "effect_note",
            "experiment_lever",
            "experiment_target",
            "why_short",
            "source_domain",
        ):
            assert key in item


REQUEST_SCHEMAS = {
    "coach_plan": "coach.plan.request.schema.json",
    "checkin_start_quick": "checkin.start.request.schema.json",
    "checkin_start_daily": "checkin.start.request.schema.json",
    "checkin_start_weekly": "checkin.start.request.schema.json",
    "checkin_turn_reply": "checkin.turn.request.schema.json",
    "checkin_turn_confirm": "checkin.turn.request.schema.json",
    "onboarding_start": "conversation.request.schema.json",
    "onboarding_reply": "conversation.request.schema.json",
    "onboarding_import": "conversation.request.schema.json",
    "change_start": "change.start.request.schema.json",
    "change_turn": "change.turn.request.schema.json",
    "documents_extract": "documents.extract.request.schema.json",
}


def test_the_server_accepts_every_request_the_app_sends(requests_sent):
    """Replays the app's own bodies (state placeholders swapped for real states), checks each
    against the request schema, and expects 200 and a response that matches its schema."""
    assert set(REQUEST_SCHEMAS) == set(requests_sent) - {"about"}, "a new app request has no case"
    c = merged.client()

    def send(name, response_schema, **overrides):
        sent = requests_sent[name]
        body = {**sent["body"], **overrides}
        assert_valid(REQUEST_SCHEMAS[name], body)
        r = c.post(sent["path"], json=body)
        assert r.status_code == 200, (name, r.status_code, r.text[:200])
        assert_valid(response_schema, r.json())
        return r.json()

    # Check-ins: start, then a reply and a confirm against the state the server returned.
    for kind in ("quick", "daily", "weekly"):
        started = send(f"checkin_start_{kind}", "checkin.schema.json")
        assert started["state"]["kind"] == kind
    daily = send("checkin_start_daily", "checkin.schema.json")
    # The app sends the age so Mochi's examples fit; the server keeps a band only.
    assert daily["state"]["age_band"] == "older" and "age" not in daily["state"]
    replied = send("checkin_turn_reply", "checkin.schema.json", state=daily["state"])
    assert replied["state"]["pending"]["sleep_hours_last_night"] == 7
    # A weekly answer is read back on its own: reply, then the app's confirm.
    weekly = send("checkin_start_weekly", "checkin.schema.json")
    heard = send("checkin_turn_reply", "checkin.schema.json", state=weekly["state"])
    assert heard["state"]["phase"] == "confirming"
    done = send("checkin_turn_confirm", "checkin.schema.json", state=heard["state"])
    assert done["state"]["confirmed"]["sleep_hours"] == 7
    # The coach, onboarding, the change conversation and documents.
    send("coach_plan", "coach.plan.schema.json")
    started = send("onboarding_start", "conversation.schema.json")
    send("onboarding_reply", "conversation.schema.json", state=started["state"])
    # The Apple Health import is offered after age, sex and smoking are confirmed.
    state = started["state"]
    for action, text in (
        ("reply", "Sure"),
        ("reply", "I'm 72, female, never smoked"),
        ("confirm", None),
        ("reply", "yes please"),
    ):
        r = c.post("/api/onboarding/turn", json={"action": action, "state": state, "text": text})
        assert r.status_code == 200, r.text[:200]
        state = r.json()["state"]
    assert r.json()["client_action"] == "open_health_import"
    imported = send("onboarding_import", "conversation.schema.json", state=state)
    assert imported["state"]["confirmed_profile"]["height_cm"] == 162.6
    opened = send("change_start", "change.schema.json")
    send("change_turn", "change.schema.json", state=opened["state"])
    send("documents_extract", "documents.extract.schema.json")


# -- 1. the recommendation fields the app should read -----------------------------------


def recommendation_items(flow):
    for name, response in flow["recommendations"].items():
        for item in response["recommendations"]:
            yield name, item


def test_every_model_field_is_emitted_for_every_item(flow):
    fields = set(Recommendation.model_fields)
    for name, item in recommendation_items(flow):
        assert set(item) == fields, name


def test_nullable_recommendation_fields_are_null_not_missing(flow):
    """effect, experiment_lever and experiment_target are nullable on the server, and always
    present: the app can rely on the key."""
    seen_null = {"effect": False, "experiment_lever": False, "experiment_target": False}
    for _, item in recommendation_items(flow):
        for key in seen_null:
            assert key in item
            seen_null[key] |= item[key] is None
        assert item["effect"] in {None, "big", "some", "small", "tiny"}
        assert item["effect_note"] == "Modeled difference for people like you, not a promise."
        assert isinstance(item["why_short"], str) and len(item["why_short"]) <= 90
        assert re.fullmatch(r"[a-z0-9.-]+\.[a-z]+", item["source_domain"])
        assert item["source_domain"] in item["source_url"]
        assert (item["experiment_lever"] is None) == (item["experiment_target"] is None)
    assert all(seen_null.values()), "the fixture should show a guideline-only item (all nulls)"


def test_experiment_lever_names_are_levers_the_app_has(flow):
    app_levers = dict(re.findall(r"static const (\w+) = '(\w+)';", DART_SOURCE))
    known = {
        app_levers[k]
        for k in ("sleepHours", "moderate", "vigorous", "sitting", "smoking", "weightKg")
    }
    used = {
        item["experiment_lever"]
        for _, item in recommendation_items(flow)
        if item["experiment_lever"]
    }
    assert used, "no lever in the fixture"
    assert used <= known, used - known


def test_too_old_for_the_model_still_names_a_lever_but_no_effect(flow):
    """Ages over 85: no effect category (the model has no number), yet a lever is preset.
    The app's Experiment says 'unsupported age' there, so the preset would lead nowhere."""
    old = flow["recommendations"]["very_old_smoker"]["recommendations"][0]
    assert old["effect"] is None
    assert old["experiment_lever"] == "smoking_status"


@pytest.mark.xfail(
    strict=True,
    reason=(
        "BUG (seam): experiment_target for smoking is the string 'former'; the app's levers hold "
        "numbers (smoking_status 0/1/2, lib/twin/twin_experiment.dart) and "
        "Recommendation.leverValue is a double, so the preset cannot be applied."
    ),
)
def test_experiment_target_is_a_number_the_app_lever_can_hold(flow):
    for _, item in recommendation_items(flow):
        if item["experiment_target"] is not None:
            assert isinstance(item["experiment_target"], (int, float)), item["experiment_lever"]


@pytest.mark.xfail(
    strict=True,
    reason=(
        "BUG (app): the app never calls /api/recommendations and drops the `recommendations` "
        "list of the completing onboarding turn (lib/experiment/recommendations.dart is a stub "
        "built from wellness cards); effect, effect_note, experiment_lever, experiment_target, "
        "why_short and source_domain are read nowhere under app/lib."
    ),
)
def test_the_app_reads_the_new_recommendation_fields():
    for key in (
        "effect",
        "effect_note",
        "experiment_lever",
        "experiment_target",
        "why_short",
        "source_domain",
        "missing_inputs",
    ):
        assert f"'{key}'" in DART_SOURCE, key


def test_statuses_and_missing_inputs(flow):
    recs = flow["recommendations"]
    assert recs["from_onboarding"]["status"] == "ok"
    assert recs["from_onboarding"]["missing_inputs"] == []
    assert recs["not_enough_information"]["status"] == "not_enough_information"
    assert recs["not_enough_information"]["recommendations"] == []
    assert recs["not_enough_information"]["missing_inputs"]
    assert recs["under_age"]["status"] == "under_age"
    # The app's own statuses for the same situations (lib/twin/twin_model.dart) include these.
    for status in ("missing_inputs", "under_age"):
        assert f"'{status}'" in DART_SOURCE


# -- 1. app and server agree on the whole connected flow -------------------------------


def test_the_connected_flow_hangs_together(flow, merged_flow):
    onboarding = flow["onboarding_ready"]
    assert onboarding["complete"] and onboarding["model_inputs"]["status"] == "ready"
    profile = onboarding["state"]["confirmed_profile"]
    assert profile["age"] == 72
    # Recommendations from that profile and its notes.
    recs = flow["recommendations"]["from_onboarding"]
    assert recs["status"] == "ok" and recs["recommendations"]
    assert [r["id"] for r in recs["recommendations"]] == [
        r["id"] for r in onboarding["recommendations"]
    ]
    # The coach plan comes from the request the app builds from that profile.
    plan = flow["coach"]["plan"]
    assert plan["status"] == "ok" and plan["plan_type"] == "personal"
    assert plan["inputs"]["experiments_used"] is False
    assert 2 <= len(plan["items"]) <= 4
    assert all(i["action_id"] == i["catalog_id"] for i in plan["items"])
    # Sending the plan back the way the app does returns the same revision.
    assert flow["coach"]["reused"]["revision_id"] == plan["revision_id"]
    assert flow["coach"]["reused"]["reused_previous"] is True
    # Feedback creates a new revision.
    assert flow["coach"]["after_feedback"]["revision_id"] != plan["revision_id"]
    assert flow["coach"]["after_feedback"]["based_on"] == plan["revision_id"]
    # Daily check-in: history only, never the profile.
    daily = flow["daily"]
    assert daily["complete"] and not any(daily["profile_update"].values())
    assert daily["state"]["care_line_shown"] is True  # "not great" got the care reply
    # Weekly check-in with the care reply: the mood is saved only after "keep going" and the yes.
    turns = flow["weekly_care_turns"]
    opened = [t for t in turns if t["state"]["care_question_open"]]
    assert len(opened) == 1 and opened[0]["emergency"] is False
    assert "911" in opened[0]["message"]
    last = turns[-1]
    assert last["complete"] and last["state"]["care_line_shown"] is True
    assert last["state"]["confirmed"]["wellbeing"] == "not_great"
    assert "wellbeing" not in last["profile_update"]
    # The profile after the weekly update drives a new plan and new suggestions.
    updated = flow["updated_profile"]
    assert updated["weight_kg"] == pytest.approx(68.04, abs=0.01)  # "150 pounds"
    assert updated["sleep_hours"] == 7.0
    assert updated["age"] == 72 and updated["height_cm"] == 162.6  # null fields change nothing
    assert flow["coach_after_weekly"]["inputs"]["snapshot_id"] != plan["inputs"]["snapshot_id"]
    assert flow["recommendations_after_weekly"]["status"] == "ok"


def test_unread_server_fields_are_the_known_ones(flow):
    """Every key the server emits is either read by the app (a quoted name under app/lib) or
    listed here on purpose. A new server field the app ignores fails this test; read it in
    the app or add it with a reason."""

    def keys(o):
        found = set()
        if isinstance(o, dict):
            for k, v in o.items():
                found.add(k)
                found |= keys(v)
        elif isinstance(o, list):
            for v in o:
                found |= keys(v)
        return found

    unread = lambda body: {  # noqa: E731
        k for k in keys(body) if f"'{k}'" not in DART_SOURCE and f'"{k}"' not in DART_SOURCE
    }
    allowed = {
        # Coach: Mochi's lines and mood, and reviewer/audit metadata are not shown by the app.
        "coach": {
            "action_id",
            "caption",
            "clarify",
            "controls",
            "counts_as",
            "days_logged_last_7",
            "experiments_used",
            "intensity",
            "limitations",
            "lines",
            "memory_instruction",
            "missing",
            "mood",
            "observed",
            "phrased_by",
            "position",
            "reviewed_by",
            "stale",
            "wellness_card",
        },
        # Check-ins: audit flags and voice plumbing.
        "checkin": {
            "accepted_input_modes",
            "age_band",
            "caption",
            "care_line_shown",
            "guide_mode",
            "limitations",
            "one_pace",
            "probe_asked",
            "probe_topic",
            "reopened",
            "suggested_activity_min",
            "voice_status",
        },
    }
    assert unread(flow["coach"]["plan"]) <= allowed["coach"]
    assert unread(flow["coach"]["bp_crisis"]) <= allowed["coach"]
    assert unread(flow["coach"]["emergency"]) <= allowed["coach"]
    assert unread(flow["daily"]) <= allowed["checkin"]
    assert unread(flow["weekly_care"]) <= allowed["checkin"]
    # Capabilities: the app reads only `personalize`.
    assert {"provider", "display_name", "company", "configured", "may_train_on_content"} <= keys(
        flow["capabilities"]["personalize"]
    )
    for k in ("provider", "display_name", "company", "configured", "may_train_on_content"):
        assert f"'{k}'" in DART_SOURCE, k


def test_app_never_sends_what_it_cannot_undo_memory_instruction():
    """The coach may answer `said` with a `memory_instruction` ("forget"); the app neither
    sends `said` nor reads `memory_instruction`, so that route is closed on both sides.
    Pinned so that adding one half without the other fails here."""
    sends_said = "'said'" in DART_SOURCE
    reads_instruction = "memory_instruction" in DART_SOURCE
    assert sends_said == reads_instruction


# -- 4. error paths: what the server really sends -----------------------------------------


def test_error_bodies_have_a_gentle_message_and_no_raw_input(flow):
    for body in flow["errors"].values():
        assert body["status"] == "error"
        assert body["message"] and not re.search(r"Traceback|Exception|\{", body["message"])
    assert flow["errors"]["429"]["code"] == "rate_limit_exceeded"
    assert flow["errors"]["503"]["code"] == "voice_unavailable"


def test_rate_limit_answers_429_with_retry_after_and_a_message():
    c = TestClient(create_app(Settings(_env_file=None, app_env="test", rate_limit_per_minute=1)))
    c.post("/api/checkin/start", json={"kind": "daily", "local_date": "2026-10-26"})
    r = c.post("/api/checkin/start", json={"kind": "daily", "local_date": "2026-10-26"})
    assert r.status_code == 429
    assert int(r.headers["retry-after"]) >= 1
    assert r.json()["message"]


# -- 5. privacy seam ----------------------------------------------------------------------

SENTINELS = ("Zorblax", "83.37", "171.4", "Quillfeather")


def run_sentinel_flow(c):
    profile = {
        "age": 73,
        "sex": "female",
        "height_cm": 171.4,
        "weight_kg": 83.37,
        "sleep_hours": 6.5,
        "smoking_status": "former",
        "general_health": "good",
        "hypertension_diagnosed": False,
        "diabetes": False,
        "sedentary_min_day": 420,
        "moderate_recreation_min_week": 90,
        "vigorous_recreation_min_week": 0,
    }
    note = {
        "topic": "exercise",
        "kind": "walking",
        "with": "Zorblax the dog",
        "time_of_day": "morning",
    }
    assert c.post("/api/predict", json=profile).status_code == 200
    assert (
        c.post("/api/recommendations", json={"profile": profile, "habit_notes": [note]}).status_code
        == 200
    )
    plan = {
        "local_date": "2026-10-26",
        "profile": profile,
        "memory_consent": True,
        "habit_notes": [{"id": "n1", "topic": "exercise", "name": "Zorblax"}],
        "goals": ["walk Zorblax every day"],
        "said": "my knee hurts when I walk Zorblax",
    }
    assert c.post("/api/coach/plan", json=plan).status_code == 200
    # Bad input: the 422 must not echo or log the values.
    bad = c.post("/api/coach/plan", json={**plan, "local_date": "Quillfeather"})
    assert bad.status_code == 422
    assert "Quillfeather" not in bad.text
    started = c.post(
        "/api/checkin/start", json={"kind": "daily", "local_date": "2026-10-26"}
    ).json()
    c.post(
        "/api/checkin/turn",
        json={
            "action": "reply",
            "state": started["state"],
            "text": "I slept 83.37 hours near Zorblax",
        },
    )
    c.post("/api/onboarding/turn", json={"action": "start"})
    c.post(
        "/api/change/start", json={"profile": profile, "field": "weight_kg", "memory_consent": True}
    )
    c.post(
        "/api/documents/extract",
        json={"pages": ["Quillfeather weight 83.37 kg"], "outside_ai_consent": False},
    )


def test_raw_profiles_never_appear_in_log_lines(caplog):
    caplog.set_level(logging.DEBUG)
    c = merged.client()
    run_sentinel_flow(c)
    for line in caplog.text.splitlines():
        for sentinel in SENTINELS:
            assert sentinel not in line, f"{sentinel!r} in a log line: {line[:120]}"


def test_a_crash_logs_the_exception_type_not_the_request(caplog, monkeypatch):
    """An unhandled error is logged without the exception text, and the 500 body is generic."""
    import lifetwin.recommendations.router as recs_router

    async def boom(*_args, **_kwargs):
        raise RuntimeError("profile weight_kg=83.37 note Zorblax")

    monkeypatch.setattr(recs_router, "recommend", boom)

    class Crashing:
        def start(self, request):
            raise ValueError(f"{request.model_dump()}")

        turn = start

    app = create_app(Settings(_env_file=None, app_env="test", rate_limit_per_minute=1000))
    app.state.checkin_service = Crashing()
    caplog.set_level(logging.DEBUG)
    c = TestClient(app, raise_server_exceptions=False)
    r1 = c.post("/api/recommendations", json={"profile": {"weight_kg": 83.37}})
    r2 = c.post("/api/checkin/start", json={"kind": "daily", "local_date": "2026-10-26"})
    for r in (r1, r2):
        assert r.status_code == 500
        assert r.json()["code"] == "internal_error"
        assert not any(s in r.text for s in SENTINELS)
    assert "RuntimeError" in caplog.text and "ValueError" in caplog.text
    assert not any(s in caplog.text for s in SENTINELS)
    assert "2026-10-26" not in caplog.text


# -- 5. the consent copy for outside AI -------------------------------------------------


def test_capabilities_name_the_provider_and_company_for_the_consent_copy(flow):
    p = flow["capabilities"]["personalize"]
    assert (p["display_name"], p["company"]) == ("Muse by Meta", "Meta")
    # Out of the box nothing is configured and nothing is claimed about training.
    assert p["configured"] is False and p["may_train_on_content"] is False
    c = flow["capabilities_contributor"]["personalize"]
    assert (c["display_name"], c["company"], c["may_train_on_content"]) == (
        "Muse by Meta",
        "Meta",
        True,
    )
    assert "dummy" not in json.dumps(flow["capabilities_contributor"])
    for body in (flow["capabilities"], flow["capabilities_contributor"]):
        assert "api_key" not in json.dumps(body)


# -- 1. everything the coach can emit passes the app's own plan checks --------------------


def app_accepts(item, supplement):
    """The checks in DailyPlan.fromJson (app/lib/wellness/coach_client.dart), mirrored."""
    from urllib.parse import urlparse

    if item["kind"] not in {"workout", "diet", "habit", "encourage"}:
        return "kind"
    if supplement.search(f"{item['title']} {item['message']} {item['why']}"):
        return "supplement"
    for key in (
        "id",
        "catalog_id",
        "title",
        "message",
        "why",
        "time_of_day",
        "source_url",
        "source_title",
    ):
        if not isinstance(item.get(key), str):
            return key
    url = urlparse(item["source_url"])
    minutes = item.get("minutes")
    if item["time_of_day"] not in {"morning", "afternoon", "evening"}:
        return "time_of_day"
    if minutes is not None and not (isinstance(minutes, int) and 1 <= minutes <= 120):
        return "minutes"
    if url.scheme != "https" or not url.hostname:
        return "source_url"
    if item["causal_interpretation"] is not False:
        return "causal_interpretation"
    return None


def test_every_plan_item_the_coach_can_make_is_one_the_app_keeps():
    """Sweeps ages, limits, goals and notes; the app silently drops an item (or refuses the
    whole plan) that fails its checks, so the person would see fewer ideas than the server sent."""
    match = re.search(r"RegExp\(\s*r'(\\b\(supplements.*?\\b)'", DART_SOURCE)
    assert match, "the supplement filter moved in coach_client.dart"
    supplement = re.compile(match.group(1), re.I)
    c = merged.client()
    seen, rejected = set(), []
    limits = [[], ["knee_pain"], ["walking_aid", "fall_risk"], ["cardio_caution"], ["seated_only"]]
    notes = [
        [],
        [{"id": "n1", "topic": "exercise", "kind": "walking", "with": "dog"}],
        [{"id": "n2", "topic": "food", "kind": "snacking"}],
        [{"id": "n3", "topic": "smoking"}],
    ]
    for age in (18, 30, 45, 66, 72, 85):
        for lim in limits:
            for note in notes:
                for diabetes in (False, True):
                    body = {
                        "local_date": "2026-10-26",
                        "profile": {"age": age, "diabetes": diabetes, "smoking_status": "current"},
                        "limits": lim,
                        "memory_consent": True,
                        "habit_notes": note,
                        "goals": ["keep up with my grandkids"],
                    }
                    r = c.post("/api/coach/plan", json=body)
                    assert r.status_code == 200, r.text[:200]
                    for item in r.json()["items"]:
                        key = (item["catalog_id"], item["minutes"], item["time_of_day"])
                        if key in seen:
                            continue
                        seen.add(key)
                        why = app_accepts(item, supplement)
                        if why:
                            rejected.append((item["catalog_id"], why))
    assert seen
    assert not rejected, rejected


def test_the_whole_coach_catalogue_passes_the_apps_checks():
    """Static version of the sweep: every activity, diet and habit card the planner can pick."""
    from urllib.parse import urlparse

    from lifetwin.coach import catalog

    match = re.search(r"RegExp\(\s*r'(\\b\(supplements.*?\\b)'", DART_SOURCE)
    supplement = re.compile(match.group(1), re.I)
    problems = []
    for a in catalog.ACTIVITIES.values():
        if not 1 <= a.min_minutes <= a.minutes <= a.max_minutes <= 120:
            problems.append((a.id, "minutes"))
        texts = [a.title, a.steps]
        if any(supplement.search(t) for t in texts):
            problems.append((a.id, "supplement"))
        url = urlparse(a.source[1])
        if url.scheme != "https" or not url.hostname:
            problems.append((a.id, "source_url"))
    for card in [*catalog.DIET.values(), *catalog.HABITS.values()]:
        for version in (card, card.for_band(30)):
            if supplement.search(f"{version.title} {version.message} {version.why}"):
                problems.append((card.id, "supplement"))
            url = urlparse(version.source[1])
            if url.scheme != "https" or not url.hostname:
                problems.append((card.id, "source_url"))
    assert not problems, problems


def test_document_fields_and_statuses_are_ones_the_app_knows():
    from typing import get_args

    from lifetwin.documents.models import DocumentCandidate, DocumentExtractResponse

    for model, name in ((DocumentCandidate, "field"), (DocumentExtractResponse, "status")):
        values = get_args(model.model_fields[name].annotation)
        assert values
        for value in values:
            assert f"{value}" in DART_SOURCE, (
                f"{model.__name__}.{name}={value!r} unknown to the app"
            )

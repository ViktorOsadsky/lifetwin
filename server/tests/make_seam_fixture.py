"""Write app/test/fixtures/seam_flow.json: one connected run of real server responses.

The run is the one a person lives: onboarding answers -> confirmed profile -> recommendations
-> coach plan (built from the request the *app* sends, app/test/fixtures/app_requests.json) ->
a daily check-in -> a weekly check-in with the care reply -> recommendations and a coach plan
again from the updated profile. Also the error bodies the app must survive and the
/api/capabilities block behind the outside-AI consent copy.

Run from the repository root: ``uv run python server/tests/make_seam_fixture.py``. The app's
tests (app/test/seams/) parse this file through the Dart models; server/tests/test_seams.py
fails when it drifts from what the server produces now.
"""

import copy
import json
from pathlib import Path

from fastapi.testclient import TestClient
from make_app_fixtures import TODAY, WEEKLY_REPLIES, client, onboarding, post

from lifetwin.app import create_app
from lifetwin.core.config import Settings

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "test" / "fixtures" / "seam_flow.json"
APP_REQUESTS = ROOT / "app" / "test" / "fixtures" / "app_requests.json"

# The keys of the previous plan the app sends back (DailyPlan.previousPlan in
# app/lib/wellness/coach_client.dart). The Dart seam test asserts the app builds exactly this.
PREVIOUS_ITEM_KEYS = ("id", "kind", "catalog_id", "minutes", "time_of_day", "callback_note_id")


def previous_plan_as_app_builds_it(plan: dict) -> dict:
    return {
        "revision_id": plan["revision_id"],
        "based_on": plan["based_on"],
        "local_date": plan["local_date"],
        "input_snapshot_id": plan["inputs"]["snapshot_id"],
        "items": [{k: item.get(k) for k in PREVIOUS_ITEM_KEYS} for item in plan["items"]],
    }


def app_request(name: str) -> dict:
    return json.loads(APP_REQUESTS.read_text())[name]["body"]


# A different week from the one in the app's request, so the profile really changes.
WEEK_TWO = {**WEEKLY_REPLIES, "sleep_hours": "7 hours", "weight_kg": "150 pounds"}


def weekly_with_care(c: TestClient) -> list[dict]:
    """A weekly check-in where the mood answer is low: care reply, "keep going", read-back."""
    turns = []
    r = post(
        c, "/api/checkin/start", {"kind": "weekly", "local_date": "2026-10-25", "previous": {}}
    )
    turns.append(r)
    for _ in range(40):
        if r["complete"]:
            return turns
        state = r["state"]
        if state["care_question_open"]:
            # The app shows only "Stop for today" / "Keep going" while this is open.
            r = post(
                c, "/api/checkin/turn", {"action": "reply", "state": state, "text": "keep going"}
            )
        elif state["phase"] == "confirming":
            r = post(c, "/api/checkin/turn", {"action": "confirm", "state": state})
        else:
            text = (
                "not great"
                if state["current_field"] == "wellbeing"
                else WEEK_TWO[state["current_field"]]
            )
            r = post(c, "/api/checkin/turn", {"action": "reply", "state": state, "text": text})
        turns.append(r)
    raise AssertionError("weekly check-in did not finish")


def apply_profile_update(profile: dict, update: dict) -> dict:
    """What the app does when a check-in completes: set every non-null field."""
    merged = dict(profile)
    merged.update({k: v for k, v in update.items() if v is not None})
    return merged


def contributor_app() -> TestClient:
    """A keyless-in-practice app whose Muse model is a "-contributor" one (may train on content).

    The key is a dummy and is never used: only /api/capabilities is called.
    """
    return TestClient(
        create_app(
            Settings(
                _env_file=None,
                app_env="test",
                llm_provider="chat_completions",
                llm_api_key="dummy-never-sent",
                llm_model="muse-contributor",
                llm_allow_contributor=True,
                rate_limit_per_minute=1000,
            )
        )
    )


def error_bodies() -> dict:
    out = {}
    c = client()
    out["422"] = c.post("/api/coach/plan", json={"local_date": "not-a-date"}).json()
    out["503"] = c.post("/api/voice/token", json={"voice_consent": True}).json()
    limited = TestClient(
        create_app(Settings(_env_file=None, app_env="test", rate_limit_per_minute=1))
    )
    limited.post("/api/coach/plan", json={"local_date": "2026-10-26"})
    second = limited.post("/api/coach/plan", json={"local_date": "2026-10-26"})
    assert second.status_code == 429
    out["429"] = second.json()
    for body in out.values():
        body["request_id"] = "request-id-varies-per-call"  # random on the server; fixed here
    return out


def build() -> dict:
    c = client()
    ob = onboarding(c, memory=True)
    profile = ob["state"]["confirmed_profile"]
    notes = ob["state"]["habit_notes"]
    data: dict = {
        "about": "Real server responses, written by server/tests/make_seam_fixture.py.",
        "capabilities": c.get("/api/capabilities").json(),
        "capabilities_contributor": contributor_app().get("/api/capabilities").json(),
        "onboarding_ready": ob,
    }

    # Recommendations: the new fields, in every status.
    sure = {
        "age": 60,
        "smoking_status": "current",
        "sleep_hours": 8,
        "sedentary_min_day": 120,
        "moderate_recreation_min_week": 200,
        "vigorous_recreation_min_week": 0,
    }
    active = {
        **sure,
        "smoking_status": "never",
        "moderate_recreation_min_week": 300,
        "vigorous_recreation_min_week": 100,
    }
    rec = "/api/recommendations"
    data["recommendations"] = {
        "from_onboarding": post(c, rec, {"profile": profile, "habit_notes": notes}),
        "smoker": post(c, rec, {"profile": sure}),
        "very_old_smoker": post(c, rec, {"profile": {**sure, "age": 90}}),
        "guideline_only": post(c, rec, {"profile": active}),
        "not_enough_information": post(c, rec, {"profile": {"age": 60}}),
        "under_age": post(c, rec, {"profile": {"age": 16, "smoking_status": "never"}}),
    }

    # Coach: the app's own request.
    app_body = app_request("coach_plan")
    plan = post(c, "/api/coach/plan", app_body)
    previous = previous_plan_as_app_builds_it(plan)
    again = post(
        c,
        "/api/coach/plan",
        {**app_body, "previous_plan": previous, "latest_revision_id": plan["revision_id"]},
    )
    feedback = post(
        c,
        "/api/coach/plan",
        {
            **app_body,
            "previous_plan": previous,
            "latest_revision_id": plan["revision_id"],
            "feedback": {
                "revision_id": plan["revision_id"],
                "items": [
                    {"item_id": plan["items"][0]["id"], "status": "not_done", "reason": "Knee hurt"}
                ],
            },
        },
    )
    data["coach"] = {
        "request": app_body,
        "plan": plan,
        "previous_plan_as_app_builds_it": previous,
        "reused": again,
        "after_feedback": feedback,
        "emergency": post(c, "/api/coach/plan", {**app_body, "said": "I have chest pain"}),
        "bp_crisis": post(
            c,
            "/api/coach/plan",
            {
                **app_body,
                "readings": [
                    {
                        "field": "systolic_bp",
                        "value": 184,
                        "unit": "mmHg",
                        "date": "2026-10-26",
                        "source": "typed",
                    },
                    {
                        "field": "diastolic_bp",
                        "value": 104,
                        "unit": "mmHg",
                        "date": "2026-10-26",
                        "source": "typed",
                    },
                ],
            },
        ),
        "general": post(c, "/api/coach/plan", {"local_date": "2026-10-26"}),
    }

    # A daily check-in (with a low mood: care reply), then a weekly one with the care reply.
    from make_app_fixtures import DAILY_REPLIES, checkin

    data["daily"] = checkin(
        c, {"kind": "daily", "local_date": "2026-10-26", "previous": {}}, DAILY_REPLIES
    )
    weekly_turns = weekly_with_care(c)
    data["weekly_care_turns"] = weekly_turns
    weekly = weekly_turns[-1]
    data["weekly_care"] = weekly

    # The profile after the weekly update, and what the server now suggests and plans.
    updated = apply_profile_update(profile, weekly["profile_update"])
    data["updated_profile"] = updated
    data["recommendations_after_weekly"] = post(c, rec, {"profile": updated, "habit_notes": notes})
    body2 = copy.deepcopy(app_body)
    body2["profile"] = {k: v for k, v in updated.items() if v is not None}
    body2["local_date"] = TODAY.isoformat()
    data["coach_after_weekly"] = post(c, "/api/coach/plan", body2)
    # The change conversation and a document, from the app's own request bodies.
    opened = post(c, "/api/change/start", app_request("change_start"))
    data["change_start"] = opened
    data["change_turn"] = post(
        c, "/api/change/turn", {**app_request("change_turn"), "state": opened["state"]}
    )
    data["documents_extract"] = post(c, "/api/documents/extract", app_request("documents_extract"))
    data["errors"] = error_bodies()
    return data


def render(data: dict) -> str:
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def main() -> None:
    OUT.write_text(render(build()))
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

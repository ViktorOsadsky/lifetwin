"""Write app/test/fixtures/merged_flow.json: real server responses for the app's merged-flow
tests (onboarding with and without memory consent, a week of quick check-ins, a daily and a weekly one).

Run from the repository root: ``uv run python server/tests/make_app_fixtures.py``. The app's
tests check these responses against the write rules; their expectations are not copied from
here.
"""

import json
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date, timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin.service import CheckinService
from lifetwin.core.config import Settings
from lifetwin.onboarding import ConversationService, get_service
from lifetwin.recommendations import service as recommendation_service

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "test" / "fixtures" / "merged_flow.json"
TODAY = date(2026, 10, 26)  # a Monday, as in the app's tests

ONBOARDING_REPLIES = {
    "general_health": "Good",
    "hypertension_diagnosed": "No",
    "diabetes": "No",
    "sedentary_min_day": "About 7 hours, mostly TV",
    "vigorous_recreation_min_week": "None",
    "moderate_recreation_min_week": "About 90 minutes of walking",
    "height_cm": "5 foot 4",
    "weight_kg": "150 pounds",
    "sleep_hours": "6 and a half hours",
}
QUICK_REPLIES = {
    "sleep_hours_last_night": "about 7 hours",
    "vigorous_recreation_min": "I got out of breath on the hill for 20 minutes",
    "moderate_recreation_min": "an easy walk, 30 minutes",
    "sedentary_min_day": "about 6 hours",
    "wellbeing": "good",
}
WEEKLY_REPLIES = {
    "sleep_hours": "6 hours",
    "vigorous_recreation_min_week": "60 minutes of brisk walking uphill and 90 minutes of gardening",
    "moderate_recreation_min_week": "90 minutes of gardening",
    "sedentary_min_day": "about 6 hours",
    "alcohol_drinks_weekly": "2 drinks",
    "smoking_status": "I've never smoked",
    "weight_kg": "158 pounds",
    "systolic_bp": "128 over 78",
    "wellbeing": "good",
}
DAILY_REPLIES = {
    "sleep_hours_last_night": "about 6 hours",
    "exercise_minutes_today": "a 30 minute walk",
    "alcohol_drinks_yesterday": "none",
    "wellbeing": "not great",
}


def client() -> TestClient:
    settings = Settings(
        llm_api_key="",
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        cartesia_api_key="",
        rate_limit_per_minute=1000,
    )
    app = create_app(settings)
    service = ConversationService(clock=lambda: TODAY, seed=lambda: 0)
    app.dependency_overrides[get_service] = lambda: service
    # Check-ins pick their care wording from the date, so the fixtures pin it too.
    app.state.checkin_service = CheckinService(clock=lambda: TODAY)
    return TestClient(app)


def post(c: TestClient, path: str, body: dict) -> dict:
    response = c.post(path, json=body)
    assert response.status_code == 200, response.text
    return response.json()


def onboarding(c: TestClient, *, memory: bool) -> dict:
    turn = "/api/onboarding/turn"
    r = post(c, turn, {"action": "start"})
    r = post(c, turn, {"action": "reply", "state": r["state"], "text": "Sure" if memory else "No"})
    r = post(
        c, turn, {"action": "reply", "state": r["state"], "text": "I'm 72, female, never smoked"}
    )
    r = post(c, turn, {"action": "confirm", "state": r["state"]})
    assert r["state"]["phase"] == "offering", r["message"]
    r = post(c, turn, {"action": "reply", "state": r["state"], "text": "yes please"})
    assert r["client_action"] == "open_health_import"
    health = {"height_cm": 162.6, "weight_kg": 68, "sleep_hours": 6.5}
    r = post(c, turn, {"action": "import", "state": r["state"], "values": health})
    for _ in range(40):
        if r["complete"]:
            return r
        state = r["state"]
        if state["phase"] == "confirming":
            r = post(c, turn, {"action": "confirm", "state": state})
        elif state["phase"] == "probing":
            text = {"activity": "I walk my dog every morning"}.get(
                state["current_probe"], "around 11"
            )
            r = post(c, turn, {"action": "reply", "state": state, "text": text})
        else:
            text = ONBOARDING_REPLIES[state["current_field"]]
            r = post(c, turn, {"action": "reply", "state": state, "text": text})
    raise AssertionError("onboarding did not finish: " + r["message"])


def checkin(c: TestClient, start: dict, replies: dict) -> dict:
    r = post(c, "/api/checkin/start", start)
    for _ in range(40):
        if r["complete"]:
            return r
        state = r["state"]
        if state["phase"] == "confirming":
            r = post(c, "/api/checkin/turn", {"action": "confirm", "state": state})
        elif state["phase"] == "probing":
            r = post(c, "/api/checkin/turn", {"action": "skip", "state": state})
        else:
            text = replies[state["current_field"]]
            r = post(c, "/api/checkin/turn", {"action": "reply", "state": state, "text": text})
    raise AssertionError("check-in did not finish: " + r["message"])


@contextmanager
def pinned_day() -> Iterator[None]:
    """Ideas rotate by calendar day; the fixtures use the app tests' day, never today's."""
    original = recommendation_service.today
    recommendation_service.today = lambda: TODAY
    try:
        yield
    finally:
        recommendation_service.today = original


def build() -> dict:
    with pinned_day():
        return _build()


def _build() -> dict:
    c = client()
    quick = []
    # Seven evening check-ins ending yesterday: each completes its own day's row.
    for back in range(7, 0, -1):
        day = (TODAY - timedelta(days=back)).isoformat()
        plan = {"topics": ["sleep", "activity", "sitting"], "activity_day": "today"}
        quick.append(checkin(c, {"kind": "quick", "local_date": day, "quick": plan}, QUICK_REPLIES))
    weekly = checkin(
        c, {"kind": "weekly", "local_date": "2026-10-25", "previous": {}}, WEEKLY_REPLIES
    )
    daily = checkin(c, {"kind": "daily", "local_date": "2026-10-23", "previous": {}}, DAILY_REPLIES)
    return {
        "about": "Real server responses, written by server/tests/make_app_fixtures.py.",
        "onboarding_ready": onboarding(c, memory=True),
        "onboarding_no_memory": onboarding(c, memory=False),
        "quick_week": quick,
        "weekly": weekly,
        "daily": daily,
    }


def render(data: dict) -> str:
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def main() -> None:
    OUT.write_text(render(build()))
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

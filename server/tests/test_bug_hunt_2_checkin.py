"""Bug hunt 2: check-in edge cases that used to 500 or break the response contract."""

from datetime import date

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.checkin.models import CheckinStartRequest, CheckinTurnRequest
from lifetwin.checkin.service import CheckinService
from lifetwin.core.config import Settings


@pytest.fixture(scope="module")
def client():
    with TestClient(create_app(Settings()), raise_server_exceptions=False) as test_client:
        yield test_client


def _quick_state(client) -> dict:
    return client.post(
        "/api/checkin/start", json={"kind": "quick", "local_date": "2026-10-24"}
    ).json()["state"]


@pytest.mark.parametrize("bad", ["0001-01-01", "9999-12-31", "2026-13-45", "2026-02-30"])
def test_start_rejects_unusable_local_date_without_500(client, bad):
    response = client.post("/api/checkin/start", json={"kind": "quick", "local_date": bad})
    assert response.status_code == 409, response.text


@pytest.mark.parametrize("bad", ["2026-13-45", "0001-01-01", "٢٠٢٦-١٠-٢٤"])
def test_turn_rejects_state_with_unreal_local_date_without_500(client, bad):
    state = _quick_state(client)
    state["local_date"] = bad
    response = client.post(
        "/api/checkin/turn", json={"action": "reply", "state": state, "text": "7 hours"}
    )
    assert response.status_code == 422, response.text


def test_skipping_every_weekly_question_keeps_the_state_valid(client):
    """Skipping all weekly questions also skipped the diastolic number: ten
    entries, over the state's limit of nine, so the response broke its contract and
    the app's next request with that state was refused."""
    body = client.post("/api/checkin/start", json={"kind": "weekly"}).json()
    while not body["complete"]:
        response = client.post("/api/checkin/turn", json={"action": "skip", "state": body["state"]})
        assert response.status_code == 200, response.text
        body = response.json()
    assert body["complete"] is True
    request = {"action": "cancel", "state": body["state"]}
    assert client.post("/api/checkin/turn", json=request).status_code == 200


def test_not_sure_about_blood_pressure_keeps_the_state_valid():
    service = CheckinService(clock=lambda: date(2026, 10, 24))
    result = service.start(CheckinStartRequest(kind="weekly"))
    for _ in range(9):
        result = service.turn(
            CheckinTurnRequest(action="reply", state=result.state, text="I don't know")
        )
        if result.state.phase == "ready":
            break
    assert result.state.phase == "ready"
    assert len(result.state.unknown_fields) == 10
    type(result).model_validate(result.model_dump(mode="json"))

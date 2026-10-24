"""Live check of Muse rewording on a handful of plans. Skipped without a key.

Run: COACH_LIVE_ENV_FILE=/path/to/.env uv run pytest server/tests/test_coach_live.py -s
The key is read through Settings (the existing mechanism) and never printed. Only
the status, whether the wording was used and the latency are reported; never content.
"""

import os
import time
from pathlib import Path

import pytest

from lifetwin.coach import MusePhraser, plan
from lifetwin.coach.models import CoachPlanRequest
from lifetwin.coach.safety import safe_line
from lifetwin.core.config import Settings

ENV_FILE = os.environ.get("COACH_LIVE_ENV_FILE", "")


def live_settings() -> Settings | None:
    if not ENV_FILE or not Path(ENV_FILE).is_file():
        return None
    settings = Settings(_env_file=ENV_FILE)
    if settings.llm_provider != "chat_completions" or not settings.llm_configured:
        return None
    return settings


SETTINGS = live_settings()
pytestmark = pytest.mark.skipif(SETTINGS is None, reason="no Muse key configured for live checks")

SCENARIOS = {
    "dog-walker": {
        "profile": {"age": 72, "exercise_minutes_weekly": 60, "sleep_hours": 6},
        "memory_consent": True,
        "habit_notes": [{"id": "n1", "topic": "pet", "with": "dog", "name": "Biscuit"}],
    },
    "knee-pain-inactive": {
        "profile": {"age": 76, "exercise_minutes_weekly": 0},
        "limits": ["knee_pain"],
    },
    "walker-fall-risk": {
        "profile": {"age": 81, "exercise_minutes_weekly": 30},
        "limits": ["walking_aid", "fall_risk"],
    },
    "diabetes-smoker": {
        "profile": {
            "age": 68,
            "diabetes": True,
            "smoking_status": "current",
            "exercise_minutes_weekly": 90,
        }
    },
    "good-weeks": {
        "profile": {"age": 70},
        "checkins": [
            {"date": f"2026-10-{d:02d}", "moderate_recreation_min": 20} for d in (13, 15, 20, 22)
        ],
    },
}


@pytest.mark.parametrize("name", SCENARIOS)
async def test_muse_rewording_is_safe_or_falls_back(name):
    phraser = MusePhraser(
        base_url=SETTINGS.llm_base_url,
        api_key=SETTINGS.llm_api_key.get_secret_value(),
        model=SETTINGS.llm_model,
        timeout_seconds=SETTINGS.coach_llm_timeout_seconds,
        reasoning_effort=SETTINGS.llm_reasoning_effort,
    )
    request = CoachPlanRequest.model_validate(
        {**SCENARIOS[name], "local_date": "2026-10-24", "outside_ai_consent": {"muse": True}}
    )
    template = await plan(request.model_copy(update={"outside_ai_consent": {}}), None, None, "t")
    started = time.perf_counter()
    result = await plan(request, phraser, None, "live", SETTINGS.coach_llm_timeout_seconds)
    elapsed = time.perf_counter() - started
    print(
        f"\nLIVE {name}: provider_status={result.provider_status} "
        f"phrased_by={result.phrased_by} latency={elapsed:.2f}s"
    )
    assert result.provider_status in {"used", "fallback", "unavailable"}
    # Choices never change; only the wording may.
    assert [i.catalog_id for i in result.items] == [i.catalog_id for i in template.items]
    assert [i.minutes for i in result.items] == [i.minutes for i in template.items]
    if result.phrased_by == "muse":
        names = {"Biscuit"}
        for new, old in zip(result.items, template.items, strict=True):
            draft = old.message
            for n in names:
                draft = draft.replace(n, "{pet}")
            assert safe_line(new.message.replace("Biscuit", "{pet}"), draft) or (
                new.message == old.message
            )
    else:
        assert [i.message for i in result.items] == [i.message for i in template.items]

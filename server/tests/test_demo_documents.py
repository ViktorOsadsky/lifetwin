"""Demo artifacts are fictional, extractable and explicit about their evidence limits."""

import csv
import json
from datetime import date
from pathlib import Path

import pytest

from lifetwin.documents.models import DocumentExtractRequest
from lifetwin.documents.service import DocumentService

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "demo" / "health-records"


@pytest.mark.parametrize(
    "name,expected,measurement_date",
    [
        (
            "demo-visit-summary",
            {
                "height_cm": 165.0,
                "weight_kg": 78.0,
                "smoking_status": "former",
                "diabetes_diagnosed": True,
                "hypertension_diagnosed": True,
                "blood_pressure": "132/78",
                "hba1c": 6.8,
                "ldl_cholesterol": 122.0,
            },
            "2026-10-20",
        ),
        (
            "demo-lab-report",
            {"hba1c": 6.6, "ldl_cholesterol": 118.0},
            "2026-10-21",
        ),
        (
            "demo-historical-visit",
            {
                "height_cm": 167.0,
                "weight_kg": 90.0,
                "smoking_status": "former",
                "blood_pressure": "128/76",
            },
            "2023-06-15",
        ),
    ],
)
async def test_demo_record_candidates_and_dates(name, expected, measurement_date):
    text = (DATA / f"{name}.txt").read_text()
    assert "SYNTHETIC DEMO DATA - NOT A REAL HEALTH RECORD" in text
    result = await DocumentService().extract(
        DocumentExtractRequest(pages=[text], outside_ai_consent=False),
        today=date(2026, 10, 24),
    )
    assert result.status == "found"
    assert {c.field: c.value for c in result.candidates} == expected
    assert {c.date for c in result.candidates} == {measurement_date}
    for candidate in result.candidates:
        if candidate.field in {"blood_pressure", "hba1c", "ldl_cholesterol"}:
            assert candidate.use == "information"
    assert "prediction" not in result.model_dump()


def test_synthetic_voice_fixture_cannot_be_mistaken_for_real_participant_results():
    folder = ROOT / "demo" / "voice-usability"
    with (folder / "synthetic-sessions.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    summary = json.loads((folder / "synthetic-summary.json").read_text())
    assert len(rows) == 35
    assert {row["synthetic_demo"] for row in rows} == {"true"}
    assert len({row["participant_id"] for row in rows}) == 5
    assert summary["synthetic"] is True
    assert summary["real_participants"] == summary["real_sessions"] == 0
    assert summary["real_provider_measurements"] is False
    for person in summary["personas"]:
        assert len([row for row in rows if row["participant_id"] == person["id"]]) == 7
    for status in ["alone", "with_hint", "failed"]:
        assert sum(row["completion"] == status for row in rows) == summary["totals"][status]

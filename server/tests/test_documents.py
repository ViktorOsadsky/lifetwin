"""Document extraction against a synthetic, fake-patient corpus.

The corpus and its expected candidates (server/tests/data/documents/) were
written before the extractor, from the rules in docs/document-upload.md.
"""

import json
import logging
from datetime import date
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.documents import parser
from lifetwin.documents.models import DocumentExtractRequest
from lifetwin.documents.redact import redact
from lifetwin.documents.service import DocumentService
from lifetwin.onboarding.providers import ChatCompletionsExtractor

DATA = Path(__file__).parent / "data" / "documents"
CONTRACTS = Path(__file__).parents[2] / "contracts"
EXPECTED = json.loads((DATA / "expected.json").read_text())
LINES = json.loads((DATA / "lines.json").read_text())
TODAY = date(2026, 10, 24)


def pages(name: str) -> list[str]:
    return [p.strip("\n") for p in (DATA / f"{name}.txt").read_text().split("<<<PAGE>>>")]


def settings(**overrides) -> Settings:
    return Settings(
        _env_file=None,
        openai_api_key="",
        openai_model="",
        tavily_api_key="",
        cartesia_api_key="",
        cartesia_voice_id="",
        **overrides,
    )


async def run(name: str, service: DocumentService | None = None, consent: bool = False):
    request = DocumentExtractRequest(pages=pages(name), outside_ai_consent=consent)
    return await (service or DocumentService()).extract(request, today=TODAY)


def key(candidate: dict) -> tuple:
    value = candidate["value"]
    if isinstance(value, float | int) and not isinstance(value, bool):
        value = round(float(value), 1)
    return candidate["field"], value, candidate["unit"], candidate["date"]


@pytest.mark.parametrize("name", sorted(EXPECTED))
async def test_corpus_document(name):
    expected = EXPECTED[name]
    response = await run(name)
    body = response.model_dump(mode="json")
    got = sorted(key(c) for c in body["candidates"])
    want = sorted(key(c) for c in expected["candidates"])
    # Exact: a missing value is a recall miss, an extra one would be a wrong value.
    assert got == want
    assert body["status"] == expected["status"]
    assert set(body["notices"]) == set(expected["notices"])
    assert body["identifiers_removed"] >= expected["min_identifiers_removed"]
    text = json.dumps(body)
    for identifier in expected["forbidden"]:
        assert identifier not in text, identifier
    for want_candidate in expected["candidates"]:
        match = next(c for c in body["candidates"] if key(c) == key(want_candidate))
        assert want_candidate["snippet_contains"] in match["source_text"]


def test_corpus_has_no_false_diagnoses_or_wrong_values():
    """The headline numbers reported in docs/document-upload.md."""
    import asyncio

    wrong = missed = right = 0
    for name, expected in EXPECTED.items():
        body = asyncio.run(run(name)).model_dump(mode="json")
        got = {key(c) for c in body["candidates"]}
        want = {key(c) for c in expected["candidates"]}
        right += len(got & want)
        wrong += len(got - want)
        missed += len(want - got)
    assert wrong == 0
    assert missed == 0
    assert right == sum(len(e["candidates"]) for e in EXPECTED.values())


@pytest.mark.parametrize("case", LINES, ids=[c["line"][:40] for c in LINES])
def test_single_lines(case):
    section = case["section"].lower() if case["section"] else None
    found = parser.read_line(case["line"], 1, section, TODAY) if not _other(case) else []
    got = sorted((f.field, _round(f.value), f.unit) for f in found)
    want = sorted((e["field"], _round(e["value"]), e["unit"]) for e in case["expect"])
    assert got == want


def _other(case) -> bool:
    lines = parser.lines(
        [f"{case['section']}:\n{case['line']}" if case["section"] else case["line"]]
    )
    return lines[-1].other


def _round(value):
    return (
        round(float(value), 1)
        if isinstance(value, float | int) and not isinstance(value, bool)
        else value
    )


def test_identifiers_are_stripped_before_parsing():
    stripped = redact(
        [
            "Patient: Ada Fakename    DOB: 01/02/1950    MRN: 99887766\n"
            "Address: 42 Nowhere Rd, Faketown, ZZ 00000\n"
            "Phone (555) 010-0000  email ada@example.com\n"
            "Ms. Fakename was seen by Dr. Noone Real.\n"
            "Ada reports feeling well.\n"
            "Weight 150 lb"
        ]
    )
    text = stripped.pages[0]
    for identifier in ("Ada", "Fakename", "01/02/1950", "99887766", "42 Nowhere", "010-0000"):
        assert identifier not in text
    assert "ada@example.com" not in text
    assert "Noone" not in text
    assert "Weight 150 lb" in text
    assert stripped.patient_names == 1


def test_two_spellings_of_one_name_are_one_patient():
    stripped = redact(["Patient: Ada B. Fakename", "Name: FAKENAME, ADA"])
    assert stripped.patient_names == 1


def test_a_birth_date_is_never_a_reading_date():
    response = TestClient(create_app(settings())).post(
        "/api/documents/extract",
        json={"pages": ["DOB: 03/04/1950\nWeight: 70 kg"]},
    )
    assert response.status_code == 200
    (candidate,) = response.json()["candidates"]
    assert candidate["date"] is None
    assert candidate["confidence"] == "medium"


def test_route_validates_against_schema_and_stores_nothing(caplog):
    schema = json.loads((CONTRACTS / "documents.extract.schema.json").read_text())
    with TestClient(create_app(settings())) as client:
        caplog.set_level(logging.DEBUG)
        response = client.post("/api/documents/extract", json={"pages": pages("visit_summary")})
        assert response.status_code == 200
        Draft202012Validator(schema).validate(response.json())
        assert response.headers["cache-control"] == "no-store"
    # Not one line of the document reaches the logs.
    logged = "\n".join(record.getMessage() for record in caplog.records)
    for line in pages("visit_summary")[0].splitlines():
        if len(line.strip()) > 12:
            assert line.strip() not in logged


@pytest.mark.parametrize(
    "body",
    [
        {"pages": []},
        {"pages": ["x"] * 11},
        {"pages": ["x" * 12001]},
        {"pages": ["ok"], "outside_ai_consent": "yes"},
        {"pages": ["ok"], "image": "base64..."},
    ],
)
def test_invalid_requests(body):
    response = TestClient(create_app(settings())).post("/api/documents/extract", json=body)
    assert response.status_code == 422
    assert "x" * 50 not in response.text


def test_a_ten_page_document_fits_its_own_body_limit_but_not_beyond():
    client = TestClient(create_app(settings()))
    page = "Weight 150 lb\n" + "Normal exam. " * 900
    assert len(page) < 12000
    assert client.post("/api/documents/extract", json={"pages": [page] * 10}).status_code == 200
    # Other routes keep the small limit.
    big = {"action": "reply", "text": "x" * 40000}
    assert client.post("/api/onboarding/turn", json=big).status_code == 413


def muse_service(reply: dict | None, calls: list, *, enabled=True) -> DocumentService:
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(json.loads(request.content))
        if reply is None:
            return httpx.Response(500)
        return httpx.Response(
            200,
            json={
                "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(reply)}}]
            },
        )

    extractor = ChatCompletionsExtractor(
        base_url="https://muse.invalid/v1",
        api_key="test-key",
        model="muse-test",
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    return DocumentService(extractor, muse_enabled=enabled)


TABLE = [
    "Patient: Ada Fakename\nDate of service: 09/14/2026\nVitals\nWeight\n150 lb\n"
    "Problem list\nHTN\nFamily history\nMother\nType 2 diabetes"
]


async def test_muse_needs_consent_and_is_only_told_stripped_text():
    calls: list = []
    service = muse_service({"candidates": []}, calls)
    request = DocumentExtractRequest(pages=TABLE)
    response = await service.extract(request, today=TODAY)
    assert response.provider_status == "not_requested"  # the parser found HTN
    request = DocumentExtractRequest(pages=["Vitals\nWeight\n150 lb\nNothing else legible here"])
    response = await service.extract(request, today=TODAY)
    assert response.provider_status == "consent_required"
    assert calls == []

    reply = {"candidates": [{"field": "weight_kg", "quote": "Weight\n150 lb"}]}
    service = muse_service(reply, calls)
    # Force the Muse path: the parser found no measurement on the split table line.
    response = await service.extract(
        DocumentExtractRequest(
            pages=["Patient: Ada Fakename\nVitals\nWeight\n150 lb"], outside_ai_consent=True
        ),
        today=TODAY,
    )
    assert response.provider_status == "used"
    (candidate,) = response.candidates
    assert (candidate.field, candidate.value, candidate.method) == ("weight_kg", 68.0, "muse")
    assert candidate.confidence == "low"
    sent = json.dumps(calls[-1])
    assert "Fakename" not in sent and "Ada" not in sent


async def test_muse_cannot_invent_values_or_diagnoses():
    calls: list = []
    reply = {
        "candidates": [
            {"field": "weight_kg", "quote": "Weight 999 lb"},  # not in the text
            {"field": "diabetes_diagnosed", "quote": "Type 2 diabetes"},  # the mother's
            {"field": "height_cm", "quote": "150 lb"},  # wrong field for the quote
        ]
    }
    service = muse_service(reply, calls)
    response = await service.extract(
        DocumentExtractRequest(pages=TABLE, outside_ai_consent=True), today=TODAY
    )
    fields = {c.field for c in response.candidates}
    assert "diabetes_diagnosed" not in fields
    assert "height_cm" not in fields
    assert all(c.method == "parser" for c in response.candidates)


async def test_muse_failure_keeps_parser_results():
    service = muse_service(None, [])
    response = await service.extract(
        DocumentExtractRequest(
            pages=["Vitals\nWt 150 lb\nW?ght 1?0\nB? 1?0/8?"], outside_ai_consent=True
        ),
        today=TODAY,
    )
    assert response.provider_status == "unavailable"
    assert [c.field for c in response.candidates] == ["weight_kg"]


async def test_muse_is_off_unless_enabled():
    calls: list = []
    service = muse_service({"candidates": []}, calls, enabled=False)
    response = await service.extract(
        DocumentExtractRequest(pages=["Weight\n150 lb"], outside_ai_consent=True), today=TODAY
    )
    assert response.provider_status == "not_requested"
    assert calls == []


def test_app_offers_muse_only_when_opted_in_and_can_switch_it_off():
    muse = dict(llm_provider="chat_completions", llm_api_key="k", llm_model="m")
    # Owner ruling (2026-10-25): LLM_PROVIDER alone is not a documents opt-in.
    app = create_app(settings(**muse))
    assert app.state.document_service.muse_available is False
    assert app.state.document_service.provider == "claude"
    app = create_app(settings(**muse, document_provider="muse"))
    assert app.state.document_service.muse_available is True
    app = create_app(settings(**muse, document_provider="muse", document_muse_enabled=False))
    assert app.state.document_service.muse_available is False
    # Without a configured provider there is nothing to send to, whatever the flag says.
    app = create_app(settings())
    assert app.state.document_service.muse_available is False


def test_a_bare_name_under_a_spouse_heading_is_removed():
    text = redact(["Spouse / Partner\nLinda Mockwell\nWeight 148 lb"]).pages[0]
    assert "Linda" not in text and "Mockwell" not in text
    assert "Weight 148 lb" in text


# Hold-out lines, written after the parser to check it generalises beyond the corpus.
HOLDOUT = [
    ("Weight 182 lb (down 4 lb from last visit)", "vitals", [("weight_kg", 82.6)]),
    ("BP goal <130/80", "plan", []),
    ("History of gestational diabetes", "past medical history", []),
    ("Hypertension screening: normal", "assessment", []),
    (
        "1. Hypertension, well controlled on lisinopril",
        "assessment and plan",
        [("hypertension_diagnosed", True)],
    ),
    (
        "2. Type 2 diabetes mellitus with hyperglycemia (E11.65)",
        "assessment and plan",
        [("diabetes_diagnosed", True)],
    ),
    ("Diabetes education provided", "assessment and plan", []),
    ("No known history of hypertension or diabetes", "past medical history", []),
    (
        "Hx of HTN, DM2, HLD",
        "past medical history",
        [("hypertension_diagnosed", True), ("diabetes_diagnosed", True)],
    ),
    ("Hypertensive heart disease", "assessment", []),
    ("Smoker: No", "social history", []),
    (
        "Tobacco: current some day smoker, 5 cigarettes a day",
        "social history",
        [("smoking_status", "current")],
    ),
    (
        "Height: 66 in   Weight: 180 lb   BMI: 29.0",
        "vitals",
        [("height_cm", 167.6), ("weight_kg", 81.6)],
    ),
    ("Ht 1.68 m  Wt 80.5 kg", "vitals", [("height_cm", 168.0), ("weight_kg", 80.5)]),
    ("Weight (lb) 182.4", "vitals", [("weight_kg", 82.7)]),
    (
        "Temp 98.6 F  Pulse 72  Resp 16  BP 128/76  SpO2 97%",
        "vitals",
        [("blood_pressure", "128/76")],
    ),
    ("HbA1c goal < 7.0 %", "plan", []),
    ("Estimated weight 80 kg", "vitals", []),
    ("Diabetes type 2? vs steroid-induced", "assessment", []),
    ("Height 66", "vitals", []),  # no units: Mochi asks
    ("Metformin 500 mg for type 2 diabetes", "medications", []),
    # What Apple Vision really returned for "Wt 182 lb" on the simulator.
    (
        "BP 138/86 Wt 182 |b Ht 5 ft 6 in",
        "vitals",
        [("blood_pressure", "138/86"), ("weight_kg", 82.6), ("height_cm", 167.6)],
    ),
    ("Weight 70 Ibs", "vitals", [("weight_kg", 31.8)]),
]


@pytest.mark.parametrize("line,section,want", HOLDOUT, ids=[h[0][:40] for h in HOLDOUT])
def test_holdout_lines(line, section, want):
    got = [(f.field, f.value) for f in parser.read_line(line, 1, section, TODAY)]
    assert sorted(got, key=str) == sorted(want, key=str)

"""PDFs read by Claude (POST /api/documents/read): consent, limits, quote checks, fallbacks.

No live calls: the SDK client is a fake that records the request and returns a fixed reply.
"""

import asyncio
import base64
import json
import logging
from datetime import date
from pathlib import Path
from types import SimpleNamespace

import anthropic
import httpx2
import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.documents.models import MAX_PDF_BYTES, DocumentReadRequest
from lifetwin.documents.pdf import ClaudeDocumentReader, read_pdf

ROOT = Path(__file__).resolve().parents[2]
DEMO_PDF = ROOT / "output" / "pdf" / "demo-visit-summary.pdf"
TODAY = date(2026, 10, 24)
KEY = "test-key-not-real"
PROVIDER_ENV = (
    "ANTHROPIC_API_KEY",
    "CLAUDE_MODEL",
    "LLM_PROVIDER",
    "PERSONALIZE_PROVIDER",
    "DOCUMENT_PROVIDER",
    "LLM_API_KEY",
    "LLM_MODEL",
    "OPENAI_API_KEY",
)

VISIT = (
    "Riverside Clinic - Visit summary\n"
    "Patient: Testy McFakeface\n"
    "Date of service: 09/14/2026\n"
    "Vitals\n"
    "Weight: 182 lb\n"
    "Height: 5 ft 6 in\n"
    "Blood pressure: 138/86 mmHg\n"
    "Problem List\n"
    "Type 2 diabetes mellitus\n"
    "Family History\n"
    "Mother: hypertension\n"
)


def make_pdf(pages: list[str]) -> bytes:
    """A tiny, valid PDF whose pages carry a real text layer (Helvetica, one line per row)."""
    objects: list[bytes] = []
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(len(pages)))
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode())
    font = 3 + 2 * len(pages)
    for i, text in enumerate(pages):
        rows = []
        for line in text.split("\n"):
            safe = line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
            rows.append(f"({safe}) Tj T*")
        stream = ("BT /F1 11 Tf 14 TL 50 780 Td " + " ".join(rows) + " ET").encode("latin-1")
        objects.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 {font} 0 R >> >> /Contents {4 + 2 * i} 0 R >>".encode()
        )
        objects.append(
            b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream"
        )
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for n, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{n} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    return bytes(out)


def b64(data: bytes) -> str:
    return base64.standard_b64encode(data).decode()


def finding(field, value, quote, *, unit=None, page=1, section=None, when=None):
    return {
        "field": field,
        "value": value,
        "unit": unit,
        "quote": quote,
        "page": page,
        "section": section,
        "date": when,
    }


def message(text: str | None, stop_reason: str = "end_turn"):
    content = [] if text is None else [SimpleNamespace(type="text", text=text)]
    return SimpleNamespace(stop_reason=stop_reason, content=content, stop_details=None)


def reply(*findings) -> SimpleNamespace:
    return message(json.dumps({"findings": list(findings)}))


class FakeClient:
    def __init__(self, response):
        self.calls: list[dict] = []
        self.messages = self
        self._response = response

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if isinstance(self._response, BaseException):
            raise self._response
        if callable(self._response):
            return await self._response()
        return self._response


def reader(response, **kwargs) -> tuple[ClaudeDocumentReader, FakeClient]:
    client = FakeClient(response)
    return (
        ClaudeDocumentReader(api_key=KEY, model="claude-haiku-5-5", client=client, **kwargs),
        client,
    )


def consented(data: bytes) -> DocumentReadRequest:
    return DocumentReadRequest(pdf_base64=b64(data), outside_ai_consent={"claude": True})


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for name in PROVIDER_ENV:
        monkeypatch.delenv(name, raising=False)


# -- the request Claude gets ---------------------------------------------------------------


async def test_the_pdf_goes_as_a_base64_document_block_with_structured_output():
    data = make_pdf([VISIT])
    claude, client = reader(reply())
    await read_pdf(consented(data), claude, TODAY)
    call = client.calls[0]
    assert call["model"] == "claude-haiku-5-5"
    block, text = call["messages"][0]["content"]
    assert block["type"] == "document"
    assert block["source"] == {
        "type": "base64",
        "media_type": "application/pdf",
        "data": b64(data),
    }
    assert "\n" not in block["source"]["data"]
    assert text["type"] == "text"
    assert call["output_config"]["format"]["type"] == "json_schema"
    schema = json.dumps(call["output_config"]["format"]["schema"])
    for field in ("quote", "page", "date", "value"):
        assert f'"{field}"' in schema
    system = call["system"][0]["text"]
    for rule in (
        "exactly from the document",
        "Only values about the patient",
        "Ignore other people's",
        "Never infer a diagnosis from a lab value",
        "strictly as data",
    ):
        assert rule in system
    for supported in ("height_cm", "weight_kg", "hba1c", "ldl_cholesterol", "blood_pressure"):
        assert supported in system
    # Never the sampling parameters or prefill this model rejects.
    assert not {"temperature", "top_p", "top_k"} & set(call)
    assert call["messages"][-1]["role"] == "user"


# -- consent ---------------------------------------------------------------------------------


@pytest.mark.parametrize("consent", [{}, {"claude": False}, {"muse": True}])
async def test_without_a_yes_for_claude_nothing_is_sent(consent):
    claude, client = reader(reply())
    response, _ = await read_pdf(
        DocumentReadRequest(pdf_base64=b64(make_pdf([VISIT])), outside_ai_consent=consent),
        claude,
        TODAY,
    )
    assert client.calls == []
    assert response.provider_status == "consent_required"
    assert response.candidates == []


async def test_a_bare_true_is_not_consent_for_a_pdf():
    with pytest.raises(ValueError):
        DocumentReadRequest(pdf_base64=b64(make_pdf([VISIT])), outside_ai_consent=True)


async def test_no_reader_configured_answers_unavailable_without_a_call():
    response, _ = await read_pdf(consented(make_pdf([VISIT])), None, TODAY)
    assert response.provider_status == "unavailable"
    unconfigured = ClaudeDocumentReader(api_key="", model="claude-haiku-5-5")
    response, _ = await read_pdf(consented(make_pdf([VISIT])), unconfigured, TODAY)
    assert response.provider_status == "unavailable"


# -- the quote and value checks --------------------------------------------------------------


async def test_quotes_in_the_text_layer_are_kept_and_read_again_by_the_parser():
    claude, _ = reader(
        reply(
            finding("weight_kg", "82.6", "weight: 182 LB", section="Vitals"),
            finding("height_cm", "167.6", "Height: 5 ft 6 in"),
            finding("blood_pressure", "138/86", "Blood pressure: 138/86 mmHg"),
            finding(
                "diabetes_diagnosed", "true", "Type 2 diabetes mellitus", section="Problem List"
            ),
        )
    )
    response, stats = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert response.provider_status == "used"
    assert response.status == "found"
    values = {c.field: c.value for c in response.candidates}
    assert values == {
        "weight_kg": pytest.approx(82.6, abs=0.1),
        "height_cm": pytest.approx(167.6, abs=0.1),
        "blood_pressure": "138/86",
        "diabetes_diagnosed": True,
    }
    assert {c.method for c in response.candidates} == {"claude"}
    assert {c.date for c in response.candidates} == {"2026-09-14"}
    assert {c.page for c in response.candidates} == {1}
    weight = next(c for c in response.candidates if c.field == "weight_kg")
    assert weight.section == "Vitals" and weight.use == "model_input"
    bp = next(c for c in response.candidates if c.field == "blood_pressure")
    assert bp.use == "information" and bp.unit == "mmHg"
    # The patient's name never comes back, and nothing about Anthropic's retention is claimed.
    assert "Testy" not in response.model_dump_json()
    assert not any("retain" in line.lower() for line in response.limitations)
    assert (stats.returned, stats.kept, stats.dropped) == (4, 4, 0)


async def test_a_quote_missing_from_the_pdf_is_dropped_and_counted():
    claude, _ = reader(
        reply(
            finding("weight_kg", "82.6", "Weight: 182 lb"),
            finding("hba1c", "7.2", "Hemoglobin A1c: 7.2 %"),
        )
    )
    response, stats = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert [c.field for c in response.candidates] == ["weight_kg"]
    assert (stats.kept, stats.quote_not_found, stats.value_mismatch) == (1, 1, 0)


async def test_a_value_the_quote_does_not_say_is_dropped_and_counted():
    claude, _ = reader(
        reply(
            finding("weight_kg", "90", "Weight: 182 lb"),
            finding("blood_pressure", "128/82", "Blood pressure: 138/86 mmHg"),
            # A diagnosis inferred from a reading: the parser reads no diagnosis there.
            finding("hypertension_diagnosed", "true", "Blood pressure: 138/86 mmHg"),
        )
    )
    response, stats = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert response.candidates == []
    assert response.status == "nothing_found" and response.provider_status == "used"
    assert (stats.quote_not_found, stats.value_mismatch, stats.dropped) == (0, 3, 3)


async def test_other_peoples_lines_are_dropped():
    claude, _ = reader(reply(finding("hypertension_diagnosed", "true", "Mother: hypertension")))
    response, stats = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert response.candidates == []
    assert "other_person_skipped" in response.notices
    assert stats.other_person == 1


async def test_a_quote_on_another_page_keeps_its_real_page():
    second = "Lab Results\nHemoglobin A1c: 6.8 %\nLDL Cholesterol: 122 mg/dL\n"
    claude, _ = reader(
        reply(
            finding("hba1c", "6.8", "Hemoglobin A1c: 6.8 %", page=1),
            finding("ldl_cholesterol", "122", "LDL Cholesterol: 122 mg/dL", unit="mg/dL", page=2),
            finding("ldl_cholesterol", "3.2", "LDL Cholesterol: 122 mg/dL", unit="mmol/L", page=2),
        )
    )
    response, stats = await read_pdf(consented(make_pdf([VISIT, second])), claude, TODAY)
    assert {(c.field, c.value, c.page) for c in response.candidates} == {
        ("hba1c", 6.8, 2),
        ("ldl_cholesterol", 122.0, 2),
    }
    assert stats.value_mismatch == 1


async def test_a_scanned_pdf_keeps_parser_readable_quotes_at_low_confidence():
    claude, _ = reader(
        reply(
            finding("weight_kg", "78", "Weight: 78 kg", section="Vitals", when="2026-10-20"),
            finding("height_cm", "180", "Height: 165 cm"),
            finding("smoking_status", "former", "Former smoker, quit 2010"),
        )
    )
    response, stats = await read_pdf(consented(make_pdf([""])), claude, TODAY)
    assert not stats.text_layer
    assert {c.field: c.value for c in response.candidates} == {
        "weight_kg": 78.0,
        "smoking_status": "former",
    }
    assert {c.confidence for c in response.candidates} == {"low"}
    assert {c.date for c in response.candidates} == {"2026-10-20"}
    assert stats.value_mismatch == 1
    assert any("no text layer" in line for line in response.limitations)


async def test_the_demo_visit_summary_pdf_with_its_known_values():
    claude, _ = reader(
        reply(
            finding("height_cm", "165", "Height: 165 cm", section="Vitals", when="2026-10-20"),
            finding("weight_kg", "78", "Weight: 78 kg", section="Vitals", when="2026-10-20"),
            finding("blood_pressure", "132/78", "Blood pressure: 132/78 mmHg", when="2026-10-20"),
            finding("smoking_status", "former", "Former smoker, quit 2010"),
            finding("diabetes_diagnosed", "true", "Type 2 diabetes mellitus"),
            finding("hypertension_diagnosed", "true", "Essential hypertension"),
            finding("hba1c", "6.8", "Hemoglobin A1c: 6.8 %"),
            finding("ldl_cholesterol", "122", "LDL Cholesterol: 122 mg/dL", unit="mg/dL"),
        )
    )
    response, stats = await read_pdf(consented(DEMO_PDF.read_bytes()), claude, TODAY)
    assert {c.field: c.value for c in response.candidates} == {
        "height_cm": 165.0,
        "weight_kg": 78.0,
        "smoking_status": "former",
        "diabetes_diagnosed": True,
        "hypertension_diagnosed": True,
        "blood_pressure": "132/78",
        "hba1c": 6.8,
        "ldl_cholesterol": 122.0,
    }
    assert {c.date for c in response.candidates} == {"2026-10-20"}
    assert (stats.kept, stats.dropped) == (8, 0)
    assert "Rosa" not in response.model_dump_json()


async def test_several_patients_are_never_sent():
    two = VISIT + "Patient: Someone Else\nWeight: 150 lb\n"
    claude, client = reader(reply())
    response, _ = await read_pdf(consented(make_pdf([two])), claude, TODAY)
    assert client.calls == []
    assert response.notices == ["multiple_patients"]


# -- refusal, errors and the time budget ------------------------------------------------------


@pytest.mark.parametrize(
    "response",
    [
        message(None, "refusal"),
        message('{"findings": []', "max_tokens"),
        message("not json"),
        message('{"findings": [{"field": "age"}]}'),
        anthropic.APIConnectionError(
            request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
        ),
        anthropic.APITimeoutError(
            request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
        ),
    ],
    ids=["refusal", "cut_off", "not_json", "bad_shape", "connection", "sdk_timeout"],
)
async def test_failures_answer_unavailable_so_the_phone_reads_it(response):
    claude, client = reader(response)
    result, _ = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert len(client.calls) == 1
    assert result.provider_status == "unavailable"
    assert result.candidates == []


async def test_a_slow_reply_times_out_as_unavailable():
    async def slow():
        await asyncio.sleep(5)
        return reply()

    claude, _ = reader(slow, timeout_seconds=0.05)
    result, _ = await read_pdf(consented(make_pdf([VISIT])), claude, TODAY)
    assert result.provider_status == "unavailable"


def test_the_sdk_client_gets_the_documents_time_budget_and_no_retries(monkeypatch):
    built = {}

    def factory(**kwargs):
        built.update(kwargs)
        return FakeClient(reply())

    from lifetwin.core import claude as claude_module

    monkeypatch.setattr(claude_module.anthropic, "AsyncAnthropic", factory)
    claude = ClaudeDocumentReader(api_key=KEY, model="claude-haiku-5-5", timeout_seconds=25)
    asyncio.run(read_pdf(consented(make_pdf([VISIT])), claude, TODAY))
    assert built == {"api_key": KEY, "timeout": 25, "max_retries": 0}


# -- limits ------------------------------------------------------------------------------------


def app(**env) -> TestClient:
    settings = Settings(_env_file=None, anthropic_api_key=KEY, **env)
    application = create_app(settings)
    return TestClient(application)


def install(client: TestClient, response) -> FakeClient:
    claude, fake = reader(response)
    client.app.state.document_service.pdf_reader = claude
    return fake


def test_capabilities_name_claude_for_documents_and_muse_stays_pinned():
    with app(llm_provider="chat_completions", personalize_provider="muse") as client:
        caps = client.get("/api/capabilities").json()
    assert caps["documents"]["text_extraction"] is True
    assert caps["documents"]["pdf"] == {
        "provider": "claude",
        "display_name": "Claude by Anthropic",
        "company": "Anthropic",
        "configured": True,
        "endpoint": "/api/documents/read",
        "max_bytes": MAX_PDF_BYTES,
        "max_pages": 20,
    }
    assert caps["personalize"]["provider"] == "muse"
    assert KEY not in json.dumps(caps)


def test_without_an_anthropic_key_pdfs_stay_on_the_phone():
    settings = Settings(_env_file=None)
    assert settings.document_provider == "local"
    muse = Settings(_env_file=None, llm_provider="chat_completions")
    assert muse.document_provider == "muse"
    assert Settings(_env_file=None, anthropic_api_key=KEY).document_provider == "claude"
    assert (
        Settings(_env_file=None, anthropic_api_key=KEY, document_provider="local").document_provider
        == "local"
    )
    with TestClient(create_app(settings)) as client:
        assert client.get("/api/capabilities").json()["documents"]["pdf"]["configured"] is False
        body = client.post(
            "/api/documents/read",
            json={"pdf_base64": b64(make_pdf([VISIT])), "outside_ai_consent": {"claude": True}},
        ).json()
    assert body["provider_status"] == "unavailable"


def test_the_route_returns_the_extract_shape():
    with app() as client:
        fake = install(client, reply(finding("weight_kg", "82.6", "Weight: 182 lb")))
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": b64(make_pdf([VISIT])), "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 200
    body = r.json()
    assert set(body) == {
        "schema_version",
        "status",
        "candidates",
        "notices",
        "identifiers_removed",
        "provider_status",
        "limitations",
    }
    assert set(body["candidates"][0]) == {
        "field",
        "use",
        "value",
        "unit",
        "date",
        "date_basis",
        "source_text",
        "page",
        "section",
        "confidence",
        "method",
    }
    assert len(fake.calls) == 1


def test_the_route_without_consent_never_calls_claude():
    with app() as client:
        fake = install(client, reply())
        body = client.post(
            "/api/documents/read", json={"pdf_base64": b64(make_pdf([VISIT]))}
        ).json()
    assert body["provider_status"] == "consent_required"
    assert fake.calls == []


def test_too_many_pages_is_a_gentle_422():
    with app() as client:
        fake = install(client, reply())
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": b64(make_pdf(["x"] * 21)), "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 422
    assert r.json()["code"] == "pdf_too_many_pages"
    assert "20 pages" in r.json()["message"]
    assert fake.calls == []


def test_over_ten_megabytes_is_a_gentle_413():
    data = make_pdf([VISIT])
    # One byte over the decoded limit; its base64 still fits the request field.
    big = data + b"%" * (MAX_PDF_BYTES + 1 - len(data))
    with app() as client:
        fake = install(client, reply())
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": b64(big), "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 413
    assert r.json()["code"] == "pdf_too_large"
    assert "10 MB" in r.json()["message"]
    assert fake.calls == []


def test_a_longer_base64_field_is_a_gentle_422():
    with app() as client:
        install(client, reply())
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": "A" * 13_981_020, "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 422
    assert "10 MB" in r.json()["message"]


def test_the_body_limit_rejects_far_larger_bodies_before_parsing():
    with app(max_pdf_body_bytes=2048) as client:
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": "A" * 4000, "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 413
    assert "10 MB" in r.json()["message"]


@pytest.mark.parametrize(
    "payload,code",
    [(b64(b"hello, not a pdf"), "pdf_unreadable"), ("@@not base64@@", "pdf_unreadable")],
)
def test_not_a_pdf_is_a_gentle_422(payload, code):
    with app() as client:
        install(client, reply())
        r = client.post(
            "/api/documents/read",
            json={"pdf_base64": payload, "outside_ai_consent": {"claude": True}},
        )
    assert r.status_code == 422
    assert r.json()["code"] == code


# -- privacy -----------------------------------------------------------------------------------


def test_nothing_from_the_document_reaches_the_logs(caplog):
    caplog.set_level(logging.DEBUG)
    secret = VISIT.replace("Testy McFakeface", "Zebulon Quartzfield")
    replies = [
        reply(
            finding("weight_kg", "82.6", "Weight: 182 lb"),
            finding("hba1c", "9.9", "Hemoglobin A1c: 9.9 %"),
        ),
        message(None, "refusal"),
        anthropic.APIConnectionError(
            request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
        ),
    ]
    for response in replies:
        with app() as client:
            install(client, response)
            client.post(
                "/api/documents/read",
                json={
                    "pdf_base64": b64(make_pdf([secret])),
                    "outside_ai_consent": {"claude": True},
                },
            )
    text = caplog.text
    assert "documents read: returned=2 kept=1 dropped=1" in text
    for leaked in ("Zebulon", "Quartzfield", "182", "82.6", "9.9", "138/86", "diabetes", KEY):
        assert leaked not in text

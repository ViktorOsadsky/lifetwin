"""Bug hunt 2: request-error wording and contract edge cases outside the fixtures."""

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings


@pytest.fixture(scope="module")
def client():
    settings = Settings(
        _env_file=None,
        app_env="test",
        openai_api_key="",
        openai_model="",
        anthropic_api_key="",
        tavily_api_key="",
        cartesia_api_key="",
        cartesia_voice_id="",
        rate_limit_per_minute=1000,
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


@pytest.mark.parametrize("body", [{"pages": []}, {"pages": [42]}, {"pages": "Weight 150 lb"}])
def test_document_text_that_is_not_too_long_is_not_called_too_long(client, body):
    response = client.post("/api/documents/extract", json=body)
    assert response.status_code == 422
    assert "too many pages" not in response.json()["message"]


def test_document_with_too_many_pages_still_says_so(client):
    response = client.post("/api/documents/extract", json={"pages": ["Weight 150 lb"] * 11})
    assert response.status_code == 422
    assert "too many pages" in response.json()["message"]


@pytest.mark.parametrize("pdf", ["@@@", "", 12345])
def test_unreadable_pdf_field_is_not_called_too_big(client, pdf):
    response = client.post(
        "/api/documents/read", json={"pdf_base64": pdf, "outside_ai_consent": {"claude": True}}
    )
    assert response.status_code == 422
    assert "too big" not in response.json()["message"]


def test_oversized_pdf_field_still_says_too_big(client):
    from lifetwin.documents.models import MAX_PDF_BASE64_CHARS

    response = client.post(
        "/api/documents/read",
        json={"pdf_base64": "A" * (MAX_PDF_BASE64_CHARS + 4)},
    )
    assert response.status_code in (413, 422)
    if response.status_code == 422:
        assert "too big" in response.json()["message"]

"""Bug hunt 2: ideas, coach safety gates and documents. Each test failed before its fix."""

import subprocess
import sys
from datetime import date

import pytest
from fastapi.testclient import TestClient
from test_documents_pdf import (
    TODAY,
    VISIT,
    consented,
    finding,
    make_pdf,
    reader,
    reply,
)

import lifetwin.onboarding  # noqa: F401  (import first: avoids a pre-existing import cycle)
from lifetwin.app import create_app
from lifetwin.coach import safety
from lifetwin.core.config import Settings
from lifetwin.core.models import HealthProfile
from lifetwin.documents.models import MAX_PDF_BYTES
from lifetwin.documents.pdf import read_pdf
from lifetwin.onboarding.models import HabitNote
from lifetwin.recommendations.ideas import IDEAS
from lifetwin.recommendations.service import suggest


@pytest.fixture(scope="module")
def client():
    app = create_app(
        Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000, llm_api_key="")
    )
    return TestClient(app)


def plan(client, said, **extra):
    r = client.post("/api/coach/plan", json={"local_date": "2026-10-24", "said": said, **extra})
    assert r.status_code == 200, r.text
    return r.json()


# -- under 18 / unknown age never get a vigorous idea ----------------------------------------


@pytest.mark.parametrize("age", [0, 10, 17])
def test_no_vigorous_idea_below_18(age):
    profile = HealthProfile(
        age=age, moderate_recreation_min_week=60, vigorous_recreation_min_week=0
    )
    notes = [HabitNote(topic="exercise", kind="walking")]
    vigorous = {i.id for i in IDEAS if i.lever == "vigorous_plus_60"}
    # Setting every pace idea but one aside must not let the last one through either.
    for day in range(1, 29):
        for excluded in ([], sorted(vigorous)[:-1]):
            for rec in suggest(profile, notes, date(2026, 10, day), excluded):
                for shown in (rec, *rec.alternatives):
                    assert shown.lever != "vigorous_plus_60", (age, day, shown.id)
                    assert shown.id not in vigorous


def test_an_adult_still_gets_pace_ideas():
    profile = HealthProfile(age=45, moderate_recreation_min_week=60, vigorous_recreation_min_week=0)
    notes = [HabitNote(topic="exercise", kind="walking")]
    recs = suggest(profile, notes, date(2026, 10, 24))
    assert any(r.lever == "vigorous_plus_60" for r in recs)


# -- supplement, stimulant, performance and weight-loss products --------------------------------

PRODUCTS = [
    "should I try garcinia cambogia",
    "what about yohimbine",
    "is DMAA ok before the gym",
    "my friend takes phentermine",
    "should I take creatines",
    "I want a fat burner",
    "any good fat-burners",
    "is a fatburner safe",
    "what about ephedrine",
    "SARMs for muscle",
    "should I use a testosterone booster",
    "a thermogenic before walking",
    "is hydroxycut any good",
    "I take Centrum every day",
    "Nature Made zinc",
    "any appetite suppressant",
    "BCAA before my walk",
    "I take 500 mg after dinner",
    "should I take 5g of something",
    "what about adderall to focus",
    "Take B-12 daily",
    "I use clenbuterol",
    "ｖｉｔａｍｉｎ D",
    "v​itamin D",
]


@pytest.mark.parametrize("text", PRODUCTS)
def test_the_coach_gate_catches_product_questions(client, text):
    out = plan(client, text)
    assert out["reply"] is not None, text


@pytest.mark.parametrize(
    "slot", ["yohimbine", "creatines", "garcinia", "DMAA", "phentermine", "Centrum", "fat burner"]
)
def test_note_slots_never_carry_a_product(slot):
    assert not safety.safe_slot(slot)


DRAFT = "A short walk after lunch is a lovely way to enjoy the day."


@pytest.mark.parametrize(
    "extra",
    [
        " ｖｉｔａｍｉｎ",  # fullwidth letters have no ASCII token
        " ビタミン",  # katakana
        " 购买",  # Chinese "buy"
        " Try yohimbine.",
        " Try phentermine.",
        " Try creatines.",
    ],
)
def test_a_provider_line_cannot_add_words_in_other_scripts_or_new_products(extra):
    assert not safety.safe_line(DRAFT + extra, DRAFT)


def test_a_provider_line_with_a_lookalike_letter_is_refused():
    assert not safety.safe_line(DRAFT.replace("walk", "wаlk"), DRAFT)  # Cyrillic a


def test_a_plain_rewording_still_passes():
    assert safety.safe_line("A short walk after lunch is a lovely way to enjoy your day.", DRAFT)


# -- the 911 line ---------------------------------------------------------------------------------

EMERGENCIES = [
    "I'm not breathing",
    "he stopped breathing",
    "can't breath",
    "cant breath",
    "I want to kill my self",
    "cutting myself",
    "I'm suffocating",
    "I'm dying",
    "I think I'm having a seizure",
    "I'm bleeding heavily",
    "severe bleeding",
    "I was poisoned",
    "I took too many tablets",
    "chest p​ain",
    "ｃhest pain",
]


@pytest.mark.parametrize("text", EMERGENCIES)
def test_these_phrasings_get_the_911_line(client, text):
    assert safety.is_emergency(text), text
    out = plan(client, text)
    assert out["status"] == "emergency" and out["items"] == []


@pytest.mark.parametrize(
    "text",
    [
        "I'm dying to try the new park",
        "my dad had a heart attack",
        "I had chest pain years ago",
        "I walk to the shops",
        "I cut myself chopping onions",
    ],
)
def test_near_misses_do_not_trigger_the_911_line(text):
    assert not safety.is_emergency(text)


# -- import order -----------------------------------------------------------------------------------


def test_the_coach_package_imports_first_without_a_cycle():
    done = subprocess.run(
        [sys.executable, "-c", "import lifetwin.coach.safety"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert done.returncode == 0, done.stderr[-400:]


# -- documents: PDF limits and scans -------------------------------------------------------------


async def test_a_pdf_of_exactly_ten_megabytes_is_read_and_one_byte_more_is_refused():
    data = make_pdf([VISIT])
    exact = data + b"\n%" + b"x" * (MAX_PDF_BYTES - len(data) - 2)
    assert len(exact) == MAX_PDF_BYTES
    claude, fake = reader(reply(finding("weight_kg", "82.6", "Weight: 182 lb")))
    response, _ = await read_pdf(consented(exact), claude, TODAY)
    assert response.provider_status == "used"
    from lifetwin.documents.pdf import PdfRejected

    with pytest.raises(PdfRejected) as err:
        await read_pdf(consented(exact + b"x"), claude, TODAY)
    assert err.value.status == 413


async def test_a_scanned_pdf_with_no_text_is_a_clear_answer_not_an_error():
    claude, _ = reader(reply())
    response, stats = await read_pdf(consented(make_pdf([""])), claude, TODAY)
    assert response.status == "nothing_found" and not stats.text_layer
    assert any("no text layer" in line for line in response.limitations)

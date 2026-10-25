"""Adversarial onboarding tests: several answers in one reply, answers for another question,
"I don't know", birth years and sex at birth. Written from the product rules, over HTTP.
"""

from datetime import date

import pytest
from fastapi.testclient import TestClient

from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.onboarding.parsing import parse_reply

FIELDS = [
    "age",
    "sex",
    "height_cm",
    "weight_kg",
    "sleep_hours",
    "exercise_minutes_weekly",
    "smoking_status",
    "alcohol_drinks_weekly",
    "diabetes",
    "systolic_bp",
    "general_health",
    "sedentary_min_day",
    "moderate_recreation_min_week",
    "vigorous_recreation_min_week",
]


@pytest.fixture(scope="module")
def client():
    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            rate_limit_per_minute=10000,
            llm_api_key="",
            openai_api_key="",
            openai_model="",
        )
    )
    return TestClient(app)


def turn(client, action, state=None, **values):
    body = {"action": action, **({"state": state} if state else {}), **values}
    response = client.post("/api/onboarding/turn", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def begin(client):
    return turn(client, "reply", turn(client, "start")["state"], text="yes")


def first_reply(client, text):
    return turn(client, "reply", begin(client)["state"], text=text)


def asking(field):
    return {"phase": "asking", "current_field": field}


def filled(profile):
    return {k: v for k, v in profile.items() if v is not None}


# --- Several answers in one reply -----------------------------------------------------------------------------


def test_one_sentence_fills_age_and_sleep_and_invents_nothing_for_the_walk(client):
    out = first_reply(client, "I'm 72, I walk every morning and sleep about six hours")
    pending = filled(out["state"]["pending_profile"])
    # "every morning" gives no duration, so no minutes may be made up.
    assert pending == {"age": 72, "sleep_hours": 6.0}
    assert out["state"]["confirmed_profile"]["age"] is None  # read back first
    assert "72" in out["message"] and "6" in out["message"]
    confirmed = turn(client, "confirm", out["state"])["state"]["confirmed_profile"]
    assert filled(confirmed) == {"age": 72, "sleep_hours": 6.0}


def test_a_long_reply_fills_every_field_it_names(client):
    out = first_reply(client, "72, female, 5 foot 4, 150 pounds")
    assert filled(out["state"]["pending_profile"]) == {
        "age": 72,
        "sex": "female",
        "height_cm": pytest.approx(162.56),
        "weight_kg": pytest.approx(68.0389),
    }


def test_a_walk_with_a_duration_counts_as_light_activity_not_hard_exercise(client):
    out = first_reply(client, "I'm 72 and I walk 30 minutes every morning")
    pending = filled(out["state"]["pending_profile"])
    assert pending["age"] == 72
    assert pending.get("vigorous_recreation_min_week") in (None, 0)
    assert (
        pending.get("moderate_recreation_min_week", pending.get("exercise_minutes_weekly")) == 210
    )


def test_an_unclear_clause_does_not_throw_away_the_clear_ones(client):
    out = first_reply(client, "I'm 72 and sleep six hours and I don't smoke")
    pending = filled(out["state"]["pending_profile"])
    assert pending.get("age") == 72 and pending.get("sleep_hours") == 6.0


def test_the_same_facts_with_a_clear_smoking_clause_all_land(client):
    out = first_reply(client, "I'm 72, I sleep about six hours and I have never smoked")
    assert filled(out["state"]["pending_profile"]) == {
        "age": 72,
        "sleep_hours": 6.0,
        "smoking_status": "never",
    }


# --- Info that belongs to another question ----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("field", "text", "expected"),
    [
        ("age", "I sleep 7 hours", {"sleep_hours": 7.0}),
        ("sleep_hours", "I'm male", {"sex": "male"}),
        ("sleep_hours", "I smoke", {"smoking_status": "current"}),
        ("sex", "female and 68", {"sex": "female", "age": 68}),
        ("smoking_status", "I sleep about 6 hours", {"sleep_hours": 6.0}),
    ],
)
def test_an_answer_for_another_question_goes_there_not_into_the_asked_one(
    client, field, text, expected
):
    out = turn(client, "reply", asking(field), text=text)
    pending = filled(out["state"]["pending_profile"])
    for key, value in expected.items():
        assert pending[key] == value
    assert set(pending) == set(expected)  # nothing leaked into the asked field


@pytest.mark.parametrize(
    "text", ["my wife is 66", "my daughter is 40", "she is 70", "my mother sleeps 9 hours"]
)
def test_someone_elses_numbers_are_never_taken_as_yours(client, text):
    out = turn(client, "reply", asking("age"), text=text)
    assert filled(out["state"]["pending_profile"]) == {}


@pytest.mark.parametrize("text", ["I'm 150", "I'm 121", "age 0 maybe", "35.5"])
def test_impossible_ages_stay_unanswered(client, text):
    out = turn(client, "reply", asking("age"), text=text)
    assert out["state"]["pending_profile"]["age"] is None
    assert out["state"]["phase"] == "asking"


# --- "I don't know" ----------------------------------------------------------------------------------------------


@pytest.mark.parametrize("field", FIELDS)
@pytest.mark.parametrize("text", ["I don't know", "idk", "no idea", "not sure", "I have no clue"])
def test_i_dont_know_records_nothing_and_never_a_zero(client, field, text):
    out = turn(client, "reply", asking(field), text=text)
    assert filled(out["state"]["pending_profile"]) == {}, text
    assert filled(out["state"]["confirmed_profile"]) == {}
    assert out["message"]
    assert out["state"]["phase"] in {"asking", "offering", "probing"}


def test_answering_i_dont_know_to_everything_completes_with_nothing_filled(client):
    result = begin(client)
    for _ in range(60):
        if result["complete"]:
            break
        text = "no thanks" if result["state"]["phase"] == "offering" else "I don't know"
        result = turn(client, "reply", result["state"], text=text)
    assert result["complete"] is True
    assert filled(result["state"]["confirmed_profile"]) == {}


# --- Birth year ---------------------------------------------------------------------------------------------------


@pytest.mark.parametrize("text", ["born in 1980", "I was born in 1980", "1980"])
def test_a_birth_year_becomes_an_age_that_is_read_back(client, text):
    today = date.today()
    out = first_reply(client, text)
    age = out["state"]["pending_profile"]["age"]
    assert age in {today.year - 1980, today.year - 1981}
    assert out["state"]["confirmed_profile"]["age"] is None
    assert out["state"]["phase"] == "confirming"
    assert str(age) in out["message"]


@pytest.mark.parametrize("text", ["born in 2090", "born in 1850", "my wife was born in 1950"])
def test_impossible_or_foreign_birth_years_are_not_an_age(client, text):
    out = turn(client, "reply", asking("age"), text=text)
    assert out["state"]["pending_profile"]["age"] is None


def test_a_stated_age_wins_over_a_birth_year_that_disagrees(client):
    out = turn(client, "reply", asking("age"), text="I'm 72, born in 1960")
    assert out["state"]["pending_profile"]["age"] is None or out["state"]["phase"] != "confirming"


# --- Sex at birth only --------------------------------------------------------------------------------------------


@pytest.mark.parametrize("text", ["I was born intersex", "I'm intersex", "intersex"])
def test_intersex_is_never_turned_into_a_sex_and_the_two_options_are_explained(client, text):
    out = turn(client, "reply", asking("sex"), text=text)
    assert out["state"]["pending_profile"]["sex"] is None
    assert out["state"]["confirmed_profile"]["sex"] is None
    assert "female or male at birth" in out["message"]


@pytest.mark.parametrize(
    "text", ["prefer not to say", "I'd rather not say", "prefer not to answer"]
)
def test_prefer_not_to_say_skips_sex_without_picking_one(client, text):
    out = turn(client, "reply", asking("sex"), text=text)
    assert out["state"]["pending_profile"]["sex"] is None
    assert "sex" in out["state"]["skipped_fields"]


@pytest.mark.parametrize("text", ["I identify as non-binary", "both", "neither", "other"])
def test_other_answers_do_not_pick_a_sex(client, text):
    out = turn(client, "reply", asking("sex"), text=text)
    assert out["state"]["pending_profile"]["sex"] is None


@pytest.mark.parametrize(
    ("text", "sex"),
    [("female", "female"), ("Male", "male"), ("assigned female at birth", "female")],
)
def test_plain_sex_at_birth_is_read_back_before_it_counts(client, text, sex):
    out = turn(client, "reply", asking("sex"), text=text)
    assert out["state"]["pending_profile"]["sex"] == sex
    assert out["state"]["confirmed_profile"]["sex"] is None
    assert "at birth" in out["message"]


@pytest.mark.parametrize(
    "text",
    [
        "I'm a trans woman",
        "I'm a trans man",
        "I identify as a woman",
        "my gender is male",
    ],
)
def test_gender_identity_is_not_sex_at_birth(text):
    assert parse_reply(text, "sex", today=date(2026, 10, 24)) == {}

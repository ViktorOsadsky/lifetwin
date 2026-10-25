"""#124: fake-provider copy cannot add claims to trusted server actions/questions."""

import logging

import pytest
from fastapi.testclient import TestClient

import lifetwin.onboarding  # noqa: F401 (load before recommendations; existing import cycle)
from lifetwin.app import create_app
from lifetwin.core.config import Settings
from lifetwin.onboarding.intents import CARE_QUESTION, SAFETY_PHRASE
from lifetwin.personalize.providers import PhrasingUnavailable
from lifetwin.personalize.safety import grounded_line, wording_choices
from lifetwin.personalize.service import phrase_question

# Synthetic values only. No external provider/key/network is used.
PROFILE = {
    "age": 64,
    "sex": "female",
    "smoking_status": "current",
    "sleep_hours": 6,
    "moderate_recreation_min_week": 0,
    "vigorous_recreation_min_week": 0,
}
ATTACKS = [
    "Getting heavier helps your health.",
    "Putting on mass improves your outlook.",
    "A bigger body makes you healthier.",
    "Bulking up protects your heart.",
    "Eating more will improve your future.",
    "Building body mass is the key to better health.",
    "It pays to become larger.",
    "You can reverse diabetes by walking.",
    "This walk makes your future safer.",
    "Skip sleep and exercise instead.",
    "Smoke for free, friendly support.",  # same harmless-looking vocabulary, different action
    "Getting he\u200bavier helps your health.",
    "Getting he\u0430vier helps your health.",  # Cyrillic a
    "Ｇｅｔｔｉｎｇ ｈｅａｖｉｅｒ ｈｅｌｐｓ ｙｏｕｒ ｈｅａｌｔｈ．",
    "Getting h3avier helps your health.",
    "Getting h e a v i e r helps your health.",
    "\u202ePutting on mass improves your outlook.\u202c",
    "Getting\u00a0heavier helps your health.",
    "Try vitamin D, after checking with your doctor.",
]


class Provider:
    name = "muse"
    configured = True
    may_train_on_content = False

    def __init__(self, rewrite):
        self.rewrite = rewrite
        self.calls = 0

    async def phrase(self, instructions, facts):
        self.calls += 1
        if "items" in facts:
            return {"lines": [self.rewrite(item) for item in facts["items"]]}
        return {"line": self.rewrite(facts)}


def client(provider=None):
    app = create_app(
        Settings(
            _env_file=None,
            app_env="test",
            rate_limit_per_minute=10000,
            llm_api_key="",
            openai_api_key="",
            cartesia_api_key="",
        )
    )
    if provider:
        app.state.personalizer = provider
        app.state.conversation_service.personalizer = provider
        app.state.coach_phraser = provider
        app.state.checkin_service.personalizer = provider
    return TestClient(app)


def request(endpoint, *, consent=False):
    body = {"profile": PROFILE, "habit_notes": []}
    if consent:
        body["outside_ai_consent"] = {"muse": True}
    if endpoint == "/api/onboarding/turn":
        body = {
            "action": "confirm",
            "state": {
                "phase": "confirming",
                "memory_consent": False,
                # The one offer of the missing answers was already made (and declined).
                "missing_offered": True,
                "confirmed_profile": PROFILE,
                "pending_profile": {"height_cm": 160},
                "skipped_fields": [
                    "weight_kg",
                    "diabetes",
                    "hypertension_diagnosed",
                    "general_health",
                    "sedentary_min_day",
                ],
                "health_offered": True,
            },
            **({"outside_ai_consent": {"muse": True}} if consent else {}),
        }
    elif endpoint == "/api/coach/plan":
        body["local_date"] = "2026-10-24"
    return body


def post(c, endpoint, **kwargs):
    response = c.post(endpoint, json=request(endpoint, **kwargs))
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize("endpoint", ["/api/recommendations", "/api/onboarding/turn"])
@pytest.mark.parametrize("attack", ATTACKS)
@pytest.mark.parametrize("append", [False, True], ids=["replacement", "mixed-with-draft"])
def test_unapproved_claims_fall_back_on_both_recommendation_surfaces(endpoint, attack, append):
    provider = Provider(lambda item: (item["draft"] + " " if append else "") + attack)
    baseline = post(client(), endpoint)
    out = post(client(provider), endpoint, consent=True)
    assert provider.calls == 1  # exercise validation, not the no-consent path
    assert out["recommendations"] == baseline["recommendations"]
    assert out["phrased_by"] == "templates"
    assert attack not in out.get("message", "")


@pytest.mark.parametrize("line", ATTACKS[:3])
def test_original_reproduction_remains_rejected_by_coach(line):
    provider = Provider(lambda item: item["draft"] + " " + line)
    baseline = post(client(), "/api/coach/plan")
    out = post(client(provider), "/api/coach/plan", consent=True)
    assert provider.calls == 1
    assert out["items"] == baseline["items"]
    assert out["lines"] == baseline["lines"]
    assert out["provider_status"] == "fallback"


@pytest.mark.parametrize("index", [0, 1, 2])
@pytest.mark.parametrize("endpoint", ["/api/recommendations", "/api/onboarding/turn"])
def test_all_bounded_choices_preserve_actions_evidence_values_and_effects(endpoint, index):
    provider = Provider(lambda item: "  " + item["approved_wordings"][index] + "  ")
    baseline = post(client(), endpoint)
    out = post(client(provider), endpoint, consent=True)
    assert provider.calls == 1 and out["phrased_by"] == "muse"
    assert len(out["recommendations"]) == len(baseline["recommendations"]) > 0
    for rec, original in zip(out["recommendations"], baseline["recommendations"], strict=True):
        assert rec["message"] == wording_choices(original["message"])[index]
        assert {k: v for k, v in rec.items() if k != "message"} == {
            k: v for k, v in original.items() if k != "message"
        }
    if endpoint.endswith("turn"):
        assert out["state"] == baseline["state"]
        assert out["model_inputs"] == baseline["model_inputs"]
        assert out["recommendations"][0]["message"] in out["message"]


def test_safe_but_unrecognized_action_wording_deliberately_falls_back():
    provider = Provider(lambda item: "You could ask for support whenever you feel ready.")
    baseline = post(client(), "/api/recommendations")
    out = post(client(provider), "/api/recommendations", consent=True)
    assert provider.calls == 1 and out["phrased_by"] == "templates"
    assert out["recommendations"] == baseline["recommendations"]


@pytest.mark.parametrize(
    "suffix", ["\n", "\r", "\t", "\u200b", "\u202e", "\u00a0", " <b>Try more.</b>"]
)
def test_untrusted_controls_and_hidden_appended_text_are_not_stripped_into_acceptance(suffix):
    draft = "You could try a short walk."
    assert grounded_line(draft + suffix, wording_choices(draft)) is None


@pytest.mark.parametrize("reply", [None, True, 42, {}, [], "", "x" * 10000])
def test_malformed_copy_cannot_be_published(reply):
    assert grounded_line(reply, wording_choices("A short walk.")) is None


def test_recombined_approved_words_cannot_reverse_an_action_or_drop_cautions():
    draft = "Do not stop taking medicine. Ask your doctor about movement."
    assert (
        grounded_line(
            "Stop taking medicine. Do not ask your doctor about movement.", wording_choices(draft)
        )
        is None
    )
    assert grounded_line("Ask your doctor about movement.", wording_choices(draft)) is None
    assert grounded_line(draft, draft) is None  # a string/facts blob is not an allowlist


@pytest.mark.parametrize(
    "topic,slot",
    [
        ("smoking", "quit_aid"),
        ("sleep", "bedtime"),
        ("sleep", "wakes_for"),
        ("exercise", "kind"),
        ("exercise", "with"),
        ("exercise", "barrier"),
    ],
)
def test_free_text_note_drafts_never_become_trusted_provider_choices(topic, slot):
    observed = []

    def choose(item):
        observed.append(item)
        return item["approved_wordings"][-1] if item["approved_wordings"] else item["draft"]

    provider = Provider(choose)
    payload = request("/api/recommendations", consent=True)
    payload["habit_notes"] = [
        {
            "topic": topic,
            slot: "putting on mass improves your outlook",
            **({"tried_quitting": "yes"} if topic == "smoking" else {}),
        }
    ]
    out = client(provider).post("/api/recommendations", json=payload)
    assert out.status_code == 200
    assert provider.calls == 1
    # Other unquoted actions can be eligible; this action retains its existing template.
    notes = [item for item in observed if item["said"]]
    assert notes and all(item["approved_wordings"] == [] for item in notes)
    baseline = client().post("/api/recommendations", json=payload).json()
    for rec, original in zip(
        out.json()["recommendations"], baseline["recommendations"], strict=True
    ):
        if f"note:{topic}" in original["based_on"]:
            assert rec == original


def test_provider_cannot_mutate_its_payload_to_define_new_approved_lines():
    def poison(item):
        item["approved_wordings"].append("Getting heavier helps your health.")
        return item["approved_wordings"][-1]

    provider = Provider(poison)
    out = post(client(provider), "/api/recommendations", consent=True)
    baseline = post(client(), "/api/recommendations")
    assert out["phrased_by"] == "templates"
    assert out["recommendations"] == baseline["recommendations"]


@pytest.mark.parametrize("attack", ATTACKS)
async def test_question_copy_cannot_introduce_claims_or_use_said_as_authority(attack):
    draft = "How many hours do you sleep?"
    provider = Provider(lambda facts: attack + " " + facts["line"])
    assert await phrase_question(provider, draft, attack) is None
    assert provider.calls == 1


@pytest.mark.parametrize("index", [0, 1, 2])
async def test_bounded_question_keeps_the_same_complete_question(index):
    draft = "How many hours do you sleep?"
    provider = Provider(lambda facts: facts["approved_wordings"][index])
    assert (
        await phrase_question(provider, draft, "untrusted words")
        == wording_choices(draft, question=True)[index]
    )


def test_bad_provider_copy_is_not_logged(caplog):
    sentinel = "PRIVATE_SYNTHETIC_COPY Getting heavier helps your health."
    with caplog.at_level(logging.DEBUG):
        out = post(client(Provider(lambda item: sentinel)), "/api/recommendations", consent=True)
    assert out["phrased_by"] == "templates"
    assert sentinel not in caplog.text


def test_only_note_derived_drafts_do_not_call_provider():
    provider = Provider(lambda item: item["draft"])
    payload = {
        "profile": {"sleep_hours": 6},
        "habit_notes": [{"topic": "sleep", "bedtime": "midnight"}],
        "outside_ai_consent": {"muse": True},
    }
    out = client(provider).post("/api/recommendations", json=payload)
    baseline = client().post("/api/recommendations", json=payload)
    assert out.status_code == 200 and provider.calls == 0
    assert out.json() == baseline.json()


@pytest.mark.parametrize("failure", [TimeoutError, PhrasingUnavailable])
def test_provider_failure_retains_deterministic_recommendations(failure):
    class Unavailable(Provider):
        async def phrase(self, instructions, facts):
            self.calls += 1
            raise failure()

    provider = Unavailable(lambda item: item["draft"])
    out = post(client(provider), "/api/recommendations", consent=True)
    baseline = post(client(), "/api/recommendations")
    assert provider.calls == 1 and out == baseline


@pytest.mark.parametrize("value", [None, True, 42, {}, [], "", "x" * 10000])
def test_malformed_provider_line_falls_back_through_the_endpoint(value):
    provider = Provider(lambda item: value)
    out = post(client(provider), "/api/recommendations", consent=True)
    baseline = post(client(), "/api/recommendations")
    assert provider.calls == 1 and out == baseline


@pytest.mark.parametrize(
    "draft", ["", " leading space", "trailing space ", "a\nb", "a\rb", "x" * 401]
)
def test_ineligible_drafts_have_no_provider_choices(draft):
    assert wording_choices(draft) == ()


def test_length_limit_keeps_whole_drafts_without_truncating_actions():
    draft = "x" * 395
    assert wording_choices(draft) == (draft,)
    assert grounded_line(draft, wording_choices(draft)) == draft
    assert grounded_line(draft + " There's no rush.", wording_choices(draft)) is None


def wellbeing_state(c, local_date="2026-10-24"):
    state = c.post("/api/checkin/start", json={"kind": "daily", "local_date": local_date}).json()[
        "state"
    ]
    for _ in range(10):
        if state["current_field"] == "wellbeing":
            return state
        state = c.post("/api/checkin/turn", json={"action": "skip", "state": state}).json()["state"]
    raise AssertionError("did not reach wellbeing")


@pytest.mark.parametrize("provider_name", ["muse", "claude"])
@pytest.mark.parametrize("attack", ATTACKS)
def test_care_endpoint_rejects_added_claims_even_when_full_safety_line_survives(
    provider_name, attack
):
    provider = Provider(lambda facts: attack + " " + facts["line"])
    provider.name = provider_name
    c = client(provider)
    state = wellbeing_state(c)
    body = {"action": "reply", "state": state, "text": "awful"}
    baseline = c.post("/api/checkin/turn", json=body).json()
    out = c.post(
        "/api/checkin/turn", json={**body, "outside_ai_consent": {provider_name: True}}
    ).json()
    assert provider.calls == 1
    # Only the provider status says the provider was asked; its wording was refused.
    assert (baseline["provider_status"], out["provider_status"]) == ("not_needed", "used")
    assert {**out, "provider_status": "not_needed"} == baseline
    assert out["message"].count("911") == 1


@pytest.mark.parametrize("provider_name", ["muse", "claude"])
@pytest.mark.parametrize("index", [0, 1])
@pytest.mark.parametrize(
    "local_date", ["2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"]
)
def test_care_endpoint_can_select_bounded_variants_without_changing_safety_or_state(
    provider_name, index, local_date
):
    selected = []

    def choose(facts):
        selected.append((facts["line"], facts["approved_wordings"][index]))
        return selected[-1][1]

    provider = Provider(choose)
    provider.name = provider_name
    c = client(provider)
    state = wellbeing_state(c, local_date)
    body = {"action": "reply", "state": state, "text": "awful"}
    baseline = c.post("/api/checkin/turn", json=body).json()
    out = c.post(
        "/api/checkin/turn", json={**body, "outside_ai_consent": {provider_name: True}}
    ).json()
    assert provider.calls == 1
    draft, canonical = selected[0]
    assert baseline["message"] == f"{draft} {CARE_QUESTION}"
    assert out["message"] == f"{canonical} {CARE_QUESTION}"
    assert draft.endswith(SAFETY_PHRASE) and canonical.endswith(draft)
    assert out["message"].count("911") == 1
    assert (baseline["provider_status"], out["provider_status"]) == ("not_needed", "used")
    same = {"message", "mascot_events", "provider_status"}
    assert {k: v for k, v in out.items() if k not in same} == {
        k: v for k, v in baseline.items() if k not in same
    }

"""Prompt shape for the AI helper: it must point at short spans, never rewrite."""

from typing import get_args

from lifetwin.onboarding.models import ProfileField
from lifetwin.onboarding.parsing import QUESTIONS
from lifetwin.onboarding.providers import QUOTE_RULES, _instructions


def test_every_field_prompt_carries_question_and_quote_rules():
    for field in get_args(ProfileField):
        text = _instructions(field)
        assert QUESTIONS[field] in text
        assert QUOTE_RULES in text


def test_quote_rules_teach_short_own_current_spans():
    rules = QUOTE_RULES.lower()
    assert "shortest span" in rules
    assert "character for character" in rules
    assert "never rewrite" in rules
    assert "own current value" in rules
    assert "empty candidates list" in rules

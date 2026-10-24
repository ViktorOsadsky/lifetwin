"""Load a reviewed bundled bank without runtime network or provider access."""

from functools import lru_cache
from importlib.resources import files

from lifetwin.quiz.models import QuizBankResponse


def parse_bank_json(raw: str) -> QuizBankResponse:
    """Reject malformed banks before any question can be scored by a client."""
    bank = QuizBankResponse.model_validate_json(raw)
    if not bank.questions or bank.total != len(bank.questions):
        raise ValueError("Bundled quiz bank must be nonempty and count every question")
    return bank


@lru_cache(maxsize=1)
def _bundled_bank() -> QuizBankResponse:
    raw = files("lifetwin.quiz").joinpath("content/questions.json").read_text(encoding="utf-8")
    return parse_bank_json(raw)


def load_bank() -> QuizBankResponse:
    """Return a copy so one caller cannot mutate future clients' questions."""
    return _bundled_bank().model_copy(deep=True)

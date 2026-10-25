"""Bound outside-AI copy to complete, server-authored wording choices.

A word/number denylist cannot establish the meaning of arbitrary prose. The
recommendation and question paths therefore accept only an exact choice derived
from their trusted draft, and publish that canonical string rather than provider
text. Facts, habit notes and provider replies never define additional choices.
This bounds provider edits; it does not certify the underlying draft clinically.
"""

from collections.abc import Sequence


def wording_choices(
    draft: str, *, question: bool = False, max_length: int = 400
) -> tuple[str, ...]:
    """Keep the whole trusted draft; vary only reviewed, neutral encouragement.

    Callers must pass the deterministic server draft, never arbitrary user or
    provider text. No synonym substitution, sentence removal or action change is
    allowed. Oversized/multiline drafts simply keep deterministic wording.
    """
    if not draft or draft != draft.strip() or "\n" in draft or "\r" in draft:
        return ()
    if question:
        candidates = (draft, f"Take your time. {draft}", f"When you're ready: {draft}")
    else:
        candidates = (draft, f"{draft} We can go at your pace.", f"{draft} There's no rush.")
    return tuple(text for text in candidates if len(text) <= max_length)


def grounded_line(
    line: object, trusted_choices: Sequence[str], *, max_length: int = 400
) -> str | None:
    """Return the matched canonical choice, or None for deterministic fallback.

    Only outer ASCII spaces may differ. Full-string equality rejects extra claims,
    reordered/mixed sentences, hidden controls, confusables and Unicode rewrites
    unless those exact characters already belong to the trusted server choice.
    Do not normalize, strip controls or fuzzy-match untrusted text into acceptance.
    """
    if not isinstance(line, str) or not line or len(line) > max_length:
        return None
    if isinstance(trusted_choices, str):
        return None  # a facts blob is not a list of approved lines
    candidate = line.strip(" ")
    return next((text for text in trusted_choices if candidate == text), None)


def safe_line(line: object, draft: str, *, question: bool = False, max_length: int = 400) -> bool:
    """Whether a line matches a bounded choice for this trusted server draft."""
    return (
        grounded_line(
            line,
            wording_choices(draft, question=question, max_length=max_length),
            max_length=max_length,
        )
        is not None
    )

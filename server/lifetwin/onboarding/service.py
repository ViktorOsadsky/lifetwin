"""Explicit candidate/confirmation transitions for text and final transcripts."""

import asyncio

from fastapi import HTTPException

from lifetwin.core.models import HealthProfile
from lifetwin.onboarding.models import (
    FIELDS,
    ConversationState,
    MascotEvent,
    TurnRequest,
    TurnResponse,
)
from lifetwin.onboarding.parsing import QUESTIONS, SKIP_WORDS, grounded_candidates, parse_reply
from lifetwin.onboarding.providers import ExtractionUnavailable, Extractor


class ConversationService:
    def __init__(self, extractor: Extractor | None = None, *, timeout_seconds: float = 6):
        self.extractor = extractor
        self.timeout = max(0.1, min(timeout_seconds, 10.0))

    async def turn(self, request: TurnRequest) -> TurnResponse:
        state = request.state.model_copy(deep=True)
        mode = "guided"
        configured = self.extractor is not None and self.extractor.configured
        provider_status = "not_needed" if configured else "not_configured"

        def respond(message: str) -> TurnResponse:
            reaction = {
                "idle": "idle",
                "asking": "asking",
                "confirming": "confirming",
                "ready": "celebrating",
                "cancelled": "idle",
            }[state.phase]
            return TurnResponse(
                state=state,
                message=message,
                guide_mode=mode,
                provider_status=provider_status,
                complete=state.phase == "ready",
                mascot_events=[MascotEvent(state=reaction, caption=message)],
            )

        if request.action == "cancel":
            # Clear drafts and supplied health data from the returned session.
            state = ConversationState(phase="cancelled")
            return respond(
                "We can stop here. Your conversation state is cleared. Come back whenever you like."
            )
        if request.action == "start":
            if state.phase in {"cancelled", "idle"}:
                state.pending_profile = HealthProfile()
                self._advance(state)
            return respond(
                "Hi, I'm your twin's guide! We can chat by text or a final voice transcript. "
                "You can skip any question, and I'll ask before saving answers in your profile. "
                + self._prompt(state)
            )
        if state.phase in {"idle", "cancelled"}:
            self._invalid("Start the conversation before sending another action.")
        if request.action == "confirm":
            if state.phase != "confirming":
                self._invalid("There are no pending answers to confirm.")
            additions = state.pending_profile.model_dump(exclude_none=True)
            merged = state.confirmed_profile.model_dump()
            merged.update(additions)
            state.confirmed_profile = HealthProfile.model_validate(merged)
            state.pending_profile = HealthProfile()
            state.skipped_fields = [
                field for field in state.skipped_fields if field not in additions
            ]
            self._advance(state)
            return respond("Confirmed! " + self._prompt(state))
        if request.action == "skip":
            target = request.field or state.current_field
            if target is None:
                self._invalid("Choose a field to skip.")
            if state.phase == "confirming":
                self._invalid("Confirm or correct pending answers before skipping a question.")
            if getattr(state.confirmed_profile, target) is not None:
                self._invalid("Skipping does not erase confirmed measurements.")
            if target not in state.skipped_fields:
                state.skipped_fields.append(target)
            self._advance(state)
            return respond("That's okay; I won't fill it in. " + self._prompt(state))
        if state.phase == "ready" and request.action != "correct":
            self._invalid(
                "The conversation is ready. Use correct with a field to change an answer."
            )
        if state.phase == "confirming" and request.action != "correct":
            self._invalid("Confirm or correct the pending answers first.")
        target = request.field or state.current_field
        if request.action == "correct" and state.phase == "confirming" and request.field is None:
            pending_fields = list(state.pending_profile.model_dump(exclude_none=True))
            if len(pending_fields) != 1:
                return respond(
                    "Several answers are pending. Choose the field you want to correct: "
                    + ", ".join(pending_fields)
                    + ". Nothing has changed."
                )
            target = pending_fields[0]
        if target is None:
            self._invalid("Choose the field you want to correct.")
        text = request.text.strip()
        normalized = text.lower().rstrip(".!?")
        if normalized in SKIP_WORDS and not (
            target == "smoking_status" and normalized == "unknown"
        ):
            if request.action == "correct":
                return respond(
                    "No value changed. You can give a new explicit answer or cancel. "
                    + self._prompt(state)
                )
            if target not in state.skipped_fields:
                state.skipped_fields.append(target)
            self._advance(state)
            return respond("I'll leave that unknown. " + self._prompt(state))
        candidates = parse_reply(text, target)
        if not candidates and configured:
            if request.provider_consent:
                try:
                    async with asyncio.timeout(self.timeout):
                        extraction = await self.extractor.extract(text, target)
                    candidates = grounded_candidates(text, extraction)
                    if not candidates:
                        raise ExtractionUnavailable()
                    mode, provider_status = "llm", "used"
                except (ExtractionUnavailable, TimeoutError):
                    provider_status = "unavailable"
            else:
                provider_status = "consent_required"
        if not candidates:
            notice = ""
            if provider_status == "consent_required":
                notice = (
                    "An optional AI provider could process this reply only with your permission. "
                )
            elif provider_status == "unavailable":
                notice = (
                    "The optional AI guide is unavailable; the guided conversation still works. "
                )
            return respond(
                notice
                + "I couldn't safely read that answer. Please give one clear value with units, "
                "choose a listed category, or skip. " + QUESTIONS[target]
            )
        if request.action == "correct" and request.field and request.field not in candidates:
            return respond(
                "Please give a correction for " + request.field + ". " + QUESTIONS[request.field]
            )
        # Corrections replace affected pending values; unrelated pending values stay visible.
        pending = state.pending_profile.model_dump(exclude_none=True)
        pending.update(candidates)
        state.pending_profile = HealthProfile.model_validate(pending)
        state.phase = "confirming"
        state.current_field = next(iter(pending)) if len(pending) == 1 else None
        return respond(self._prompt(state))

    @staticmethod
    def _advance(state: ConversationState) -> None:
        state.current_field = next(
            (
                field
                for field in FIELDS
                if getattr(state.confirmed_profile, field) is None
                and field not in state.skipped_fields
            ),
            None,
        )
        state.phase = "asking" if state.current_field else "ready"

    @staticmethod
    def _prompt(state: ConversationState) -> str:
        if state.phase == "confirming":
            summary = "; ".join(
                f"{field}: {value}"
                for field, value in state.pending_profile.model_dump(exclude_none=True).items()
            )
            return (
                "I heard "
                + summary
                + ". Metric fields use cm, kg, hours/night, minutes/week, drinks/week and mmHg. Confirm these answers, or tell me a correction."
            )
        if state.phase == "ready":
            return "Your confirmed answers are ready, with skipped answers left unknown. Prediction functionality will be added later. You can still correct a field."
        return QUESTIONS[state.current_field]

    @staticmethod
    def _invalid(message: str):
        raise HTTPException(
            status_code=409, detail={"code": "invalid_conversation_transition", "message": message}
        )

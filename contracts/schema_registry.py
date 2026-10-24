"""Shared schema registry; compare and sensitivity schemas intentionally contain no estimates.

Request schemas use pydantic's validation mode. Response schemas use serialization mode,
where every field the server always emits (including defaulted safety markers) is required.
"""

from lifetwin.advisor.models import AdvisorRequest, AdvisorResponse
from lifetwin.checkin.models import CheckinResponse, CheckinStartRequest, CheckinTurnRequest
from lifetwin.core.models import (
    ApiError,
    CompareRequest,
    DeferredFeature,
    HealthProfile,
    SensitivityRequest,
)
from lifetwin.documents.models import DocumentExtractRequest, DocumentExtractResponse
from lifetwin.onboarding.models import TurnRequest, TurnResponse
from lifetwin.prediction.models import PredictionResponse
from lifetwin.quiz.models import QuizBankResponse, QuizQuestion
from lifetwin.voice.models import VoiceTokenRequest, VoiceTokenResponse

REQUEST = "validation"
RESPONSE = "serialization"

SCHEMAS = {
    "profile.schema.json": (HealthProfile, REQUEST),
    "error.schema.json": (ApiError, RESPONSE),
    "prediction.request.schema.json": (HealthProfile, REQUEST),
    "prediction.schema.json": (PredictionResponse, RESPONSE),
    "compare.request.schema.json": (CompareRequest, REQUEST),
    "compare.schema.json": (DeferredFeature, RESPONSE),
    "sensitivity.request.schema.json": (SensitivityRequest, REQUEST),
    "sensitivity.schema.json": (DeferredFeature, RESPONSE),
    "conversation.request.schema.json": (TurnRequest, REQUEST),
    "conversation.schema.json": (TurnResponse, RESPONSE),
    "checkin.start.request.schema.json": (CheckinStartRequest, REQUEST),
    "checkin.turn.request.schema.json": (CheckinTurnRequest, REQUEST),
    "checkin.schema.json": (CheckinResponse, RESPONSE),
    "advisor.request.schema.json": (AdvisorRequest, REQUEST),
    "advisor.schema.json": (AdvisorResponse, RESPONSE),
    "quiz.schema.json": (QuizBankResponse, RESPONSE),
    "quiz.question.schema.json": (QuizQuestion, RESPONSE),
    "voice.token.request.schema.json": (VoiceTokenRequest, REQUEST),
    "voice.token.schema.json": (VoiceTokenResponse, RESPONSE),
    "documents.extract.request.schema.json": (DocumentExtractRequest, REQUEST),
    "documents.extract.schema.json": (DocumentExtractResponse, RESPONSE),
}

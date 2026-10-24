"""Shared schema registry; prediction schemas intentionally contain no estimates."""

from lifetwin.advisor.models import AdvisorRequest, AdvisorResponse
from lifetwin.core.models import (
    ApiError,
    CompareRequest,
    DeferredFeature,
    HealthProfile,
    SensitivityRequest,
)
from lifetwin.onboarding.models import TurnRequest, TurnResponse
from lifetwin.quiz.models import QuizBankResponse

SCHEMAS = {
    "profile.schema.json": HealthProfile,
    "error.schema.json": ApiError,
    "prediction.request.schema.json": HealthProfile,
    "prediction.schema.json": DeferredFeature,
    "compare.request.schema.json": CompareRequest,
    "compare.schema.json": DeferredFeature,
    "sensitivity.request.schema.json": SensitivityRequest,
    "sensitivity.schema.json": DeferredFeature,
    "conversation.request.schema.json": TurnRequest,
    "conversation.schema.json": TurnResponse,
    "advisor.request.schema.json": AdvisorRequest,
    "advisor.schema.json": AdvisorResponse,
    "quiz.schema.json": QuizBankResponse,
}

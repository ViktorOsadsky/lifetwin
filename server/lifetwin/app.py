"""Runnable LifeTwin backend; compare and sensitivity remain deferred."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from lifetwin.advisor import router as advisor_router
from lifetwin.change import ChangeService
from lifetwin.change import router as change_router
from lifetwin.checkin import CheckinService
from lifetwin.checkin import router as checkin_router
from lifetwin.core.config import Settings
from lifetwin.core.middleware import RequestBudgetMiddleware
from lifetwin.core.models import (
    BP_ORDER_MESSAGE,
    ApiError,
    CompareRequest,
    DeferredFeature,
    HealthProfile,
    SensitivityRequest,
)
from lifetwin.documents import DocumentService
from lifetwin.documents import router as documents_router
from lifetwin.onboarding import ChatCompletionsExtractor, ConversationService, OpenAIExtractor
from lifetwin.onboarding import router as onboarding_router
from lifetwin.onboarding.probes import MAX_PROBES
from lifetwin.personalize.providers import DISPLAY_NAMES, ClaudePersonalizer, MusePersonalizer
from lifetwin.prediction import load_model
from lifetwin.prediction.models import PredictionResponse
from lifetwin.quiz.router import router as quiz_router
from lifetwin.quiz.service import load_bank
from lifetwin.recommendations.router import router as recommendations_router
from lifetwin.research.tavily import TavilyResearch
from lifetwin.voice import VoiceService, voice_configured
from lifetwin.voice import router as voice_router

FIELD_WORDS = {
    "age": "age",
    "sex": "sex",
    "height_cm": "height",
    "weight_kg": "weight",
    "sleep_hours": "hours of sleep",
    "exercise_minutes_weekly": "weekly exercise minutes",
    "smoking_status": "smoking",
    "alcohol_drinks_weekly": "drinks per week",
    "diabetes": "diabetes",
    "systolic_bp": "top blood pressure number",
    "diastolic_bp": "bottom blood pressure number",
    "text": "your message",
    "limit": "number of questions",
    "question_id": "question",
    "voice_consent": "voice",
    "sleep_hours_last_night": "last night's sleep",
    "exercise_minutes_today": "today's exercise",
    "alcohol_drinks_yesterday": "yesterday's drinks",
    "wellbeing": "how you feel",
    "local_date": "date",
    "outside_ai_consent": "AI helper choice",
    "memory_consent": "memory",
}


def invalid_input_message(exc: RequestValidationError) -> str:
    errors = exc.errors()
    if any(list(error.get("loc", []))[-1:] == ["voice_consent"] for error in errors):
        return "Please agree to use your voice first."
    if any("pages" in list(error.get("loc", [])) for error in errors):
        return "That document has too many pages or too much text. Please choose up to 10 pages."
    if any(BP_ORDER_MESSAGE in str(error.get("msg", "")) for error in errors):
        return BP_ORDER_MESSAGE
    names = []
    for error in errors:
        word = FIELD_WORDS.get(str(error["loc"][-1])) if error.get("loc") else None
        if word and word not in names:
            names.append(word)
    if names:
        return f"Please check these answers: {', '.join(names)}. Then try again."
    return "Some answers do not look right. Please check them and try again."


def _described(statuses: dict[int, str]) -> dict:
    return {status: {"model": ApiError, "description": text} for status, text in statuses.items()}


# Only statuses a route can really return. COMMON_ERRORS come from the
# request-budget middleware and apply to every route.
COMMON_ERRORS = _described(
    {
        429: "Request or concurrency limit reached",
        500: "Redacted internal error",
        504: "Request deadline exceeded",
    }
)
BODY_ERRORS = _described({413: "Request body too large", 422: "Invalid request fields or values"})


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # Fail at startup if packaged educational content is invalid.
        load_bank()
        yield

    application = FastAPI(
        title="LifeTwin backend",
        version="0.1.0",
        description=(
            "Mascot intake, check-ins and changes, survival forecast, educational plans and quiz content. "
            "Compare and sensitivity are deferred."
        ),
        lifespan=lifespan,
        responses=COMMON_ERRORS,
    )
    application.state.settings = settings
    personalizer = (
        ClaudePersonalizer(
            api_key=settings.anthropic_api_key.get_secret_value(), model=settings.claude_model
        )
        if settings.personalize_provider == "claude"
        else MusePersonalizer(
            base_url=settings.llm_base_url,
            api_key=settings.llm_api_key.get_secret_value(),
            model=settings.llm_model,
            timeout_seconds=settings.provider_timeout_seconds,
            reasoning_effort=settings.llm_reasoning_effort,
        )
    )
    application.state.personalizer = personalizer
    application.state.conversation_service = ConversationService(
        extractor=(
            ChatCompletionsExtractor(
                base_url=settings.llm_endpoint,
                api_key=settings.llm_api_key.get_secret_value(),
                model=settings.llm_model,
                timeout_seconds=settings.provider_timeout_seconds,
                reasoning_effort=settings.llm_reasoning_effort,
            )
            if settings.llm_provider == "chat_completions"
            else OpenAIExtractor(
                api_key=settings.openai_api_key.get_secret_value(),
                model=settings.openai_model,
                timeout_seconds=settings.provider_timeout_seconds,
            )
        ),
        timeout_seconds=settings.provider_timeout_seconds,
        personalizer=personalizer,
        max_probes=1 if settings.onboarding_demo else MAX_PROBES,
    )
    # Documents: the deterministic parser always; Muse only when enabled, configured
    # (Chat Completions) and the person agreed in the request.
    conversation_extractor = application.state.conversation_service.extractor
    application.state.document_service = DocumentService(
        conversation_extractor if settings.llm_provider == "chat_completions" else None,
        muse_enabled=settings.document_muse_enabled,
        timeout_seconds=settings.provider_timeout_seconds,
    )
    # Check-ins are guided only and stateless: the caller sends the previous answers.
    application.state.checkin_service = CheckinService()
    # Changing a saved answer is a stateless talk with Mochi: the caller sends the profile.
    application.state.change_service = ChangeService()
    application.state.research_client = TavilyResearch(
        api_key=settings.tavily_api_key.get_secret_value(),
        timeout_seconds=settings.provider_timeout_seconds,
    )

    application.state.voice_service = VoiceService(settings)
    # Loaded once at startup; None when the artifact files are missing (route stays 501).
    survival_model = load_model(settings.model_artifact_path)
    application.state.survival_model = survival_model
    prediction_state = "available" if survival_model else "not_implemented"

    @application.exception_handler(RequestValidationError)
    async def invalid_input(request: Request, exc: RequestValidationError):
        # Pydantic's default error includes raw input; deliberately omit it.
        return JSONResponse(
            status_code=422,
            content=ApiError(
                code="invalid_request",
                message=invalid_input_message(exc),
                request_id=getattr(request.state, "request_id", None),
            ).model_dump(),
        )

    @application.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        code = "not_found" if exc.status_code == 404 else "request_rejected"
        message = (
            "We could not find that. Please go back and try again."
            if exc.status_code == 404
            else "We could not do that. Please go back and try again."
        )
        if isinstance(exc.detail, dict):
            try:
                known = ApiError.model_validate(exc.detail)
                code, message = known.code, known.message
            except ValueError:
                pass
        return JSONResponse(
            status_code=exc.status_code,
            headers=exc.headers,
            content=ApiError(
                code=code,
                message=message,
                request_id=getattr(request.state, "request_id", None),
            ).model_dump(),
        )

    @application.get("/health", tags=["service"])
    async def health():
        return {"status": "ok", "service": "lifetwin-backend"}

    @application.get("/ready", tags=["service"])
    async def ready():
        return {"status": "ready", "prediction": prediction_state, "voice": "deferred"}

    @application.get("/api/capabilities", tags=["service"])
    async def capabilities():
        return {
            "schema_version": "1.0",
            "intake": "guided",
            "llm_configured": settings.llm_configured,
            "web_research_configured": bool(settings.tavily_api_key.get_secret_value().strip()),
            "advisor": "curated_educational",
            "quiz": "local_scoring_content",
            "prediction": prediction_state,
            "voice": "available" if voice_configured(settings) else "unavailable",
            "health_data_storage": "none",
            "documents": "text_extraction",
            # The app's consent text names this provider; consent is per provider.
            "personalize": {
                "provider": personalizer.name,
                "display_name": DISPLAY_NAMES[personalizer.name],
                "configured": personalizer.configured,
            },
        }

    @application.post(
        "/api/predict",
        response_model=PredictionResponse,
        tags=["prediction"],
        responses={
            **BODY_ERRORS,
            501: {"model": DeferredFeature, "description": "Model files are not installed"},
        },
    )
    def predict(profile: HealthProfile):
        # Never log the profile. Unsupported profiles get a plain reason, not a number.
        if survival_model is None:
            return JSONResponse(status_code=501, content=DeferredFeature().model_dump())
        return survival_model.predict(profile)

    # Only route shells and input boundaries: no model, math or mock results.

    @application.post(
        "/api/compare",
        response_model=DeferredFeature,
        status_code=501,
        tags=["deferred"],
        responses=BODY_ERRORS,
    )
    async def compare(profiles: CompareRequest):
        return DeferredFeature()

    @application.post(
        "/api/sensitivity",
        response_model=DeferredFeature,
        status_code=501,
        tags=["deferred"],
        responses=BODY_ERRORS,
    )
    async def sensitivity(payload: SensitivityRequest):
        return DeferredFeature()

    application.include_router(
        onboarding_router,
        prefix="/api",
        responses={**BODY_ERRORS, **_described({409: "Invalid conversation transition"})},
    )
    application.include_router(
        checkin_router,
        prefix="/api",
        responses={**BODY_ERRORS, **_described({409: "Invalid check-in transition"})},
    )
    application.include_router(
        change_router,
        prefix="/api",
        responses={**BODY_ERRORS, **_described({409: "Invalid change transition"})},
    )
    application.include_router(advisor_router, prefix="/api", responses=BODY_ERRORS)
    application.include_router(documents_router, prefix="/api", responses=BODY_ERRORS)
    application.include_router(recommendations_router, prefix="/api", responses=BODY_ERRORS)
    application.include_router(
        quiz_router,
        prefix="/api",
        responses=_described({404: "Quiz question not found", 422: "Invalid request values"}),
    )
    application.include_router(
        voice_router,
        prefix="/api",
        responses={
            **BODY_ERRORS,
            **_described({503: "Voice is unavailable; the app can continue by typing"}),
        },
    )
    application.add_middleware(RequestBudgetMiddleware, settings=settings)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
        allow_credentials=False,
        expose_headers=["X-Request-ID"],
    )
    return application


app = create_app()

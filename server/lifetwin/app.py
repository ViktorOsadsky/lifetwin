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
from lifetwin.coach import DailyCap
from lifetwin.coach import router as coach_router
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
from lifetwin.documents.models import MAX_PDF_BYTES, MAX_PDF_PAGES
from lifetwin.documents.pdf import ClaudeDocumentReader
from lifetwin.onboarding import (
    AnthropicExtractor,
    ChatCompletionsExtractor,
    ConversationService,
    OpenAIExtractor,
)
from lifetwin.onboarding import router as onboarding_router
from lifetwin.onboarding.probes import MAX_PROBES
from lifetwin.personalize.providers import (
    COMPANIES,
    DISPLAY_NAMES,
    ClaudePersonalizer,
    MusePersonalizer,
)
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


# Pydantic error types for a list or string over its maximum length.
TOO_LONG = {"too_long", "string_too_long"}


def invalid_input_message(exc: RequestValidationError) -> str:
    errors = exc.errors()
    if any(list(error.get("loc", []))[-1:] == ["voice_consent"] for error in errors):
        return "Please agree to use your voice first."

    def about(field: str, too_long: bool) -> bool:
        return any(
            field in list(error.get("loc", [])) and (error.get("type") in TOO_LONG) == too_long
            for error in errors
        )

    if about("pages", too_long=True):
        return "That document has too many pages or too much text. Please choose up to 10 pages."
    if about("pdf_base64", too_long=True):
        return (
            "That PDF is too big to send. Please choose one under 10 MB, or read it on this phone."
        )
    if about("pages", too_long=False):
        return "We could not find any text to read. Please choose a document with text in it."
    if about("pdf_base64", too_long=False):
        return "We could not read that file as a PDF. Please choose a PDF and try again."
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
            api_key=settings.anthropic_api_key.get_secret_value(),
            model=settings.claude_model,
            timeout_seconds=min(6, settings.provider_timeout_seconds),
        )
        if settings.personalize_provider == "claude"
        else MusePersonalizer(
            base_url=settings.llm_base_url,
            api_key=settings.llm_api_key.get_secret_value(),
            model=settings.llm_model,
            timeout_seconds=settings.provider_timeout_seconds,
            reasoning_effort=settings.llm_reasoning_effort,
            allow_contributor=settings.llm_allow_contributor,
        )
    )
    application.state.personalizer = personalizer
    claude_key = settings.anthropic_api_key.get_secret_value()
    voice_timeout = min(6, settings.provider_timeout_seconds)
    # The AI helper per LLM_PROVIDER: recognised document text, and conversation turns
    # when CONVERSATION_PROVIDER is "muse".
    shared_extractor = (
        AnthropicExtractor(
            api_key=claude_key, model=settings.claude_model, timeout_seconds=voice_timeout
        )
        if settings.llm_provider == "anthropic"
        else ChatCompletionsExtractor(
            base_url=settings.llm_endpoint,
            api_key=settings.llm_api_key.get_secret_value(),
            model=settings.llm_model,
            timeout_seconds=settings.provider_timeout_seconds,
            reasoning_effort=settings.llm_reasoning_effort,
            allow_contributor=settings.llm_allow_contributor,
        )
        if settings.llm_provider == "chat_completions"
        else OpenAIExtractor(
            api_key=settings.openai_api_key.get_secret_value(),
            model=settings.openai_model,
            timeout_seconds=settings.provider_timeout_seconds,
        )
    )
    # Owner ruling (2026-10-25): every model call made while Mochi listens (onboarding,
    # check-in and change turns) goes to Claude when CONVERSATION_PROVIDER is "claude", and
    # only with the person's yes for Claude; without it the rules answer, never Muse.
    # Ideas, coach and recommendations keep the shared personalizer above.
    if settings.conversation_provider == "claude":
        conversation_extractor = AnthropicExtractor(
            api_key=claude_key, model=settings.claude_model, timeout_seconds=voice_timeout
        )
        conversation_personalizer = ClaudePersonalizer(
            api_key=claude_key, model=settings.claude_model, timeout_seconds=voice_timeout
        )
    elif settings.conversation_provider == "muse":
        conversation_extractor, conversation_personalizer = shared_extractor, personalizer
    else:
        conversation_extractor, conversation_personalizer = None, None
    application.state.conversation_personalizer = conversation_personalizer
    # The provider a conversation turn may reach: "muse" also covers the OpenAI extractor.
    conversation_name = (
        None
        if conversation_extractor is None
        else getattr(conversation_extractor, "provider", None)
        or (conversation_personalizer.name if conversation_personalizer else None)
    )
    application.state.conversation_service = ConversationService(
        extractor=conversation_extractor,
        timeout_seconds=settings.provider_timeout_seconds,
        personalizer=conversation_personalizer,
        max_probes=1 if settings.onboarding_demo else MAX_PROBES,
    )
    # Documents: the deterministic parser always; the selected outside AI (Muse over Chat
    # Completions, or Claude) only when enabled, configured and the person agreed for
    # that provider in the request. It reads the words only, never the photo.
    # A whole PDF goes to Claude only with DOCUMENT_PROVIDER=claude and the person's yes for
    # that document (POST /api/documents/read); otherwise the phone reads it.
    pdf_reader = (
        ClaudeDocumentReader(
            api_key=settings.anthropic_api_key.get_secret_value(),
            model=settings.claude_model,
            timeout_seconds=settings.document_read_timeout_seconds,
        )
        if settings.document_provider == "claude"
        else None
    )
    application.state.document_service = DocumentService(
        shared_extractor
        if settings.llm_provider in {"chat_completions", "anthropic"}
        and settings.document_provider != "local"
        else None,
        muse_enabled=settings.document_muse_enabled,
        timeout_seconds=settings.provider_timeout_seconds,
        pdf_reader=pdf_reader,
    )
    # Check-ins are guided only and stateless: the caller sends the previous answers.
    # The care reply may be reworded by the conversation provider, only with consent for it.
    application.state.checkin_service = CheckinService(
        personalizer=conversation_personalizer, timeout_seconds=voice_timeout
    )
    # Changing a saved answer is a stateless talk with Mochi: the caller sends the profile.
    # It calls no model today; if it ever does, it takes the conversation provider.
    application.state.change_service = ChangeService()
    application.state.research_client = TavilyResearch(
        api_key=settings.tavily_api_key.get_secret_value(),
        timeout_seconds=settings.provider_timeout_seconds,
    )

    application.state.voice_service = VoiceService(settings)
    # Coach: deterministic plans; the shared personalizer may reword them only with the person's consent.
    application.state.coach_phraser = personalizer
    application.state.coach_cap = DailyCap(settings.coach_llm_daily_cap)
    application.state.coach_timeout = settings.coach_llm_timeout_seconds
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
            # Recognised text always works. "pdf": who may read a whole PDF, by name, for the
            # app's per-document consent sheet; configured false: PDFs are read on the phone.
            "documents": {
                "text_extraction": True,
                "pdf": {
                    "provider": settings.document_provider,
                    "display_name": DISPLAY_NAMES.get(settings.document_provider),
                    "company": COMPANIES.get(settings.document_provider),
                    "configured": bool(pdf_reader and pdf_reader.configured),
                    "endpoint": "/api/documents/read",
                    "max_bytes": MAX_PDF_BYTES,
                    "max_pages": MAX_PDF_PAGES,
                },
            },
            # Who reads and words onboarding, check-in and change turns (the AI helper). The
            # app names it beside the AI helper switch and sends outside_ai_consent
            # {provider: true} with conversation turns only after a yes for it.
            "conversation": {
                "provider": conversation_name,
                "display_name": DISPLAY_NAMES.get(conversation_name),
                "company": COMPANIES.get(conversation_name),
                "configured": bool(
                    conversation_extractor is not None and conversation_extractor.configured
                ),
                "may_train_on_content": bool(
                    conversation_personalizer is not None
                    and conversation_personalizer.may_train_on_content
                ),
                "routes": ["/api/onboarding/turn", "/api/checkin/turn", "/api/change/turn"],
            },
            # The app's consent text names this provider; consent is per provider.
            "personalize": {
                "provider": personalizer.name,
                "display_name": DISPLAY_NAMES[personalizer.name],
                "company": COMPANIES[personalizer.name],
                "configured": personalizer.configured,
                "may_train_on_content": personalizer.may_train_on_content,
            },
            "coach": {
                "endpoint": "/api/coach/plan",
                "planner": "deterministic_catalog",
                "runs": "on_app_open_or_resume",
                "personalize": {
                    "provider": personalizer.name,
                    "display_name": DISPLAY_NAMES[personalizer.name],
                    "company": COMPANIES[personalizer.name],
                    "configured": personalizer.configured,
                    "may_train_on_content": personalizer.may_train_on_content,
                    "daily_cap_per_client": settings.coach_llm_daily_cap,
                },
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
        coach_router,
        prefix="/api",
        responses={
            **BODY_ERRORS,
            **_described({409: "Feedback for a plan that is not the latest"}),
        },
    )
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

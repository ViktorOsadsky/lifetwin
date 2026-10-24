"""Runnable LifeTwin backend; all prediction implementation remains deferred."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from lifetwin.advisor import router as advisor_router
from lifetwin.core.config import Settings
from lifetwin.core.middleware import RequestBudgetMiddleware
from lifetwin.core.models import (
    ApiError,
    CompareRequest,
    DeferredFeature,
    HealthProfile,
    SensitivityRequest,
)
from lifetwin.onboarding import ConversationService, OpenAIExtractor
from lifetwin.onboarding import router as onboarding_router
from lifetwin.quiz.router import router as quiz_router
from lifetwin.quiz.service import load_bank
from lifetwin.research.tavily import TavilyResearch


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
        description="Mascot intake, educational plans and quiz content. Prediction is deferred.",
        lifespan=lifespan,
    )
    application.state.settings = settings
    application.state.conversation_service = ConversationService(
        extractor=OpenAIExtractor(
            api_key=settings.openai_api_key.get_secret_value(),
            model=settings.openai_model,
            timeout_seconds=settings.provider_timeout_seconds,
        )
    )
    application.state.research_client = TavilyResearch(
        api_key=settings.tavily_api_key.get_secret_value(),
        timeout_seconds=settings.provider_timeout_seconds,
    )

    @application.exception_handler(RequestValidationError)
    async def invalid_input(request: Request, exc: RequestValidationError):
        # Pydantic's default error includes raw input; deliberately omit it.
        return JSONResponse(
            status_code=422,
            content=ApiError(
                code="invalid_request",
                message="Request fields or values are invalid.",
                request_id=getattr(request.state, "request_id", None),
            ).model_dump(),
        )

    @application.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        code = "not_found" if exc.status_code == 404 else "request_rejected"
        message = "Resource not found." if exc.status_code == 404 else "The request was rejected."
        if isinstance(exc.detail, dict):
            try:
                known = ApiError.model_validate(exc.detail)
                code, message = known.code, known.message
            except ValueError:
                pass
        return JSONResponse(
            status_code=exc.status_code,
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
        return {"status": "ready", "prediction": "not_implemented", "voice": "deferred"}

    @application.get("/api/capabilities", tags=["service"])
    async def capabilities():
        return {
            "schema_version": "1.0",
            "intake": "guided",
            "llm_configured": bool(
                settings.openai_api_key.get_secret_value().strip() and settings.openai_model.strip()
            ),
            "web_research_configured": bool(settings.tavily_api_key.get_secret_value().strip()),
            "advisor": "curated_educational",
            "quiz": "local_scoring_content",
            "prediction": "not_implemented",
            "voice": "deferred",
            "health_data_storage": "none",
        }

    # Only route shells and input boundaries: no model, math or mock results.
    @application.post(
        "/api/predict", response_model=DeferredFeature, status_code=501, tags=["deferred"]
    )
    async def predict(profile: HealthProfile):
        return DeferredFeature()

    @application.post(
        "/api/compare", response_model=DeferredFeature, status_code=501, tags=["deferred"]
    )
    async def compare(profiles: CompareRequest):
        return DeferredFeature()

    @application.post(
        "/api/sensitivity", response_model=DeferredFeature, status_code=501, tags=["deferred"]
    )
    async def sensitivity(payload: SensitivityRequest):
        return DeferredFeature()

    application.include_router(onboarding_router, prefix="/api")
    application.include_router(advisor_router, prefix="/api")
    application.include_router(quiz_router, prefix="/api")
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

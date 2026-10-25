"""Health-document extraction: recognised text in, candidates to confirm out. Stateless."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from lifetwin.core.models import ApiError
from lifetwin.documents import pdf
from lifetwin.documents.models import (
    DocumentExtractRequest,
    DocumentExtractResponse,
    DocumentReadRequest,
)
from lifetwin.documents.service import DocumentService

logger = logging.getLogger(__name__)
router = APIRouter(tags=["documents"])
_parser_only = DocumentService()


def get_service(request: Request) -> DocumentService:
    return getattr(request.app.state, "document_service", _parser_only)


@router.post("/documents/extract", response_model=DocumentExtractResponse)
async def extract(
    payload: DocumentExtractRequest,
    service: Annotated[DocumentService, Depends(get_service)],
) -> DocumentExtractResponse:
    # Never log the payload: it is the text of a health document.
    return await service.extract(payload)


@router.post("/documents/read", response_model=DocumentExtractResponse)
async def read(
    payload: DocumentReadRequest,
    service: Annotated[DocumentService, Depends(get_service)],
) -> DocumentExtractResponse:
    """A whole PDF, read by the documents provider only with the person's yes for it.

    Same response as /documents/extract. consent_required or unavailable: the phone reads
    the PDF itself instead. Never log the payload, quotes or values: counts only.
    """
    try:
        response, stats = await pdf.read_pdf(payload, service.pdf_reader)
    except pdf.PdfRejected as exc:
        raise HTTPException(
            status_code=exc.status,
            detail=ApiError(code=exc.code, message=exc.message).model_dump(),
        ) from None
    if response.provider_status == "used":
        logger.info(
            "documents read: returned=%d kept=%d dropped=%d "
            "(quote_not_found=%d value_mismatch=%d other_person=%d) text_layer=%s",
            stats.returned,
            stats.kept,
            stats.dropped,
            stats.quote_not_found,
            stats.value_mismatch,
            stats.other_person,
            stats.text_layer,
        )
    return response


__all__ = [
    "DocumentExtractRequest",
    "DocumentExtractResponse",
    "DocumentReadRequest",
    "DocumentService",
    "router",
]

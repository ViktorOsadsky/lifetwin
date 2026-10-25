"""Health-document extraction: recognised text in, candidates to confirm out. Stateless."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from lifetwin.documents.models import DocumentExtractRequest, DocumentExtractResponse
from lifetwin.documents.service import DocumentService

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


__all__ = ["DocumentExtractRequest", "DocumentExtractResponse", "DocumentService", "router"]

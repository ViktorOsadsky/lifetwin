"""Bounded research contracts; no free-text health query or client URL input."""

from typing import Literal

from pydantic import Field

from lifetwin.core.models import ApiModel

ResearchTopic = Literal["physical_activity", "sleep", "nutrition", "smoking", "supplements"]


class EvidenceSource(ApiModel):
    id: str
    topic: ResearchTopic
    title: str
    url: str
    publisher: str
    reviewed_on: Literal["2026-10-23"] = "2026-10-23"


class ResearchResult(ApiModel):
    status: Literal["not_requested", "unconfigured", "retrieved", "partial", "unavailable"]
    sources: list[EvidenceSource] = Field(default_factory=list, max_length=5)
    retrieved_source_ids: list[str] = Field(default_factory=list, max_length=5)
    query_count: int = Field(default=0, ge=0, le=3)
    page_count: int = Field(default=0, ge=0, le=5)
    limitation: str

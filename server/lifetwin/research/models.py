"""Bounded research contracts; no free-text health query or client URL input."""

from typing import Literal

from pydantic import Field, model_validator

from lifetwin.core.models import ApiModel

ResearchTopic = Literal["physical_activity", "sleep", "nutrition", "smoking", "supplements"]
ResearchStatus = Literal["not_requested", "unconfigured", "retrieved", "partial", "unavailable"]


class EvidenceSource(ApiModel):
    id: str
    topic: ResearchTopic
    title: str
    url: str
    publisher: str
    reviewed_on: Literal["2026-10-23"] = "2026-10-23"


class ResearchResult(ApiModel):
    status: ResearchStatus
    sources: list[EvidenceSource] = Field(default_factory=list, max_length=5)
    retrieved_source_ids: list[str] = Field(default_factory=list, max_length=5)
    query_count: int = Field(default=0, ge=0, le=3)
    page_count: int = Field(default=0, ge=0, le=5)
    limitation: str

    @model_validator(mode="after")
    def coherent_retrieval(self) -> "ResearchResult":
        source_ids = {source.id for source in self.sources}
        retrieved = set(self.retrieved_source_ids)
        if len(retrieved) != len(self.retrieved_source_ids) or not retrieved <= source_ids:
            raise ValueError("Retrieved IDs must name supplied sources once each.")
        if self.status == "retrieved":
            coherent = bool(retrieved) and retrieved == source_ids
        elif self.status == "partial":
            coherent = bool(retrieved) and retrieved < source_ids
        else:
            coherent = not retrieved
        if not coherent:
            raise ValueError("Research status must match the retrieved sources.")
        return self

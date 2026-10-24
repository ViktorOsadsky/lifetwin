"""Non-predictive educational advisor boundary."""

from typing import Literal

from pydantic import Field, field_validator, model_validator

from lifetwin.core.models import ApiModel, HealthProfile
from lifetwin.research.models import EvidenceSource, ResearchResult, ResearchTopic


class AdvisorRequest(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    profile: HealthProfile | None = None
    topics: list[ResearchTopic] = Field(
        default_factory=lambda: ["physical_activity", "sleep", "nutrition"],
        min_length=1,
        max_length=3,
    )
    use_web_research: bool = False

    @field_validator("topics")
    @classmethod
    def distinct_topics(cls, topics: list[ResearchTopic]) -> list[ResearchTopic]:
        if len(set(topics)) != len(topics):
            raise ValueError("Select each topic only once.")
        return topics


class PlanAction(ApiModel):
    id: str
    topic: ResearchTopic
    title: str
    next_step: str
    evidence_summary: str
    source_ids: list[str] = Field(min_length=1, max_length=5)
    evidence_kind: Literal["public_health_guidance"] = "public_health_guidance"
    modeled_effect_status: Literal["unmodeled"] = "unmodeled"
    modeled_effect: None = None
    experiment_assumptions: None = None
    optional: bool = True


class AdvisorResponse(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    status: Literal["educational"] = "educational"
    mode: Literal["curated_educational"] = "curated_educational"
    mascot_message: str
    actions: list[PlanAction] = Field(min_length=1, max_length=3)
    sources: list[EvidenceSource] = Field(min_length=1, max_length=5)
    research: ResearchResult
    limitations: list[str]

    @model_validator(mode="after")
    def cited_actions(self) -> "AdvisorResponse":
        source_ids = {source.id for source in self.sources}
        if any(not set(action.source_ids) <= source_ids for action in self.actions):
            raise ValueError("Every action must cite a supplied evidence source.")
        return self

"""Reviewed quiz contracts; every effect is cosmetic game state only."""

from datetime import date
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import Field, field_validator, model_validator

from lifetwin.core.models import ApiModel

QuizTopic = Literal["nutrition", "food_safety", "activity"]
QuizDifficulty = Literal["moderate", "challenging"]
QuestionId = Annotated[str, Field(pattern=r"^[a-z][a-z0-9-]{2,60}\.v[1-9][0-9]{0,2}$")]


class QuizOption(ApiModel):
    id: str = Field(pattern=r"^[a-d]$")
    text: str = Field(min_length=1, max_length=400)


class QuizSource(ApiModel):
    title: str = Field(min_length=1, max_length=200)
    publisher: Literal["CDC", "FDA"]
    url: str = Field(min_length=1, max_length=500)
    accessed_on: date

    @field_validator("url")
    @classmethod
    def official_source(cls, value: str) -> str:
        parsed = urlsplit(value)
        if (
            parsed.scheme != "https"
            or parsed.hostname not in {"www.cdc.gov", "www.fda.gov"}
            or parsed.username
            or parsed.password
            or parsed.port not in {None, 443}
            or parsed.query
            or parsed.fragment
            or not parsed.path.startswith("/")
        ):
            raise ValueError("Quiz citations must be canonical CDC or FDA HTTPS pages")
        return value

    @model_validator(mode="after")
    def publisher_matches_url(self) -> "QuizSource":
        expected_host = {"CDC": "www.cdc.gov", "FDA": "www.fda.gov"}[self.publisher]
        if urlsplit(self.url).hostname != expected_host:
            raise ValueError("Citation publisher must match its URL")
        return self


class GameEffect(ApiModel):
    game_health_delta: int = Field(ge=-10, le=10)
    mascot_event: Literal["quiz_sick", "quiz_recovering"]
    reduced_motion_text: str = Field(min_length=1, max_length=180)

    @model_validator(mode="after")
    def reaction_matches_delta(self) -> "GameEffect":
        if self.game_health_delta == 0:
            raise ValueError("Scored effects must change game health")
        if (self.game_health_delta < 0) != (self.mascot_event == "quiz_sick"):
            raise ValueError("Reaction must match game-health direction")
        return self


class QuizQuestion(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    id: QuestionId
    topic: QuizTopic
    difficulty: QuizDifficulty
    scenario: str = Field(min_length=20, max_length=1000)
    options: list[QuizOption] = Field(min_length=3, max_length=4)
    correct_option_id: str = Field(pattern=r"^[a-d]$")
    explanation: str = Field(min_length=20, max_length=1200)
    sources: list[QuizSource] = Field(min_length=1, max_length=4)
    review_status: Literal["reviewed"]
    reviewed_on: date
    wrong_effect: GameEffect
    correct_effect: GameEffect
    review_effect: GameEffect

    @model_validator(mode="after")
    def coherent_question(self) -> "QuizQuestion":
        ids = [option.id for option in self.options]
        texts = [option.text.strip().casefold() for option in self.options]
        if len(ids) != len(set(ids)) or len(texts) != len(set(texts)):
            raise ValueError("Question option IDs and texts must be unique")
        if self.correct_option_id not in ids:
            raise ValueError("Correct option must exist")
        if len({source.url for source in self.sources}) != len(self.sources):
            raise ValueError("Question citations must be unique")
        if self.wrong_effect.game_health_delta >= 0:
            raise ValueError("Wrong answers decrement game health")
        if min(self.correct_effect.game_health_delta, self.review_effect.game_health_delta) <= 0:
            raise ValueError("Correct answers and review must allow recovery")
        if self.review_effect.game_health_delta < -self.wrong_effect.game_health_delta:
            raise ValueError("Review must provide a complete penalty recovery route")
        if any(source.accessed_on > self.reviewed_on for source in self.sources):
            raise ValueError("Content review must follow source access")
        return self


class LocalScoringRules(ApiModel):
    state_scope: Literal["game_health_only"] = "game_health_only"
    minimum_game_health: Literal[0] = 0
    maximum_game_health: Literal[100] = 100
    initial_game_health: Literal[100] = 100
    clamp_after_each_effect: Literal[True] = True
    score_once_per_question_version: Literal[True] = True
    review_once_after_wrong_answer: Literal[True] = True
    retry_after_review_is_unscored: Literal[True] = True
    network_failure_is_unscored: Literal[True] = True
    affects_confirmed_profile: Literal[False] = False
    affects_prediction: Literal[False] = False
    answer_metadata: Literal["included_for_local_offline_scoring"] = (
        "included_for_local_offline_scoring"
    )
    label: Literal["Game health"] = "Game health"


class QuizBankResponse(ApiModel):
    schema_version: Literal["1.0"] = "1.0"
    bank_version: str = Field(pattern=r"^[1-9][0-9]*\.[0-9]+$")
    local_scoring: LocalScoringRules = Field(default_factory=LocalScoringRules)
    total: int = Field(ge=0, le=100)
    questions: list[QuizQuestion] = Field(max_length=100)

    @model_validator(mode="after")
    def coherent_bank(self) -> "QuizBankResponse":
        ids = [question.id for question in self.questions]
        if len(ids) != len(set(ids)):
            raise ValueError("Question IDs must be unique")
        if self.total < len(self.questions):
            raise ValueError("Total must count at least the returned questions")
        return self

"""Export reviewed educational content/regexes for the Supabase implementation.

No request, profile, provider key or fixture response is included. Run from the
locked server development environment after changing the reviewed source catalog.
"""

import argparse
import asyncio
import json
import re
from dataclasses import asdict
from pathlib import Path

# Initialize onboarding's models before the coach package. DocumentContext is
# shared by recommendations, whose package initialization also loads onboarding.
from lifetwin.onboarding.intents import EMERGENCY, EMERGENCY_MESSAGE, SELF_HARM

# isort: split

from lifetwin.advisor.models import AdvisorRequest
from lifetwin.advisor.service import _COPY, build_plan
from lifetwin.coach import catalog, safety
from lifetwin.documents import parser, redact
from lifetwin.documents.service import _ENGLISH, _FOREIGN
from lifetwin.quiz.service import load_bank
from lifetwin.recommendations import ideas, levers
from lifetwin.recommendations.models import RecommendationResponse
from lifetwin.recommendations.service import SOURCES
from lifetwin.research.tavily import LIMITATIONS

DESTINATION = (
    Path(__file__).resolve().parents[1] / "supabase/functions/lifetwin-api/wellness-content.json"
)


def patterns(module):
    return {
        name: {"source": value.pattern, "flags": "i" if value.flags & re.I else ""}
        for name, value in vars(module).items()
        if isinstance(value, re.Pattern)
    }


async def main(argv: list[str] | None = None) -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--check", action="store_true", help="Fail if the saved export is stale")
    args = cli.parse_args(argv)
    advisor = (await build_plan(AdvisorRequest())).model_dump(mode="json")
    content = {
        "provenance": "Reviewed Python source catalogs; scripts/export_edge_wellness.py",
        "quiz": load_bank().model_dump(mode="json"),
        "advisor": {
            "copy": _COPY,
            "sources": {
                k: v.model_dump(mode="json")
                for k, v in __import__(
                    "lifetwin.research.sources", fromlist=["SOURCES"]
                ).SOURCES.items()
            },
            "message": advisor["mascot_message"],
            "limitations": advisor["limitations"],
            "research_limitations": LIMITATIONS,
        },
        "ideas": [
            {**asdict(idea), "card": idea.card, "source": idea.source} for idea in ideas.IDEAS
        ],
        "recommendations": {
            "sources": SOURCES,
            "lever_order": levers.LEVER_ORDER,
            "lever_field": levers.LEVER_FIELD,
            "model_version": levers.MODEL_VERSION,
            "medians": levers.MEDIAN_PP,
            "thresholds": levers.EFFECT_THRESHOLDS_PP,
            "limitations": RecommendationResponse.model_fields["limitations"].default_factory(),
            "limits": {k: v.pattern for k, v in ideas.NOTE_LIMITS.items()},
            "interests": {k: v.pattern for k, v in ideas.INTEREST_PATTERNS.items()},
            "times": {k: v.pattern for k, v in ideas.TIME_WORDS.items()},
        },
        "coach": {
            "activities": {k: asdict(v) for k, v in catalog.ACTIVITIES.items()},
            "diets": {k: asdict(v) for k, v in catalog.DIET.items()},
            "habits": {k: asdict(v) for k, v in catalog.HABITS.items()},
            "replies": {k: v for k, v in vars(catalog).items() if k.endswith("_REPLY")},
            "emergency_message": EMERGENCY_MESSAGE,
            "emergency_patterns": [EMERGENCY.pattern, SELF_HARM.pattern],
            "safety": patterns(safety),
        },
        "documents": {
            "patterns": patterns(parser),
            "redaction": patterns(redact),
            "patient_sections": sorted(parser._PATIENT_SECTIONS),
            "diagnosis_sections": sorted(parser._DIAGNOSIS_SECTIONS),
            "date_labels": parser._DOC_DATE_LABELS,
            "field_order": parser._FIELD_ORDER,
            "model_inputs": sorted(parser.MODEL_INPUTS),
            "redact_name_labels": redact._NAME_LABELS,
            "redact_people_labels": redact._PEOPLE_LABELS,
            "redact_id_labels": redact._ID_LABELS,
            "redact_inline": [
                {"source": p.pattern, "flags": "i" if p.flags & re.I else ""}
                for p in redact._INLINE
            ],
            "common_name_words": sorted(redact._COMMON_WORDS),
            "english_words": sorted(_ENGLISH),
            "foreign_words": sorted(_FOREIGN),
        },
    }
    # Normalize authored tuples to the JSON arrays consumed by Deno. Checking is
    # semantic so formatting the generated asset never creates false drift.
    content = json.loads(json.dumps(content, ensure_ascii=False))
    if args.check:
        try:
            current = json.loads(DESTINATION.read_text())
        except (OSError, ValueError):
            print("Wellness export is missing or invalid; regenerate it.")
            return 1
        if current != content:
            print("Wellness export differs from reviewed Python content; regenerate it.")
            return 1
        print("Wellness export matches reviewed Python catalogs and parser rules.")
        return 0
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_text(json.dumps(content, indent=2, ensure_ascii=False) + "\n")
    print("Exported reviewed wellness catalogs; no profiles or credentials included.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))

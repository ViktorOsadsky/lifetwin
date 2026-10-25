"""Export authored conversation content and empty model defaults for Supabase.

Run in the locked server environment. ``--check`` compares parsed JSON so Deno
formatting cannot cause drift. No fixtures, request data, or credentials are read.
"""

import argparse
import json
from dataclasses import asdict
from pathlib import Path
from types import ModuleType

from lifetwin.change import scripts as change
from lifetwin.change.models import ChangeState
from lifetwin.checkin import scripts as checkin
from lifetwin.checkin.models import CheckinState
from lifetwin.core.models import CheckinValues, HealthProfile
from lifetwin.onboarding import intents
from lifetwin.onboarding import script as onboarding
from lifetwin.onboarding.models import ConversationState, HabitNote

DESTINATION = (
    Path(__file__).resolve().parents[1] / "supabase/functions/lifetwin-api/conversation-data.json"
)


def constants(module: ModuleType) -> dict:
    """Keep only JSON-compatible, authored uppercase constants, in source order."""
    result = {}
    for name, value in vars(module).items():
        if not name.isupper():
            continue
        try:
            json.dumps(value)
        except TypeError:
            continue
        result[name] = value
    return result


def export_content() -> dict:
    content = {
        "onboarding": constants(onboarding),
        "questions": {question.field: asdict(question) for question in onboarding.SCRIPT},
        "checkin": constants(checkin),
        "change": constants(change),
        "profile": HealthProfile().model_dump(mode="json"),
        "values": CheckinValues().model_dump(mode="json"),
        "onboardingState": ConversationState().model_dump(mode="json"),
        "changeState": ChangeState().model_dump(mode="json"),
        "habitNote": HabitNote(topic="exercise").model_dump(mode="json", by_alias=True),
        "checkinState": CheckinState(
            kind="daily", questions=list(checkin.DAILY), current_field=checkin.DAILY[0]
        ).model_dump(mode="json"),
        "emergency": intents.EMERGENCY_MESSAGE,
        "safety": {
            name: getattr(intents, name).pattern
            for name in (
                "EMERGENCY",
                "SELF_HARM",
                "SELF_HARM_PAST",
                "HISTORY",
                "HAPPENING_NOW",
            )
        },
    }
    # JSON round-trip normalizes authored tuples to the arrays read by Deno.
    return json.loads(json.dumps(content, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the saved export is stale")
    args = parser.parse_args()
    content = export_content()
    if args.check:
        try:
            current = json.loads(DESTINATION.read_text())
        except (OSError, ValueError):
            print("Conversation export is missing or invalid; regenerate it.")
            return 1
        if current != content:
            print("Conversation export differs from the authored Python sources; regenerate it.")
            return 1
        print("Conversation export matches authored Python content and empty defaults.")
        return 0
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n")
    print("Exported authored conversation content and empty defaults; no health records or keys.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

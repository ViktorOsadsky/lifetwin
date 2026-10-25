"""Copy the server's reviewed quiz bank into the app's offline asset, in the same schema.

The app bundles the bank so the quiz works offline. Run this after the server bank changes:
    uv run python server/tools/export_quiz_bank.py
`--check` exits 1 when the asset differs from the server bank.
"""

from __future__ import annotations

import sys
from pathlib import Path

from lifetwin.quiz.service import parse_bank_json

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "server/lifetwin/quiz/content/questions.json"
ASSET = ROOT / "app/assets/quiz/questions.json"


def main(argv: list[str]) -> int:
    raw = SOURCE.read_text(encoding="utf-8")
    bank = parse_bank_json(raw)  # only a valid, reviewed bank is exported
    if "--check" in argv:
        if ASSET.read_text(encoding="utf-8") != raw:
            print(f"{ASSET.relative_to(ROOT)} differs from the server bank {bank.bank_version}")
            return 1
        return 0
    ASSET.write_text(raw, encoding="utf-8")
    print(f"Wrote {bank.total} questions (bank {bank.bank_version}) to {ASSET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

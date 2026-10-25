"""Synthetic endpoint acceptance, in-process only; no external provider calls."""
import json
import subprocess
from pathlib import Path

import lifetwin.onboarding  # noqa: F401
from fastapi.testclient import TestClient
from lifetwin.app import create_app
from lifetwin.core.config import Settings


class FakeProvider:
    name = "muse"
    configured = True
    may_train_on_content = False

    def __init__(self, line):
        self.line = line
        self.calls = 0

    async def phrase(self, instructions, facts):
        self.calls += 1
        return {"lines": [item["draft"] + " " + self.line for item in facts["items"]]}


def app():
    return create_app(Settings(_env_file=None, app_env="test", rate_limit_per_minute=10000,
                               openai_api_key="", llm_api_key="", cartesia_api_key=""))


profile = dict(age=64, sex="female", height_cm=162.6, weight_kg=66.49,
               sleep_hours=6.9, smoking_status="never", diabetes=False,
               hypertension_diagnosed=False, general_health="good", sedentary_min_day=420,
               moderate_recreation_min_week=120, vigorous_recreation_min_week=0)
records = []
for endpoint in ["/api/recommendations", "/api/coach/plan"]:
    bodies = []
    for label, kg in [("baseline", 66.49), ("BMI_plus_one", 66.49 + 1.626 ** 2)]:
        request = {"profile": {**profile, "weight_kg": kg}, "habit_notes": []}
        if endpoint.endswith("plan"):
            request["local_date"] = "2026-10-24"
        response = TestClient(app()).post(endpoint, json=request)
        assert response.status_code == 200, (endpoint, response.text)
        body = response.json()
        bodies.append(body)
        records.append(dict(kind="keyless_template", endpoint=endpoint, label=label,
                            request=request, status=response.status_code, response=body))
    fields = ["kind", "catalog_id", "minutes", "time_of_day", "lever", "message", "effect"]
    key = "items" if endpoint.endswith("plan") else "recommendations"
    selected = [[{k: x.get(k) for k in fields} for x in b.get(key, [])] for b in bodies]
    assert bodies[0][key] and bodies[0][key] == bodies[1][key]
    assert selected[0] == selected[1], (endpoint, "BMI-only change altered recommendation content")
    records.append(dict(kind="BMI_only_content_comparison", endpoint=endpoint,
                        content_unchanged=True, selected=selected[0]))

for endpoint in ["/api/recommendations", "/api/coach/plan"]:
    for line in ["Getting heavier helps your health.", "Putting on mass improves your outlook.",
                 "Gaining weight improves survival."]:
        application = app()
        provider = FakeProvider(line)
        application.state.personalizer = provider
        application.state.coach_phraser = provider
        request = {"profile": {**profile, "smoking_status": "current"}, "habit_notes": [],
                   "outside_ai_consent": {"muse": True}}
        if endpoint.endswith("plan"):
            request["local_date"] = "2026-10-24"
        response = TestClient(application).post(endpoint, json=request)
        assert response.status_code == 200, (endpoint, response.text)
        body = response.json()
        records.append(dict(kind="fake_consented_provider", endpoint=endpoint, line=line,
                            provider_calls=provider.calls, status=response.status_code,
                            disallowed_line_published=line in json.dumps(body), response=body))

result = dict(schema="lifetwin.qa107.server_checks.v0", synthetic=True,
              source_head=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
              scope="In-process real endpoints and deterministic fake provider; not live Muse or UI acceptance",
              records=records)
path = Path("/private/tmp/lifetwin-qa107-server-results.json")
path.write_text(json.dumps(result, indent=2) + "\n")
print("PASS keyless baseline/BMI+1 content invariance for both endpoints")
for r in records:
    if r["kind"] == "fake_consented_provider":
        print(r["endpoint"], r["line"], "published=", r["disallowed_line_published"], "calls=", r["provider_calls"])
print(path)

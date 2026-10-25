import { wellnessRoute } from "./wellness.ts";
import { extractDocument } from "./documents.ts";
import { routes, validate } from "./validation.ts";
import cases from "../../../contracts/fixtures/cases.json" with {
  type: "json",
};
function assert(
  condition: unknown,
  label = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(label);
}
async function call(path: string, payload: any = {}, query = "") {
  const value = await wellnessRoute(
    path,
    structuredClone(payload),
    new URL("https://example.test" + path + query),
    {},
  );
  assert(value);
  return value as { status: number; body: any };
}
Deno.test("Every valid educational request fixture yields its current response schema", async () => {
  let checked = 0;
  for (const fixture of cases as any[]) {
    if (
      ![
        "/api/advisor",
        "/api/recommendations",
        "/api/documents/extract",
        "/api/coach/plan",
      ].includes(fixture.path)
    ) continue;
    const request = structuredClone(fixture.request),
      schema = routes[fixture.path];
    if (!validate(schema[0], request)) continue;
    const value = await call(fixture.path, request);
    assert(value.status === fixture.status, "fixture status: " + fixture.name);
    assert(
      validate(
        value.status >= 400 ? "error.schema.json" : schema[1],
        value.body,
      ),
      "response contract: " + fixture.name,
    );
    checked++;
  }
  assert(checked >= 20, "educational fixtures exercised");
});
Deno.test("Quiz is reviewed versioned content with isolated local game health", async () => {
  const all = await call("/api/quiz/questions", {}, "?limit=100");
  assert(all.status === 200);
  assert(validate("quiz.schema.json", all.body));
  assert(all.body.total === 38);
  assert(all.body.questions.length === 38);
  assert(all.body.local_scoring.affects_prediction === false);
  assert(all.body.local_scoring.affects_confirmed_profile === false);
  const detail = await call("/api/quiz/questions/" + all.body.questions[0].id);
  assert(validate("quiz.question.schema.json", detail.body));
  assert((await call("/api/quiz/questions", {}, "?limit=0")).status === 422);
  assert(
    (await call("/api/quiz/questions", {}, "?topic=not-a-topic")).status ===
      422,
  );
  assert(
    (await call("/api/quiz/questions/missing-question.v1")).status === 404,
  );
});
Deno.test("Advisor sources remain reviewed and no causal effect is fabricated", async () => {
  const value = await call("/api/advisor", {
    topics: ["supplements", "sleep"],
    use_web_research: true,
  });
  assert(value.body.research.status === "unconfigured");
  assert(value.body.research.query_count === 0);
  for (const action of value.body.actions) {
    assert(action.modeled_effect === null);
    assert(action.modeled_effect_status === "unmodeled");
    assert(
      value.body.sources.some((s: any) =>
        s.id === action.source_ids[0] && s.topic === action.topic
      ),
    );
  }
  assert(
    (await call("/api/advisor", { topics: ["sleep", "sleep"] })).status === 422,
  );
});
Deno.test("Parser extracts actual text labels and strips identifiers", () => {
  const value = extractDocument({
    pages: [
      "SYNTHETIC CLINIC\nPatient: Testy McFakeface    MRN: 00000001\nDOB: 01/01/1950\nDate of service: 09/14/2026\nVitals\nBP 138/86   Wt 182 lb   Ht 5' 6\"\nProblem List\nType 2 diabetes mellitus\nFamily History\nMother: hypertension\nSocial History\nFormer smoker, quit 2009\nPlan: goal weight 170 lb",
    ],
  });
  assert(validate("documents.extract.schema.json", value));
  assert(value.status === "found");
  const fields = new Map(value.candidates.map((c: any) => [c.field, c]));
  assert((fields.get("height_cm") as any).value === 167.6);
  assert((fields.get("weight_kg") as any).value === 82.6);
  assert((fields.get("blood_pressure") as any).value === "138/86");
  assert(!fields.has("hypertension_diagnosed"));
  assert(value.notices.includes("other_person_skipped"));
  const rendered = JSON.stringify(value);
  assert(!rendered.includes("McFakeface"));
  assert(!rendered.includes("00000001"));
});
Deno.test("Parser refuses conflicting, family, goal and uncertain diagnosis values", () => {
  const value = extractDocument({
    pages: [
      "Patient: Ada Example\nVitals\nWeight 70 kg\nWeight 80 kg\nGoal weight 60 kg\nFamily History\nFather: height 180 cm; diabetes\nAssessment\nNo diabetes; possible hypertension",
    ],
  });
  assert(value.notices.includes("conflicting_values"));
  assert(
    !value.candidates.some((c: any) =>
      ["weight_kg", "height_cm", "hypertension_diagnosed", "diabetes_diagnosed"]
        .includes(c.field)
    ),
  );
  const multiple = extractDocument({
    pages: [
      "Patient: Ada Example\nVitals\nWeight 70 kg",
      "Patient: Bert Other\nVitals\nWeight 90 kg",
    ],
  });
  assert(multiple.candidates.length === 0);
  assert(multiple.notices.includes("multiple_patients"));
});
Deno.test("Recommendations honor excluded IDs, limits, effects and day rotation", async () => {
  const request = {
    profile: {
      age: 68,
      sex: "female",
      smoking_status: "current",
      sleep_hours: 5,
      moderate_recreation_min_week: 0,
      sedentary_min_day: 500,
    },
    habit_notes: [{
      topic: "exercise",
      barrier: "I use a wheelchair and my knees hurt",
    }],
    local_date: "2026-10-25",
  };
  const value = await call("/api/recommendations", request);
  assert(validate("recommendations.schema.json", value.body));
  assert(value.body.status === "ok");
  assert(value.body.causal_interpretation === false);
  const first = value.body.recommendations[0];
  assert(first.lever === "quit_smoking");
  const again = await call("/api/recommendations", request);
  assert(JSON.stringify(value) === JSON.stringify(again));
  const excluded = await call("/api/recommendations", {
    ...request,
    excluded_ids: [first.id],
  });
  assert(
    !JSON.stringify(excluded.body.recommendations).includes(
      '"' + first.id + '"',
    ),
  );
  const unknown = await call("/api/recommendations", { profile: {} });
  assert(unknown.body.status === "not_enough_information");
  assert(unknown.body.recommendations.length === 0);
  const minor = await call("/api/recommendations", {
    profile: { age: 16, smoking_status: "current" },
  });
  assert(minor.body.status === "under_age");
  assert(minor.body.recommendations.length === 0);
});
Deno.test("Coach pauses every movement card for acute symptoms and BP crisis", async () => {
  const emergency = await call("/api/coach/plan", {
    local_date: "2026-10-25",
    said: "My chest hurts and I can't breathe",
  });
  assert(emergency.body.status === "emergency");
  assert(emergency.body.items.length === 0);
  assert(emergency.body.emergency === true);
  assert(validate("coach.plan.schema.json", emergency.body));
  const crisis = await call("/api/coach/plan", {
    local_date: "2026-10-25",
    profile: { sedentary_min_day: 500 },
    readings: [{
      field: "systolic_bp",
      value: 185,
      unit: "mmHg",
      date: "2026-10-25",
      source: "typed",
    }],
  });
  assert(crisis.body.alert === "bp_crisis");
  assert(crisis.body.movement_paused === true);
  assert(
    !crisis.body.items.some((i: any) =>
      i.id === "move" || i.catalog_id === "sitting_breaks"
    ),
  );
  assert(validate("coach.plan.schema.json", crisis.body));
});
Deno.test("Coach revision is replayable, tampering refused, feedback removal retained", async () => {
  const req = {
    local_date: "2026-10-25",
    profile: { age: 67, sleep_hours: 6 },
  };
  const first = await call("/api/coach/plan", req);
  assert(validate("coach.plan.schema.json", first.body));
  const previous = {
    revision_id: first.body.revision_id,
    based_on: first.body.based_on,
    local_date: req.local_date,
    input_snapshot_id: first.body.inputs.snapshot_id,
    items: first.body.items.map((i: any) => ({
      id: i.id,
      kind: i.kind,
      catalog_id: i.catalog_id,
      minutes: i.minutes,
      time_of_day: i.time_of_day,
      callback_note_id: i.callback_note_id,
    })),
  };
  const reused = await call("/api/coach/plan", {
    ...req,
    previous_plan: previous,
    latest_revision_id: previous.revision_id,
  });
  assert(reused.body.reused_previous);
  assert(reused.body.revision_id === first.body.revision_id);
  const bad = structuredClone(previous);
  bad.items[0].catalog_id = "brisk_walk";
  assert(
    (await call("/api/coach/plan", { ...req, previous_plan: bad })).status ===
      409,
  );
  const changed = await call("/api/coach/plan", {
    ...req,
    previous_plan: previous,
    latest_revision_id: previous.revision_id,
    feedback: {
      revision_id: previous.revision_id,
      items: [{ item_id: "move", status: "dismissed" }],
    },
  });
  assert(!changed.body.items.some((i: any) => i.id === "move"));
  assert(changed.body.changes[0].change === "removed");
  const changedPrevious = {
    revision_id: changed.body.revision_id,
    based_on: changed.body.based_on,
    local_date: req.local_date,
    input_snapshot_id: changed.body.inputs.snapshot_id,
    items: changed.body.items.map((i: any) => ({
      id: i.id,
      kind: i.kind,
      catalog_id: i.catalog_id,
      minutes: i.minutes,
      time_of_day: i.time_of_day,
      callback_note_id: i.callback_note_id,
    })),
  };
  const changedReplay = await call("/api/coach/plan", {
    ...req,
    previous_plan: changedPrevious,
    latest_revision_id: changedPrevious.revision_id,
  });
  assert(changedReplay.body.reused_previous);
  assert(!changedReplay.body.items.some((i: any) => i.id === "move"));
});
Deno.test("Coach and recommendation calendar/reading dependencies fail closed", async () => {
  for (
    const payload of [
      { local_date: "2026-02-30" },
      { local_date: "2026-10-25", local_time: "25:10" },
      { local_date: "2026-10-25", checkins: [{ date: "2026-10-26" }] },
      {
        local_date: "2026-10-25",
        checkins: [{ date: "2026-10-25" }, { date: "2026-10-25" }],
      },
      {
        local_date: "2026-10-25",
        readings: [{
          field: "systolic_bp",
          value: 185,
          unit: "%",
          date: "2026-10-25",
          source: "typed",
        }],
      },
    ]
  ) assert((await call("/api/coach/plan", payload)).status === 422);
  assert(
    (await call("/api/recommendations", {
      profile: {},
      local_date: "2026-02-30",
    })).status === 422,
  );
  const past = await call("/api/coach/plan", {
    local_date: "2026-10-25",
    said: "I had chest pain in 2015",
  });
  assert(past.body.emergency === false);
  for (
    const text of [
      "kms",
      "I do not see the point of living",
      "I have saved pills to take all at once",
    ]
  ) {
    const response = await call("/api/coach/plan", {
      local_date: "2026-10-25",
      said: text,
    });
    assert(response.body.emergency === true, "shared emergency guard");
    assert(response.body.items.length === 0);
  }
});

/** Stateless educational routes using the repository's reviewed catalogs.
 * Edge subset: template wording only, deterministic parser, foreground plans.
 * No personal probability, causal benefit, diagnosis, or medication instruction.
 */
import content from "./wellness-content.json" with { type: "json" };
import { extractDocument } from "./documents.ts";
import { isEmergency } from "./conversation.ts";
const data: any = content;
export type WellnessResult = { status: number; body: unknown };
const ok = (body: unknown): WellnessResult => ({ status: 200, body });
const error = (
  status: number,
  code: string,
  message: string,
): WellnessResult => ({
  status,
  body: {
    schema_version: "1.0",
    status: "error",
    code,
    message,
    request_id: null,
  },
});
const copy = <T>(value: T): T => structuredClone(value);
const test = (source: string, text: string) =>
  new RegExp(source, "i").test(text);
function advisor(req: any): WellnessResult {
  const topics = req.topics ?? ["physical_activity", "sleep", "nutrition"];
  if (new Set(topics).size !== topics.length) {
    return error(422, "invalid_request", "Select each topic only once.");
  }
  const sources = topics.map((topic: string) =>
    copy(data.advisor.sources[topic])
  );
  if (sources.some((v: unknown) => !v)) {
    return error(422, "invalid_request", "Please check the selected topics.");
  }
  const researchStatus = req.use_web_research
    ? "unconfigured"
    : "not_requested";
  const limitations = copy(data.advisor.limitations);
  return ok({
    schema_version: "1.0",
    status: "educational",
    mode: "curated_educational",
    mascot_message: data.advisor.message,
    actions: topics.map((topic: string) => {
      const [title, next_step, evidence_summary] = data.advisor.copy[topic];
      return {
        id: `learn-${topic}`,
        topic,
        title,
        next_step,
        evidence_summary,
        source_ids: [data.advisor.sources[topic].id],
        evidence_kind: "public_health_guidance",
        modeled_effect_status: "unmodeled",
        modeled_effect: null,
        experiment_assumptions: null,
        optional: true,
      };
    }),
    sources,
    research: {
      status: researchStatus,
      sources: copy(sources),
      retrieved_source_ids: [],
      query_count: 0,
      page_count: 0,
      limitation: data.advisor.research_limitations[researchStatus],
    },
    limitations,
  });
}
function quiz(path: string, url: URL): WellnessResult {
  const bank = copy(data.quiz);
  if (path === "/api/quiz/questions") {
    const topic = url.searchParams.get("topic"),
      difficulty = url.searchParams.get("difficulty"),
      limit = Number(url.searchParams.get("limit") ?? 20);
    if (
      !Number.isInteger(limit) || limit < 1 || limit > 100 ||
      (topic !== null &&
        !["nutrition", "food_safety", "activity", "sleep", "habits"].includes(
          topic,
        )) ||
      (difficulty !== null && !["moderate", "challenging"].includes(difficulty))
    ) return error(422, "invalid_request", "Please check the quiz options.");
    const matches = bank.questions.filter((q: any) =>
      (topic === null || q.topic === topic) &&
      (difficulty === null || q.difficulty === difficulty)
    );
    return ok({
      ...bank,
      total: matches.length,
      questions: matches.slice(0, limit),
    });
  }
  const id = path.slice("/api/quiz/questions/".length);
  if (!/^[a-z][a-z0-9-]{2,60}\.v[1-9][0-9]{0,2}$/.test(id) || id.length > 66) {
    return error(422, "invalid_request", "Please check the quiz question.");
  }
  const question = bank.questions.find((q: any) => q.id === id);
  return question
    ? ok(question)
    : error(404, "quiz_question_not_found", "Quiz question not found.");
}
function hints(profile: any, notes: any[]): any {
  const feeling = [...notes].reverse().find((n) => n.feeling)?.feeling;
  const mood =
    ["great", "good", "lucky", "grateful", "hopeful"].includes(feeling)
      ? "good"
      : ["not great", "worried", "frustrated", "down", "tired"].includes(
          feeling,
        )
      ? "not_great"
      : feeling === "okay"
      ? "okay"
      : profile.general_health
      ? ({ fair: "okay", poor: "not_great" } as any)[profile.general_health] ??
        "good"
      : null;
  const moderate = profile.moderate_recreation_min_week,
    vigorous = profile.vigorous_recreation_min_week;
  const minutes = moderate != null || vigorous != null
    ? (moderate ?? 0) + 2 * (vigorous ?? 0)
    : profile.exercise_minutes_weekly;
  let energy = null;
  if (minutes != null) {
    let level = minutes >= 150 ? 2 : minutes >= 30 ? 1 : 0;
    if (profile.sleep_hours != null && profile.sleep_hours < 6) {
      level = Math.max(0, level - 1);
    }
    energy = ["low", "medium", "high"][level];
  } else if (profile.sleep_hours != null) {
    energy = profile.sleep_hours >= 6 ? "medium" : "low";
  }
  return { mood, energy };
}
const ordinal = (date: string) =>
  Math.floor(Date.parse(date + "T00:00:00Z") / 86400000) + 719163;
function realDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(value + "T00:00:00Z");
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}
const READING_RANGES: Record<string, Record<string, [number, number]>> = {
  systolic_bp: { mmHg: [40, 300] },
  diastolic_bp: { mmHg: [20, 200] },
  a1c: { "%": [3, 20] },
  ldl: { "mg/dL": [10, 500], "mmol/L": [0.3, 13] },
};
function validReading(entry: any): boolean {
  const bounds = READING_RANGES[entry.field]?.[entry.unit];
  return Boolean(
    bounds && entry.value >= bounds[0] && entry.value <= bounds[1] &&
      realDate(entry.date),
  );
}
function recommendations(req: any): WellnessResult {
  if (req.local_date != null && !realDate(req.local_date)) {
    return error(422, "invalid_request", "Please check the calendar day.");
  }
  if (
    (req.document_context?.readings ?? []).some((entry: any) =>
      !validReading(entry)
    )
  ) {
    return error(
      422,
      "invalid_request",
      "Please check the reading and its unit.",
    );
  }
  const p = req.profile ?? {},
    notes = req.habit_notes ?? [],
    r = data.recommendations;
  const base = {
    schema_version: "1.0",
    status: "not_enough_information",
    message:
      "Once I know a little more about your days, I'll have some ideas for you. There's no rush.",
    recommendations: [] as any[],
    featured: null as string | null,
    missing_inputs: [] as string[],
    character_hints: hints(p, notes),
    lever_ranking: {
      source: "docs/model-sensitivity.json",
      model_version: r.model_version,
      order: r.lever_order,
    },
    phrased_by: "templates",
    causal_interpretation: false,
    limitations: copy(r.limitations),
  };
  const raw = notes.flatMap((n: any) =>
    Object.entries(n).filter(([key, value]) =>
      !["topic", "source", "estimate_for", "tried_quitting"].includes(key) &&
      value != null
    ).map(([, value]) => String(value))
  ).join(" ").toLowerCase();
  const limits = new Set<string>(
    Object.entries(r.limits).filter(([, pattern]) =>
      test(pattern as string, raw)
    ).map(([name]) => name),
  );
  if (/\b(?:pain|pains|painful|ache|aches|sore|trouble|hurts?)\b/.test(raw)) {
    limits.add("knee_pain");
  }
  const interests = new Set(
    Object.entries(r.interests).filter(([, pattern]) =>
      test(pattern as string, raw)
    ).map(([name]) => name),
  );
  if (
    notes.some((n: any) =>
      n.naps && !["no", "never"].includes(n.naps.toLowerCase())
    )
  ) interests.add("nap");
  const times = new Set(
    Object.entries(r.times).filter(([, pattern]) =>
      test(pattern as string, raw)
    ).map(([name]) => name),
  );
  const company = notes.map((n: any) => n.with ?? "").join(" "),
    social = /\b(?:alone|myself|on my own)\b/.test(company)
      ? "solo"
      : /\b(?:friends?|group|class|wife|husband|partner|grand\w*)\b/.test(
          company,
        )
      ? "social"
      : null;
  const weather = /\b(?:weather|rain\w*|cold|hot|snow\w*|ice|icy)\b/.test(raw),
    band = p.age == null || p.age < 18
      ? null
      : p.age < 40
      ? "18-39"
      : p.age < 65
      ? "40-64"
      : "65+";
  const excluded = new Set(req.excluded_ids ?? []),
    day = ordinal(req.local_date ?? new Date().toISOString().slice(0, 10));
  // No vigorous pick for anyone under 18 (an unknown age keeps the ideas for all ages).
  const noVigorous = p.age != null && p.age < 18;
  const eligible = (idea: any) =>
    !excluded.has(idea.id) &&
    !(noVigorous && idea.lever === "vigorous_plus_60") &&
    !idea.avoid.some((tag: string) => limits.has(tag)) &&
    (!idea.needs || idea.interests.some((tag: string) => interests.has(tag))) &&
    (band === null
      ? (idea.ages.length === 3 ||
        (idea.needs &&
          idea.interests.some((tag: string) => interests.has(tag))))
      : idea.ages.includes(band));
  const score = (idea: any) =>
    3 * idea.interests.filter((tag: string) => interests.has(tag)).length +
    (idea.needs && idea.interests.some((tag: string) => interests.has(tag))
      ? 2
      : 0) +
    (idea.times.some((tag: string) => times.has(tag)) ? 1 : 0) +
    (social !== null && idea.social === social ? 1 : 0) + (weather
      ? (idea.place === "indoor" ? 1 : idea.place === "outdoor" ? -2 : 0)
      : 0);
  function pick(lever: string, stage: string): any[] {
    const pool = data.ideas.filter((i: any) =>
      i.lever === lever && i.stages.includes(stage) && eligible(i)
    ).sort((a: any, b: any) => a.id.localeCompare(b.id));
    const shift = day +
        [...`${lever}:${stage}`].reduce((n, c) => n + c.charCodeAt(0), 0),
      out: any[] = [];
    for (
      const rank of [...new Set<number>(pool.map(score))].sort((a, b) => b - a)
    ) {
      const tier = pool.filter((i: any) => score(i) === rank),
        k = shift % tier.length;
      out.push(...tier.slice(k), ...tier.slice(0, k));
    }
    return out;
  }
  function effect(idea: any): string | null {
    if (idea.coping || (p.age != null && (p.age < 18 || p.age > 85))) {
      return null;
    }
    const group = p.age >= 35 && p.age <= 49
      ? "35-49"
      : p.age >= 50 && p.age <= 64
      ? "50-64"
      : p.age >= 65 && p.age <= 79
      ? "65-79"
      : null;
    const median = [`${group}|${p.sex}`, group, "all"].map((key) =>
      key ? r.medians[key]?.[idea.lever] : null
    ).find((v) => v != null);
    if (median == null) return null;
    return r.thresholds.find(([, minimum]: any) => median >= minimum)?.[0] ??
      "tiny";
  }
  function ideaCard(
    idea: any,
    based: string[],
    lead = "",
    tail = "",
    pose: string | null = null,
  ): any {
    const steps: any = {
      vigorous_plus_60: ["vigorous_recreation_min_week", 60, null],
      moderate_plus_90: ["moderate_recreation_min_week", 90, null],
      short_sleep_plus_1h: ["sleep_hours", 1, 24],
      sitting_minus_60_realistic: ["sedentary_min_day", -60, null],
    };
    let experiment_lever = null, experiment_target: any = null;
    if (idea.lever === "quit_smoking") {
      experiment_lever = "smoking_status";
      experiment_target = "former";
    } else if (steps[idea.lever]) {
      const [field, delta, cap] = steps[idea.lever];
      experiment_lever = field;
      if (p[field] != null) {
        experiment_target = cap === null
          ? Math.max(0, p[field] + delta)
          : Math.min(cap, p[field] + delta);
      }
    }
    const source = r.sources[idea.source];
    return {
      id: idea.id,
      lever: idea.lever,
      title: idea.title,
      message: [lead, idea.message, tail].filter(Boolean).join(" ").slice(
        0,
        400,
      ),
      based_on: based,
      wellness_card: idea.card,
      source_title: source[0],
      source_url: source[1],
      effect: effect(idea),
      effect_note: "Modeled difference for people like you, not a promise.",
      experiment_lever,
      experiment_target,
      why_short: idea.why,
      source_domain: new URL(source[1]).hostname.replace(/^www\./, ""),
      kind: pose ?? idea.kind,
      causal_interpretation: false,
    };
  }
  function add(
    pool: any[],
    based: string[],
    lead = "",
    tail = "",
    pose: string | null = null,
  ): boolean {
    if (!pool.length) return false;
    const cards = pool.slice(0, 4).map((i) =>
      ideaCard(i, based, lead, tail, pose)
    );
    base.recommendations.push({ ...cards[0], alternatives: cards.slice(1) });
    return true;
  }
  const note = (topic: string) =>
    [...notes].reverse().find((n) => n.topic === topic);
  if (p.smoking_status === "current") {
    add(
      pick("quit_smoking", "any"),
      ["smoking_status", ...(note("smoking") ? ["note:smoking"] : [])],
      "",
      "When you’re ready, 1-800-QUIT-NOW offers free support.",
    );
  }
  const moderate = p.moderate_recreation_min_week,
    vigorous = p.vigorous_recreation_min_week;
  const minutes = moderate != null || vigorous != null
    ? (moderate ?? 0) + 2 * (vigorous ?? 0)
    : p.exercise_minutes_weekly;
  const activityFields = [
    "moderate_recreation_min_week",
    "vigorous_recreation_min_week",
    "exercise_minutes_weekly",
  ].filter((f) => p[f] != null);
  if (note("exercise")) activityFields.push("note:exercise");
  if (minutes === 0) {
    add(
      pick("moderate_plus_90", "start"),
      activityFields,
      "Even 10 to 15 minutes counts.",
      limits.size ? "Your doctor can suggest what's right for you." : "",
    );
  } else if (minutes != null && minutes >= 150) {
    add(
      pick("keep_it_up", "keep"),
      activityFields,
      `You're already active, at about ${minutes} minutes a week. That's at or above the 150 minutes adults are advised to aim for. Keep it up!`,
      "",
      "walk",
    );
  } else if (minutes != null || (note("exercise")?.kind)) {
    let done = false;
    if ((moderate ?? 0) > 0 && !vigorous && !limits.size) {
      done = add(pick("vigorous_plus_60", "pace"), activityFields);
    }
    if (!done) add(pick("moderate_plus_90", "more"), activityFields);
  }
  if (p.sleep_hours != null && p.sleep_hours < 7) {
    add(pick("short_sleep_plus_1h", "any"), [
      "sleep_hours",
      ...(note("sleep") ? ["note:sleep"] : []),
    ]);
  }
  if (p.sedentary_min_day != null && p.sedentary_min_day >= 240) {
    add(pick("sitting_minus_60_realistic", "any"), [
      "sedentary_min_day",
      ...(note("sitting") ? ["note:sitting"] : []),
    ]);
  }
  base.recommendations.sort((a, b) =>
    Number(a.lever === "keep_it_up") - Number(b.lever === "keep_it_up")
  );
  base.recommendations = base.recommendations.slice(0, 3);
  if (base.recommendations.length) {
    base.status = "ok";
    base.message = [
      "Here are a few ideas from what you told me.",
      ...base.recommendations.map((i) => i.message),
    ].join(" ").slice(0, 1500);
    base.featured = (base.recommendations.find((i) =>
      i.lever !== "keep_it_up"
    ) ?? base.recommendations[0]).id;
  } else {base.missing_inputs = Object.values<string>(r.lever_field).filter(
      (field) => p[field] == null,
    );}
  return ok(base);
}
function stable(value: any): string {
  if (Array.isArray(value)) return "[" + value.map(stable).join(",") + "]";
  if (value && typeof value === "object") {
    return "{" + Object.keys(value).sort().map((key) =>
      JSON.stringify(key) + ":" + stable(value[key])
    ).join(",") + "}";
  }
  return JSON.stringify(value);
}
async function hash(value: any): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(value)),
  );
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0"))
    .join("").slice(0, 16);
}
function ref(item: any): any {
  return {
    id: item.id,
    kind: item.kind,
    catalog_id: item.catalog_id,
    minutes: item.minutes ?? null,
    time_of_day: item.time_of_day ?? null,
    callback_note_id: item.callback_note_id ?? null,
  };
}
async function revision(
  based_on: string | null,
  local_date: string,
  snapshot: string,
  items: any[],
): Promise<string> {
  return "r" +
    await hash({ based_on, local_date, snapshot, items: items.map(ref) });
}
function safety(name: string, text: string): boolean {
  const p = data.coach.safety[name];
  return p ? test(p.source, text) : false;
}
function safetyHit(name: string, text: string): boolean {
  const p = data.coach.safety[name];
  if (!p) return false;
  const clean = text.toLowerCase().replaceAll("’", "'").replace(
    /[^\w'\s.;!?]/g,
    " ",
  ).replace(/\s+/g, " ");
  return clean.split(/[.;!?]|\bbut\b/).some((clause) => {
    for (const match of clause.matchAll(new RegExp(p.source, "gi"))) {
      if (!safety("NEGATED", clause.slice(0, match.index!))) return true;
    }
    return false;
  });
}
async function coach(req: any): Promise<WellnessResult> {
  const c = data.coach,
    p = req.profile ?? {},
    previous = req.previous_plan ?? null,
    feedback = req.feedback ?? null,
    date = req.local_date;
  if (
    !realDate(date) || (req.local_time != null &&
      (!/^\d{2}:\d{2}$/.test(req.local_time) ||
        +req.local_time.slice(0, 2) > 23 || +req.local_time.slice(3) > 59))
  ) {
    return error(
      422,
      "invalid_request",
      "Please check the calendar day and time.",
    );
  }
  const checkins = req.checkins ?? [],
    readings = req.readings ?? [],
    habitNotes = req.habit_notes ?? [];
  if (
    [...checkins, ...readings, ...(req.document_context?.readings ?? [])].some((
      entry: any,
    ) => !realDate(entry.date) || entry.date > date) ||
    habitNotes.some((entry: any) =>
      entry.noted_on != null && !realDate(entry.noted_on)
    ) ||
    new Set(checkins.map((entry: any) => entry.date)).size !==
      checkins.length ||
    new Set(habitNotes.map((entry: any) => entry.id)).size !==
      habitNotes.length ||
    (previous &&
      (!realDate(previous.local_date) ||
        new Set(previous.items.map((entry: any) => entry.id)).size !==
          previous.items.length)) ||
    (feedback &&
      new Set((feedback.items ?? []).map((entry: any) => entry.item_id))
          .size !== (feedback.items ?? []).length)
  ) {
    return error(
      422,
      "invalid_request",
      "Please check the dates and duplicate entries.",
    );
  }
  if (
    [...readings, ...(req.document_context?.readings ?? [])].some((
      entry: any,
    ) => !validReading(entry))
  ) {
    return error(
      422,
      "invalid_request",
      "Please check the reading and its unit.",
    );
  }
  if (feedback && (!previous || req.latest_revision_id == null)) {
    return error(
      422,
      "invalid_request",
      "Feedback needs the plan it is about.",
    );
  }
  if (previous) {
    const expected = await revision(
      previous.based_on ?? null,
      previous.local_date,
      previous.input_snapshot_id,
      previous.items,
    );
    if (
      expected !== previous.revision_id ||
      (req.latest_revision_id != null &&
        req.latest_revision_id !== previous.revision_id) ||
      (feedback && feedback.revision_id !== previous.revision_id) ||
      previous.local_date > date
    ) {
      return error(
        409,
        "stale_revision",
        "There is a newer or changed plan. Please refresh today's plan.",
      );
    }
  }
  const limitations = [
    "Ideas follow public-health guidance; they are not medical advice and promise no benefit. The activity and food lists await professional review.",
    "The server keeps nothing. The plan, notes and history stay on your phone.",
    "Plans refresh when the app is opened or resumed; nothing runs in the background.",
    "This backend uses a limited deterministic catalog planner; individualized progression, memory callbacks and outside-AI plan wording are unavailable.",
  ];
  const base: any = {
    schema_version: "1.0",
    status: "ok",
    revision_id: null,
    based_on: previous?.revision_id ?? null,
    local_date: date,
    inputs: null,
    plan_type: null,
    reused_previous: false,
    clarify: null,
    alert: null,
    notices: [],
    lines: [],
    reply: null,
    items: [],
    changes: [],
    trace: [],
    mood: "cozy",
    mascot_events: [],
    emergency: false,
    movement_paused: false,
    memory_instruction: null,
    phrased_by: "templates",
    provider_status: "not_requested",
    causal_interpretation: false,
    limitations,
  };
  // As safety.clean(): full-width letters folded and invisible characters dropped, so a
  // spelling trick cannot hide a word from the gates.
  const said = (req.said ?? "").normalize("NFKC").replace(/\p{Cf}/gu, "")
    .replaceAll("’", "'");
  const notes = req.memory_consent === true ? (req.habit_notes ?? []) : [];
  const text = [
    said,
    ...notes.flatMap((n: any) =>
      Object.entries(n).filter(([key]) =>
        !["id", "source", "name", "noted_on"].includes(key)
      ).map(([, v]) => v)
    ),
    ...(feedback?.items ?? []).map((i: any) => i.reason ?? ""),
  ].join(" ").toLowerCase();
  const acute = isEmergency(said) ||
    (safetyHit("ACUTE", said) && !safety("LONG_AGO", said));
  if (acute) {
    base.status = "emergency";
    base.emergency = true;
    base.movement_paused = true;
    base.mood = "concerned";
    base.reply = c.emergency_message;
    base.lines = [base.reply];
    base.mascot_events = [{ state: "concerned", caption: base.reply }];
    return ok(base);
  }
  const limits = new Set<string>(req.limits ?? []);
  for (const [name, source] of Object.entries(data.recommendations.limits)) {
    if (test(source as string, text)) limits.add(name);
  }
  if (/\b(?:pain|hurts?|ache|sore)\b/.test(text)) limits.add("knee_pain");
  const recentReadings = (req.readings ?? []).filter((r: any) =>
    ordinal(date) - ordinal(r.date) <= 7 && r.date <= date
  );
  const crisis = recentReadings.some((r: any) =>
    (r.field === "systolic_bp" && r.value >= 180) ||
    (r.field === "diastolic_bp" && r.value >= 120)
  );
  const paused = req.movement_paused === true || safetyHit("RED_FLAG", text) ||
    safetyHit("ACUTE", text) || crisis;
  base.movement_paused = paused;
  if (crisis) {
    base.alert = "bp_crisis";
    base.reply = c.replies.BP_CRISIS_REPLY;
  } else if (paused) base.reply = c.replies.RED_FLAG_REPLY;
  else {for (
      const [name, key] of [
        ["SUPPLEMENT", "SUPPLEMENT_REPLY"],
        ["MEDICINE", "MEDICINE_REPLY"],
        ["DOSE", "MEDICINE_REPLY"],
        ["KIDNEY", "KIDNEY_FOOD_REPLY"],
        ["DIABETES_FOOD", "DIABETES_FOOD_REPLY"],
        ["WEIGHT", "WEIGHT_REPLY"],
        ["FORECAST", "FORECAST_REPLY"],
        ["DIAGNOSIS", "DIAGNOSIS_REPLY"],
      ]
    ) {
      if (safety(name, said)) {
        base.reply = c.replies[key];
        break;
      }
    }}
  if (safety("FORGET_ALL", said)) {
    base.memory_instruction = {
      action: "forget_all",
      note_ids: [],
      confirm_prompt:
        "Forget everything in Mochi’s notebook? Please confirm twice.",
      confirmations_needed: 2,
    };
  } else if (safety("FORGET", said)) {
    base.reply = c.replies.FORGET_WHICH ??
      "Which note should I forget? Please open the notebook to choose.";
  }
  const usedNotes = notes.map((n: any) => ({
    id: n.id,
    topic: n.topic,
    barrier: n.barrier ?? null,
    concern: n.concern ?? null,
    feeling: n.feeling ?? null,
  }));
  const snapshot = await hash({
    profile: p,
    checkins: req.checkins ?? [],
    readings: req.readings ?? [],
    notes: usedNotes,
    limits: [...limits].sort(),
    movement_paused: paused,
  });
  const logged = (req.checkins ?? []).filter((d: any) =>
    d.date <= date && ordinal(date) - ordinal(d.date) < 7
  );
  base.inputs = {
    snapshot_id: snapshot,
    observed: [
      ...[
        "age",
        "smoking_status",
        "sleep_hours",
        "hypertension_diagnosed",
        "diabetes",
      ].filter((f) => p[f] != null).map((f) => "profile." + f),
      ...(logged.length ? ["checkins"] : []),
      ...(limits.size ? ["limits"] : []),
    ],
    missing: ["moderate_recreation_min_week", "sleep_hours"].filter((f) =>
      p[f] == null
    ).map((f) => "profile." + f),
    stale:
      (req.checkins ?? []).some((d: any) => ordinal(date) - ordinal(d.date) > 7)
        ? ["checkins"]
        : [],
    days_logged_last_7: logged.length,
    experiments_used: false,
  };
  // A general plan labels its limited knowledge even when a few fields are known.
  base.plan_type = "general";
  base.clarify =
    "To make this more personal: on how many days did you get moving last week?";
  function item(
    slot: string,
    kind: string,
    card: any,
    based: string[],
    time: string,
  ): any {
    return {
      id: slot,
      kind,
      action_id: card.id,
      catalog_id: card.id,
      lever: card.lever ?? null,
      title: card.title,
      message: card.message,
      why: card.why,
      minutes: null,
      time_of_day: time,
      intensity: null,
      position: null,
      counts_as: null,
      based_on: based,
      wellness_card: card.wellness_card ?? null,
      source_title: card.source[0],
      source_url: card.source[1],
      callback_note_id: null,
      controls: ["accept", "edit", "dismiss"],
      reviewed_by: "awaiting professional review",
      causal_interpretation: false,
    };
  }
  if (!paused) {
    const a = c.activities.chair_march;
    const movement = item(
      "move",
      "workout",
      {
        ...a,
        message: a.steps.replaceAll("{minutes}", String(a.minutes)),
        why:
          "A short, seated movement idea from the reviewed activity catalog.",
        wellness_card: "activity",
      },
      limits.size ? ["limits"] : ["default"],
      "morning",
    );
    Object.assign(movement, {
      minutes: a.minutes,
      intensity: a.intensity,
      position: a.position,
      counts_as: a.counts_as,
    });
    base.items.push(movement);
  }
  // Kidney/diabetes food needs individualized care; do not substitute a diet card.
  if (
    !safety("KIDNEY", text) && !safety("DIABETES_FOOD", text) &&
    p.diabetes !== true
  ) {
    const original = c.diets.mediterranean,
      card = p.age != null && p.age >= 65
        ? original
        : { ...original, ...original.younger };
    base.items.push(item("food", "diet", card, ["default"], "afternoon"));
  }
  let habit: any = null;
  if (p.smoking_status === "current") habit = c.habits.quit_help;
  else if (p.sleep_hours != null && p.sleep_hours < 7) {
    habit = c.habits.sleep_routine;
  } // Movement stays paused across every card, including sitting-break habits.
  else if (
    !paused && p.sedentary_min_day != null && p.sedentary_min_day >= 240
  ) habit = c.habits.sitting_breaks;
  if (habit) {
    const card = copy(habit);
    if (limits.has("seated_only") && card.variants.seated_only) {
      card.message = card.variants.seated_only;
    }
    base.items.push(
      item("habit", "habit", card, [
        card.wellness_card === "sleep"
          ? "profile.sleep_hours"
          : card.wellness_card === "smoking"
          ? "profile.smoking_status"
          : "profile.sedentary_min_day",
      ], card.wellness_card === "sleep" ? "evening" : "afternoon"),
    );
  }
  for (const action of feedback?.items ?? []) {
    const current = base.items.find((i: any) => i.id === action.item_id);
    if (!current) continue;
    if (action.status === "dismissed") {
      base.items = base.items.filter((i: any) => i.id !== action.item_id);
      base.changes.push({
        item_id: action.item_id,
        change: "removed",
        explanation:
          "You set this idea aside, so it is removed from this plan.",
      });
    } else if (action.status === "edited") {
      if (action.time_of_day) current.time_of_day = action.time_of_day;
      if (current.id === "move" && action.minutes != null) {
        const a = c.activities[current.catalog_id];
        current.minutes = Math.max(
          a.min_minutes,
          Math.min(a.max_minutes, action.minutes),
        );
        current.message = a.steps.replaceAll(
          "{minutes}",
          String(current.minutes),
        );
      }
      base.changes.push({
        item_id: action.item_id,
        change: "edited",
        explanation:
          "Your requested time or duration was applied within the catalog’s supported range.",
      });
    }
  }
  const same = previous?.local_date === date &&
    previous?.input_snapshot_id === snapshot && !feedback;
  if (same) {
    // Reconstruct only known reviewed actions; never echo client-supplied wording.
    for (const action of previous.items) {
      const current = base.items.find((i: any) =>
        i.id === action.id && i.catalog_id === action.catalog_id
      );
      if (current) {
        current.time_of_day = action.time_of_day ?? current.time_of_day;
        if (current.id === "move" && action.minutes != null) {
          const a = c.activities[current.catalog_id];
          if (
            action.minutes >= a.min_minutes && action.minutes <= a.max_minutes
          ) {
            current.minutes = action.minutes;
            current.message = a.steps.replaceAll(
              "{minutes}",
              String(action.minutes),
            );
          }
        }
      }
    }
    base.items = base.items.filter((i: any) =>
      previous.items.some((old: any) =>
        old.id === i.id && old.catalog_id === i.catalog_id
      )
    );
    base.reused_previous = true;
    base.based_on = previous.based_on ?? null;
  }
  base.revision_id = await revision(base.based_on, date, snapshot, base.items);
  if (!base.items.length) {
    base.reply = base.reply ??
      "You can leave these ideas aside. Your care team can help choose what fits you.";
    base.clarify = null;
  }
  base.trace = base.items.map((i: any) => ({
    item_id: i.id,
    facts: [{
      source: i.based_on[0] ?? "default",
      value:
        "Confirmed context or a labelled general option; no hypothetical experiment.",
    }],
    rule: "reviewed_catalog_general_edge_v1",
    evidence: i.source_url,
    action: i.catalog_id,
  }));
  base.lines = [
    ...(base.reply ? [base.reply] : []),
    ...base.items.map((i: any) => i.message),
  ];
  if (!base.lines.length) {
    base.lines = ["We can pick a small step when you are ready."];
  }
  base.mood = paused
    ? "concerned"
    : (feedback?.items ?? []).some((i: any) => i.status === "done")
    ? "proud"
    : "cozy";
  base.mascot_events = [{
    state: paused
      ? "concerned"
      : base.mood === "proud"
      ? "celebrating"
      : "idle",
    caption: base.lines[0],
  }];
  return ok(base);
}
export async function wellnessRoute(
  path: string,
  payload: any,
  url: URL,
  _config: Record<string, string>,
): Promise<WellnessResult | null> {
  if (
    path === "/api/quiz/questions" || path.startsWith("/api/quiz/questions/")
  ) return quiz(path, url);
  if (path === "/api/advisor") return advisor(payload);
  if (path === "/api/recommendations") return recommendations(payload);
  if (path === "/api/documents/extract") return ok(extractDocument(payload));
  if (path === "/api/coach/plan") return await coach(payload);
  return null;
}

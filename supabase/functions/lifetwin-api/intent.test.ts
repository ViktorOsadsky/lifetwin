import assert from "node:assert/strict";
import matrix from "../../../contracts/fixtures/yes-no-intent.json" with {
  type: "json",
};
import {
  clearNo,
  clearYes,
  type Complete,
  INTENT_PROMPT,
  type IntentResult,
  MEMORY,
  type Question,
  readBack,
  readIntent,
  readLocal,
  validate,
} from "./intent.ts";
import data from "./intent-data.json" with { type: "json" };
import { conversationRoute } from "./conversation.ts";

const byKind = data.questions as Record<string, Question>;
const QUESTIONS: Record<string, Question> = Object.fromEntries(
  Object.entries(matrix.questions).map(([name, q]) => [
    name,
    q.kind === "read_back" ? readBack(q.text) : byKind[q.kind],
  ]),
);
const rows = matrix.rows;
const reading = (r: IntentResult) => ({
  intent: r.intent,
  confidence: r.confidence,
  tone: r.tone,
  corrected_value: r.corrected_value,
  source: r.source,
  clear_yes: clearYes(r),
  clear_no: clearNo(r),
});
const answer = (
  intent: string,
  value: string | null = null,
  tone = "neutral",
  confidence = 0.95,
) => ({ intent, confidence, tone, corrected_value: value });

/** The Python test's stub: answers each reply's true intent, and counts the calls. */
function stub(answers: Record<string, unknown>) {
  const calls: Record<string, unknown>[] = [];
  const complete: Complete = (system, user, schema) => {
    const sent = JSON.parse(user);
    calls.push({ system, sent, schema });
    if (!(sent.reply in answers)) {
      throw new Error(`unexpected call for ${sent.reply}`);
    }
    return Promise.resolve(answers[sent.reply]);
  };
  return { calls, complete };
}

Deno.test("the matrix is the server's 187 replies over every question", () => {
  assert.equal(rows.length, 187);
  assert.deepEqual(
    new Set(rows.map((r) => r.question)),
    new Set(Object.keys(QUESTIONS)),
  );
});

Deno.test("rules: the same reading as the server on every row", () => {
  const differ = rows.filter((row) =>
    JSON.stringify(reading(readLocal(row.reply, QUESTIONS[row.question]))) !==
      JSON.stringify(row.rules)
  ).map((row) => [row.question, row.reply]);
  assert.deepEqual(differ, []);
  for (const row of rows) {
    const r = readLocal(row.reply, QUESTIONS[row.question]);
    assert.ok([row.truth, ...row.alternatives].includes(r.intent), row.reply);
    // Safety: the rules never hear a clear yes that wasn't one.
    if (row.truth !== "yes") assert.ok(!clearYes(r), row.reply);
  }
  const right =
    rows.filter((row) =>
      readLocal(row.reply, QUESTIONS[row.question]).intent === row.truth
    ).length;
  console.log(`local intent accuracy ${right}/${rows.length}`);
  assert.ok(right / rows.length >= 0.95);
});

Deno.test("Claude path (stubbed): the same reading and calls as the server on every row", async () => {
  const { calls, complete } = stub(
    Object.fromEntries(
      rows.map((row) => [
        row.reply,
        answer(row.truth, row.truth === "correction" ? row.reply : null),
      ]),
    ),
  );
  const differ = [];
  for (const row of rows) {
    const before = calls.length;
    const r = await readIntent(row.reply, QUESTIONS[row.question], complete, {
      allowed: true,
    });
    const mine = { ...reading(r), asked_claude: calls.length > before };
    if (JSON.stringify(mine) !== JSON.stringify(row.claude_path)) {
      differ.push([row.question, row.reply, mine]);
    }
  }
  assert.deepEqual(differ, []);
  assert.equal(
    calls.length,
    rows.filter((r) => r.claude_path.asked_claude).length,
  );
  assert.ok(
    calls.every((c) =>
      !["memory", "outside_ai", "voice"].some((k) =>
        (c.sent as Record<string, string>).question === byKind[k].text
      )
    ),
    "a consent question reached Claude",
  );
  assert.ok(calls.every((c) => c.system === INTENT_PROMPT));
});

Deno.test("owner's example: the memory question, 'take all of my data, just take it all' is a yes without Claude", async () => {
  const { calls, complete } = stub({});
  for (const allowed of [false, true]) {
    const r = await readIntent(
      "take all of my data, just take it all",
      MEMORY,
      complete,
      { allowed, askClaude: true },
    );
    assert.equal(r.intent, "yes");
    assert.ok(clearYes(r));
    assert.equal(r.source, "rules");
  }
  assert.equal(calls.length, 0);
});

Deno.test("consent questions never reach Claude, even when the rules are unsure", async () => {
  const { calls, complete } = stub({});
  for (const kind of ["memory", "outside_ai", "voice"]) {
    const r = await readIntent(
      "hmm, what would you keep?",
      byKind[kind],
      complete,
      {
        allowed: true,
        askClaude: true,
      },
    );
    assert.equal(r.intent, "unsure");
  }
  assert.equal(calls.length, 0);
});

Deno.test("Claude never turns a no into a yes, and is asked only with consent", async () => {
  const health = byKind.health_offer;
  const { calls, complete } = stub({
    "nope I have no clue what you even said": answer("yes", null, "reluctant"),
    "i guess?": answer("yes", null, "reluctant"),
  });
  const turned = await readIntent(
    "nope I have no clue what you even said",
    health,
    complete,
    {
      allowed: true,
      askClaude: true,
    },
  );
  assert.equal(turned.intent, "unsure");
  assert.ok(!clearYes(turned));
  const local = await readIntent("i guess?", health, complete);
  assert.equal(calls.length, 1);
  assert.equal(local.source, "rules");
  const heard = await readIntent("i guess?", health, complete, {
    allowed: true,
  });
  assert.equal(heard.source, "claude");
  assert.ok(clearYes(heard));
});

Deno.test("Claude's reply is validated strictly", () => {
  const text = "no, it's 5'11";
  for (
    const bad of [
      "not json",
      [],
      { intent: "yes", confidence: 0.9, tone: "neutral" },
      { ...answer("yes"), extra: 1 },
      answer("maybe"),
      answer("yes", null, "sarcastic"),
      { ...answer("yes"), confidence: true },
      { ...answer("yes"), confidence: 1.5 },
      answer("correction", "6 foot 2"),
      answer("correction"),
    ]
  ) assert.equal(validate(bad, text), null, JSON.stringify(bad));
  assert.equal(
    validate(answer("correction", "5'11"), text)?.corrected_value,
    "5'11",
  );
  assert.equal(validate(answer("no", "6 foot 2"), text)?.corrected_value, null);
  assert.equal(validate(JSON.stringify(answer("no")), text)?.intent, "no");
});

Deno.test("a Claude failure or a slow Claude keeps the rules' reading", async () => {
  const q = readBack("Age: 46. Is that right?");
  const failing: Complete = () => Promise.reject(new Error("down"));
  assert.equal(
    (await readIntent("hmm", q, failing, { allowed: true })).source,
    "rules",
  );
  const empty: Complete = () => Promise.resolve(null);
  assert.equal(
    (await readIntent("hmm", q, empty, { allowed: true })).source,
    "rules",
  );
  let timer: ReturnType<typeof setTimeout> | undefined;
  const slow: Complete = () =>
    new Promise((done) => timer = setTimeout(() => done(answer("yes")), 4500));
  const started = Date.now();
  const r = await readIntent("hmm", q, slow, { allowed: true });
  clearTimeout(timer);
  assert.equal(r.source, "rules");
  assert.ok(Date.now() - started < 4400);
});

// -- Through the conversation route ---------------------------------------------------

const CLAUDE = { ANTHROPIC_API_KEY: "synthetic-test-key" };
const CONSENT = {
  provider_consent: true,
  outside_ai_consent: { claude: true },
};
/** Runs ``body`` with fetch answering as Claude would (``answers`` by reply). */
async function withClaude(
  answers: Record<string, unknown>,
  body: (sent: string[]) => Promise<void>,
) {
  const original = globalThis.fetch;
  const sent: string[] = [];
  globalThis.fetch = (_input, init) => {
    const reply = JSON.parse(
      JSON.parse(String(init?.body)).messages[0].content,
    ).reply;
    sent.push(reply);
    return Promise.resolve(Response.json({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify(answers[reply]) }],
    }));
  };
  try {
    await body(sent);
  } finally {
    globalThis.fetch = original;
  }
}
const onboarding = (state: Record<string, unknown>, text: string, extra = {}) =>
  conversationRoute("/api/onboarding/turn", {
    action: "reply",
    text,
    state,
    ...extra,
  }, CLAUDE);

Deno.test("route: the owner's example consents to memory, with no Claude call", async () => {
  await withClaude({}, async (sent) => {
    for (const extra of [{}, CONSENT]) {
      const r = await onboarding(
        { phase: "remembering" },
        "take all of my data, just take it all",
        extra,
      );
      assert.equal(r.status, 200);
      assert.equal(r.body.state.memory_consent, true);
      assert.equal(r.body.state.phase, "asking");
    }
    assert.deepEqual(sent, []);
  });
});

Deno.test("route: an unclear memory reply gets one check, then is a no", async () => {
  await withClaude({}, async (sent) => {
    // A question back is explained, as on the server, and is not an unclear answer.
    const asked = await onboarding(
      { phase: "remembering" },
      "hmm, what would you keep?",
      CONSENT,
    );
    assert.equal(asked.body.state.yes_no_checked, false);
    assert.equal(asked.body.state.phase, "remembering");
    const first = await onboarding(asked.body.state, "hmm", CONSENT);
    assert.equal(first.body.message, MEMORY.check);
    assert.equal(first.body.state.yes_no_checked, true);
    assert.equal(first.body.state.phase, "remembering");
    const yes = await onboarding(first.body.state, "sure, go ahead", CONSENT);
    assert.equal(yes.body.state.memory_consent, true);
    const again = await onboarding(first.body.state, "hmm", CONSENT);
    assert.equal(again.body.state.memory_consent, false);
    assert.equal(again.body.state.phase, "asking");
    assert.ok(again.body.message.startsWith(data.lines.MEMORY_UNCLEAR));
    assert.deepEqual(sent, []);
  });
});

Deno.test("route: loose replies to the Health offer and read-backs, Claude only with consent", async () => {
  await withClaude(
    { "i guess?": answer("yes", null, "reluctant") },
    async (sent) => {
      const offer = { phase: "offering" };
      const ok = await onboarding(offer, "go for it, fill them in");
      assert.equal(ok.body.client_action, "open_health_import");
      const local = await onboarding(offer, "i guess?");
      assert.deepEqual(sent, []);
      assert.equal(local.body.message, byKind.health_offer.check);
      const heard = await onboarding(offer, "i guess?", CONSENT);
      assert.deepEqual(sent, ["i guess?"]);
      assert.equal(heard.body.client_action, "open_health_import");
      const no = await onboarding(offer, "nah I'd rather just tell you");
      assert.equal(no.body.client_action ?? null, null);
      assert.notEqual(no.body.state.phase, "offering");
      const readBack = {
        phase: "confirming",
        current_field: "age",
        pending_profile: { age: 46 },
      };
      const saved = await onboarding(readBack, "you nailed it", CONSENT);
      assert.equal(saved.body.state.confirmed_profile.age, 46);
      const corrected = await onboarding(readBack, "no, it's 47", CONSENT);
      assert.equal(corrected.body.state.confirmed_profile.age, null);
      assert.equal(corrected.body.state.pending_profile.age, 47);
      // A number beside a yes is a value to read, never sent to Claude.
      const value = await onboarding(readBack, "yes, actually 48", CONSENT);
      assert.equal(value.body.state.pending_profile.age, 48);
      assert.deepEqual(sent, ["i guess?"]);
    },
  );
});

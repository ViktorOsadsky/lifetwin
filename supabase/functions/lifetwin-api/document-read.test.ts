import {
  documentInfo,
  pdfTextLayer,
  readDocument,
  verifyFindings,
} from "./document-read.ts";
import { redact } from "./documents.ts";
import { validate } from "./validation.ts";
import cases from "../../../contracts/fixtures/cases.json" with {
  type: "json",
};
function assert(
  condition: unknown,
  label = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(label);
}
const CONFIG = {
  ANTHROPIC_API_KEY: "synthetic-private-key",
  CLAUDE_MODEL: "synthetic-model",
};
const fixture: any = (cases as any[]).find((c) =>
  c.name === "documents-read-claude-stubbed"
);
const goodFinding = {
  field: "weight_kg",
  value: "82.6",
  unit: null,
  quote: "Weight: 182 lb",
  page: 1,
  section: "Vitals",
  date: "2026-09-14",
};
function provider(findings: any[], calls: any[] = []): typeof fetch {
  return ((url: any, init: any) => {
    calls.push({ url: String(url), init });
    return Promise.resolve(
      new Response(
        JSON.stringify({
          stop_reason: "end_turn",
          content: [{ type: "text", text: JSON.stringify({ findings }) }],
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;
}
function pdf(pages: string[]): Uint8Array {
  const objects: string[] = [],
    kids = pages.map((_, i) => `${3 + 2 * i} 0 R`).join(" "),
    font = 3 + 2 * pages.length;
  objects.push(
    "<< /Type /Catalog /Pages 2 0 R >>",
    `<< /Type /Pages /Kids [${kids}] /Count ${pages.length} >>`,
  );
  for (const [i, text] of pages.entries()) {
    const rows = text.split("\n").map((s) =>
      "(" +
      s.replaceAll("\\", "\\\\").replaceAll("(", "\\(").replaceAll(")", "\\)") +
      ") Tj T*"
    ).join(" ");
    const stream = "BT /F1 11 Tf 14 TL 50 780 Td " + rows + " ET";
    objects.push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${font} 0 R >> >> /Contents ${
        4 + 2 * i
      } 0 R >>`,
      `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
    );
  }
  objects.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  let out = "%PDF-1.4\n";
  const offsets: number[] = [];
  for (const [i, body] of objects.entries()) {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  }
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` +
    offsets.map((n) => String(n).padStart(10, "0") + " 00000 n \n").join("") +
    `trailer\n<< /Size ${
      objects.length + 1
    } /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(out);
}
const encode = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
Deno.test("Document capability identifies only the dedicated Claude provider", () => {
  assert(documentInfo(CONFIG).configured);
  assert(
    documentInfo({ ...CONFIG, DOCUMENT_PROVIDER: "local" }).configured ===
      false,
  );
  assert(documentInfo({ LLM_API_KEY: "muse" }).configured === false);
  // Owner ruling (2026-10-25): Claude by default, unconfigured without its key; Muse only
  // when DOCUMENT_PROVIDER names it.
  assert(documentInfo({}).provider === "claude");
  assert(documentInfo({}).configured === false);
  assert(
    documentInfo({ LLM_PROVIDER: "chat_completions" }).provider === "claude",
  );
  assert(documentInfo({ DOCUMENT_PROVIDER: "muse" }).provider === "muse");
  assert(documentInfo({ ...CONFIG, DOCUMENT_PROVIDER: "" }).configured);
  assert(documentInfo(CONFIG).max_pages === 20);
});
Deno.test("No Claude consent or key: PDF is not opened and provider never called", async () => {
  const calls: any[] = [];
  const keyless = await readDocument(
    { pdf_base64: "not-a-pdf", outside_ai_consent: { claude: true } },
    {},
    provider([], calls),
  );
  assert(keyless.body.provider_status === "unavailable");
  const no = await readDocument(
    { pdf_base64: "not-a-pdf", outside_ai_consent: { muse: true } },
    CONFIG,
    provider([], calls),
  );
  assert(no.body.provider_status === "consent_required");
  assert(calls.length === 0);
});
Deno.test("Real fixture PDF: Claude values are kept only when quote and number agree", async () => {
  const calls: any[] = [];
  const value = await readDocument(
    fixture.request,
    CONFIG,
    provider(fixture.claude_stub.findings, calls),
  );
  assert(value.status === 200);
  assert(value.body.provider_status === "used");
  assert(validate("documents.extract.schema.json", value.body));
  assert(
    value.body.candidates.length === 2,
    "invented quote, BP mismatch and family diagnosis must be dropped",
  );
  assert(
    value.body.candidates[0].field === "weight_kg" &&
      value.body.candidates[0].value === 82.6,
  );
  assert(
    value.body.candidates[1].field === "diabetes_diagnosed" &&
      value.body.candidates[1].value === true,
  );
  assert(
    value.body.candidates.every((c: any) =>
      c.method === "claude" && c.confidence === "high"
    ),
  );
  assert(value.body.notices.includes("other_person_skipped"));
  assert(!JSON.stringify(value.body).includes("McFakeface"));
  assert(
    calls.length === 1 &&
      calls[0].url === "https://api.anthropic.com/v1/messages",
  );
  const sent = JSON.parse(calls[0].init.body);
  assert(sent.messages[0].content[0].type === "document");
  assert(sent.messages[0].content[0].source.media_type === "application/pdf");
  assert(
    sent.messages[0].content[0].source.data === fixture.request.pdf_base64,
  );
});
Deno.test("Actual native PDF text preserves line and diagnosis context without external fetch", async () => {
  const bytes = pdf([
    "SYNTHETIC CLINIC\nPatient: Ada Example\nDate of service: 09/14/2026\nVitals\nWeight: 182 lb\nProblem List\nType 2 diabetes mellitus\nFamily History\nMother: hypertension",
  ]);
  const pages = await pdfTextLayer(bytes);
  assert(pages.length === 1);
  assert(pages[0].includes("Weight: 182 lb"));
  assert(pages[0].includes("\n"));
  const value = await readDocument(
    { pdf_base64: encode(bytes), outside_ai_consent: { claude: true } },
    CONFIG,
    provider([goodFinding]),
  );
  assert(value.body.candidates[0].value === 82.6);
  assert(value.body.candidates[0].section === "Vitals");
  assert(value.body.candidates[0].date === "2026-09-14");
});
Deno.test("Unverified scan quotes are low confidence and clearly labeled", async () => {
  const value = await readDocument(
    { pdf_base64: encode(pdf([""])), outside_ai_consent: { claude: true } },
    CONFIG,
    provider([goodFinding]),
  );
  assert(value.body.provider_status === "used");
  assert(value.body.candidates[0].confidence === "low");
  assert(
    value.body.limitations.some((s: string) => s.includes("no text layer")),
  );
  assert(validate("documents.extract.schema.json", value.body));
});
Deno.test("Malformed PDF, invalid base64 and overlong page counts fail before provider calls", async () => {
  const calls: any[] = [];
  for (const base64 of ["not base64", btoa("not a PDF"), btoa("%PDF-broken")]) {
    const result = await readDocument(
      { pdf_base64: base64, outside_ai_consent: { claude: true } },
      CONFIG,
      provider([], calls),
    );
    assert(result.status === 422);
    assert(result.body.code === "pdf_unreadable");
  }
  const tooMany = await readDocument(
    {
      pdf_base64: encode(pdf(Array.from({ length: 21 }, () => ""))),
      outside_ai_consent: { claude: true },
    },
    CONFIG,
    provider([], calls),
  );
  assert(tooMany.status === 422);
  assert(tooMany.body.code === "pdf_too_many_pages");
  assert(calls.length === 0);
});
Deno.test("Text-layer family, hallucinations, mismatches and unsupported diagnoses never become candidates", () => {
  const raw = [
    "Synthetic clinic report with sufficient words for actual text corroboration and careful parsing.\nVitals\nWeight: 182 lb\nBlood pressure: 138/86 mmHg\nFamily History\nMother: hypertension",
  ];
  const findings = [{ ...goodFinding, value: "60" }, {
    ...goodFinding,
    quote: "Weight: 200 lb",
    value: "90.7",
  }, {
    field: "hypertension_diagnosed",
    value: "true",
    unit: null,
    quote: "Mother: hypertension",
    section: "Family History",
    page: 1,
    date: null,
  }, {
    field: "blood_pressure",
    value: "128/82",
    unit: null,
    quote: "Blood pressure: 138/86 mmHg",
    section: "Vitals",
    page: 1,
    date: null,
  }];
  const value = verifyFindings({ findings }, raw, redact(raw).pages);
  assert(value.candidates.length === 0);
  assert(value.notices.includes("other_person_skipped"));
});
Deno.test("Claude response refusal, malformed findings and budget denial return unavailable without sensitive output", async () => {
  for (
    const value of [{ stop_reason: "max_tokens", content: [] }, {
      stop_reason: "end_turn",
      content: [{ type: "text", text: "private-invalid-body" }],
    }, {
      stop_reason: "end_turn",
      content: [{
        type: "text",
        text: JSON.stringify({ findings: [{ ...goodFinding, value: 82.6 }] }),
      }],
    }]
  ) {
    const fetcher = (() =>
      Promise.resolve(new Response(JSON.stringify(value)))) as typeof fetch;
    const result = await readDocument(fixture.request, CONFIG, fetcher);
    assert(result.body.provider_status === "unavailable");
    assert(!JSON.stringify(result.body).includes("private-invalid-body"));
  }
  let calls = 0;
  const denied = await readDocument(
    fixture.request,
    {
      ...CONFIG,
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role",
    },
    (() => {
      calls++;
      return Promise.resolve(new Response("false"));
    }) as typeof fetch,
  );
  assert(calls === 1);
  assert(denied.body.provider_status === "unavailable");
});

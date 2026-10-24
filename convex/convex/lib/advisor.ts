// Port of server/lifetwin/advisor/ and research/: cited curated educational
// plans plus the bounded Tavily extract of reviewed pages. No inference, no
// profile or transcript in any outbound request.

import type { AdvisorRequest, ResearchTopic } from "./models";
import { decodeBody, pyJsonLoads } from "./jsonload";
import { readCapped } from "./providers";
import { pyLen, pyStrip } from "./py";

export interface EvidenceSource {
  id: string;
  topic: ResearchTopic;
  title: string;
  url: string;
  publisher: string;
  reviewed_on: "2026-10-23";
}

// Original authority sources checked on October 23, 2026 (Pacific time).
export const SOURCES: Record<ResearchTopic, EvidenceSource> = {
  physical_activity: {
    id: "niddk-start-activity",
    topic: "physical_activity",
    title: "Tips for Starting Physical Activity",
    url: "https://www.niddk.nih.gov/health-information/weight-management/" + "tips-get-active/tips-starting-physical-activity",
    publisher: "NIH National Institute of Diabetes and Digestive and Kidney Diseases",
    reviewed_on: "2026-10-23",
  },
  sleep: {
    id: "cdc-about-sleep",
    topic: "sleep",
    title: "About Sleep",
    url: "https://www.cdc.gov/sleep/about/",
    publisher: "Centers for Disease Control and Prevention",
    reviewed_on: "2026-10-23",
  },
  nutrition: {
    id: "cdc-healthy-eating",
    topic: "nutrition",
    title: "Healthy Eating Tips",
    url: "https://www.cdc.gov/nutrition/features/healthy-eating-tips.html",
    publisher: "Centers for Disease Control and Prevention",
    reviewed_on: "2026-10-23",
  },
  smoking: {
    id: "cdc-quitting-smoking",
    topic: "smoking",
    title: "Benefits of Quitting Smoking",
    url: "https://www.cdc.gov/tobacco/about/benefits-of-quitting.html",
    publisher: "Centers for Disease Control and Prevention",
    reviewed_on: "2026-10-23",
  },
  supplements: {
    id: "nih-supplements-consumer",
    topic: "supplements",
    title: "Dietary Supplements: What You Need to Know",
    url: "https://ods.od.nih.gov/factsheets/WYNTK-Consumer/",
    publisher: "NIH Office of Dietary Supplements",
    reviewed_on: "2026-10-23",
  },
};

export function curatedSources(topics: ResearchTopic[]): EvidenceSource[] {
  return topics.map((topic) => ({ ...SOURCES[topic] }));
}

export type ResearchStatus = "not_requested" | "unconfigured" | "retrieved" | "partial" | "unavailable";

export interface ResearchResult {
  status: ResearchStatus;
  sources: EvidenceSource[];
  retrieved_source_ids: string[];
  query_count: number;
  page_count: number;
  limitation: string;
}

const MAX_TOPICS = 3;
const MAX_PAGES = 5;
const MAX_RESPONSE_BYTES = 256_000;
const MAX_PAGE_CHARS = 40_000;
const ALLOWED_HOSTS = new Set(["www.cdc.gov", "www.niddk.nih.gov", "ods.od.nih.gov"]);

const REVIEWED_NOTE = "Your tips still come from health websites our team already reviewed.";
export const LIMITATIONS: Record<ResearchStatus, string> = {
  not_requested: `We did not go online for this plan. ${REVIEWED_NOTE}`,
  unconfigured: `Website checking is not set up, so we did not go online. ${REVIEWED_NOTE}`,
  unavailable: `We could not check the websites right now. ${REVIEWED_NOTE}`,
  partial: `We could check only some of the health websites right now. ${REVIEWED_NOTE}`,
  retrieved: "We checked that the health websites are online. The tips themselves were " + "already reviewed by our team.",
};

class InvalidProviderResponse extends Error {}

/** Python urllib.parse.urlsplit for the parts _page_key inspects. */
function urlsplit(value: string) {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):(?:\/\/([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/s.exec(value);
  if (!match) return null;
  const netloc = match[2] ?? "";
  const at = netloc.lastIndexOf("@");
  const userinfo = at >= 0 ? netloc.slice(0, at) : null;
  const hostport = at >= 0 ? netloc.slice(at + 1) : netloc;
  let hostname: string;
  let portText: string | null = null;
  const bracket = /^\[([^\]]*)\](?::(.*))?$/.exec(hostport);
  if (bracket) {
    hostname = bracket[1];
    portText = bracket[2] ?? null;
  } else {
    const colon = hostport.lastIndexOf(":");
    hostname = colon >= 0 ? hostport.slice(0, colon) : hostport;
    portText = colon >= 0 ? hostport.slice(colon + 1) : null;
  }
  let port: number | null = null;
  if (portText) {
    // Python raises ValueError for a nonnumeric or out-of-range port.
    if (!/^[0-9]+$/.test(portText) || Number(portText) > 65535) throw new Error("bad port");
    port = Number(portText);
  }
  return {
    scheme: match[1].toLowerCase(),
    hostname: hostname ? hostname.toLowerCase() : null,
    userinfo,
    port,
    path: match[3],
    query: match[4] ?? "",
    fragment: match[5] ?? "",
  };
}

/** Compare page URLs while tolerating a trailing slash or index.html suffix. */
export function pageKey(value: unknown): string | null {
  if (typeof value !== "string" || pyLen(value) > 500) return null;
  let parsed;
  try {
    parsed = urlsplit(value);
  } catch {
    return null;
  }
  if (
    !parsed ||
    parsed.scheme !== "https" ||
    !parsed.hostname ||
    !ALLOWED_HOSTS.has(parsed.hostname) ||
    parsed.userinfo !== null ||
    parsed.port !== null ||
    parsed.query ||
    parsed.fragment
  ) {
    return null;
  }
  let path = parsed.path;
  if (path.endsWith("/index.html")) path = path.slice(0, -"/index.html".length);
  if (path.endsWith("/")) path = path.slice(0, -1);
  return `${parsed.hostname}${path}`;
}

export interface ResearchOptions {
  apiKey: string;
  totalTimeoutSeconds?: number;
}

export async function research(topics: ResearchTopic[], options: ResearchOptions): Promise<ResearchResult> {
  if (topics.length === 0 || topics.length > MAX_TOPICS || new Set(topics).size !== topics.length) {
    throw new Error("Research requires one to three distinct reviewed topics.");
  }
  if (topics.some((topic) => !(topic in SOURCES))) throw new Error("Only reviewed research topics are supported.");
  const sources = curatedSources(topics);
  const apiKey = pyStrip(options.apiKey);
  if (!apiKey) {
    return {
      status: "unconfigured",
      sources,
      retrieved_source_ids: [],
      query_count: 0,
      page_count: 0,
      limitation: LIMITATIONS.unconfigured,
    };
  }
  // Server-side ceilings cannot be expanded by a client request.
  // One extract call, so the overall deadline bounds it (per-operation
  // timeouts in httpx cannot exceed it either).
  const totalTimeout = Math.min(Math.max(options.totalTimeoutSeconds ?? 12, 0.01), 15.0);
  // Only the fixed reviewed page URLs leave the server: no query text at all.
  const urls = sources.map((source) => source.url);
  const sourceByKey = new Map(sources.map((source) => [pageKey(source.url), source.id]));
  const found = new Set<string>();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), totalTimeout * 1000);
  try {
    const response = await fetch("https://api.tavily.com/extract", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ urls, extract_depth: "basic", format: "text", include_images: false }),
      redirect: "manual",
      signal: controller.signal,
    });
    if (response.status < 200 || response.status >= 300) throw new InvalidProviderResponse();
    const data = await readCapped(response, MAX_RESPONSE_BYTES, () => new InvalidProviderResponse());
    let extracted: any;
    try {
      extracted = pyJsonLoads(decodeBody(data));
    } catch {
      throw new InvalidProviderResponse();
    }
    if (!extracted || typeof extracted !== "object" || Array.isArray(extracted)) throw new InvalidProviderResponse();
    const rows = extracted.results;
    const failedRows = "failed_results" in extracted ? extracted.failed_results : [];
    if (!Array.isArray(rows) || rows.length > MAX_PAGES || !Array.isArray(failedRows) || failedRows.length > MAX_PAGES) {
      throw new InvalidProviderResponse();
    }
    const isRow = (row: unknown): row is Record<string, unknown> =>
      typeof row === "object" && row !== null && !Array.isArray(row);
    const failedKeys = new Set(failedRows.filter(isRow).map((row: Record<string, unknown>) => pageKey(row.url)));
    const accepted: string[] = [];
    for (const row of rows) {
      if (!isRow(row)) throw new InvalidProviderResponse();
      const key = pageKey(row.url);
      const content = row.raw_content;
      // Content is deliberately discarded, never interpolated into prompts,
      // returned to clients, logged, or used as instructions.
      if (
        key !== null &&
        sourceByKey.has(key) &&
        !failedKeys.has(key) &&
        typeof content === "string" &&
        pyLen(pyStrip(content)) >= 20 &&
        pyLen(pyStrip(content)) <= MAX_PAGE_CHARS
      ) {
        accepted.push(sourceByKey.get(key)!);
      }
    }
    for (const id of accepted) found.add(id);
  } catch {
    // No provider exception strings, keys, response bodies, or URLs in logs.
    found.clear();
  } finally {
    clearTimeout(timer);
  }
  const retrieved = sources.filter((source) => found.has(source.id)).map((source) => source.id);
  let status: ResearchStatus = retrieved.length === sources.length ? "retrieved" : "partial";
  if (retrieved.length === 0) status = "unavailable";
  return {
    status,
    sources,
    retrieved_source_ids: retrieved,
    query_count: 0,
    page_count: urls.length,
    limitation: LIMITATIONS[status],
  };
}

const COPY: Record<ResearchTopic, [string, string, string]> = {
  physical_activity: [
    "Find movement you enjoy",
    "Choose a comfortable, accessible activity and start small. Build up gradually. " +
      "If you have a health condition or disability, ask your care team what suits you.",
    "NIDDK advises starting slowly, building up, and discussing suitable activity " +
      "with a health professional when health conditions affect what is appropriate.",
  ],
  sleep: [
    "Make a sleep routine",
    "Choose a consistent bedtime and wake time that fit your routine. " +
      "If sleep difficulties persist, discuss them with a healthcare professional.",
    "CDC lists consistent bed and wake times among sleep habits and advises " +
      "consulting a healthcare provider about regular sleep difficulties.",
  ],
  nutrition: [
    "Try one food change",
    "Pick a meal you enjoy and add a fruit or vegetable that fits your budget, " +
      "preferences, allergies, and any existing care plan.",
    "CDC describes varied, nutrient-dense eating patterns and offers practical " + "ways to include fruits and vegetables.",
  ],
  smoking: [
    "Explore support for quitting",
    "If you smoke, read the CDC resource and consider discussing quitting support " +
      "with a healthcare professional. If you do not smoke, this is educational only.",
    "CDC explains that quitting smoking has health benefits regardless of age " + "or how long someone has smoked.",
  ],
  supplements: [
    "Review supplement safety first",
    "If considering a supplement, ask a pharmacist or clinician to review it " +
      "alongside your medicines. This plan does not select a product or dose.",
    "NIH ODS notes that supplements can interact with medicines and do not " +
      "replace a varied eating pattern. Discuss their use with healthcare providers.",
  ],
};

export async function buildPlan(request: AdvisorRequest, researchOptions: ResearchOptions) {
  const sources = curatedSources(request.topics);
  const researchResult: ResearchResult = request.use_web_research
    ? await research(request.topics, researchOptions)
    : {
        status: "not_requested",
        sources,
        retrieved_source_ids: [],
        query_count: 0,
        page_count: 0,
        limitation: LIMITATIONS.not_requested,
      };
  const actions = request.topics.map((topic) => {
    const [title, nextStep, evidence] = COPY[topic];
    return {
      id: `learn-${topic}`,
      topic,
      title,
      next_step: nextStep,
      evidence_summary: evidence,
      source_ids: [SOURCES[topic].id],
      evidence_kind: "public_health_guidance",
      modeled_effect_status: "unmodeled",
      modeled_effect: null,
      experiment_assumptions: null,
      optional: true,
    };
  });
  const limitations = [
    "These are general tips from trusted health websites. " + "They are not a diagnosis or a treatment plan.",
    "The tips are in the order you picked the topics. " + "They are not ranked by how much they might help.",
    "We have not measured how much each tip could help you. " + "That does not mean it will not help.",
    "Following a tip does not change the health details you gave us.",
    "When we check websites, we only open the same trusted pages for everyone. " +
      "We never send your health details. What we find online cannot change your tips.",
  ];
  const age = request.profile?.age;
  if (age !== null && age !== undefined && (age as number) < 18) {
    limitations.push(
      "We do not set age-based goals for young people. A parent, guardian, or " +
        "pediatric care team can help choose activities that suit a young person.",
    );
  }
  return {
    schema_version: "1.0",
    status: "educational",
    mode: "curated_educational",
    mascot_message: "Let's pick one small step! These ideas come from trusted health " + "websites. You choose what fits your life.",
    actions,
    sources,
    research: researchResult,
    limitations,
  };
}

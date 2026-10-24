"""Useful cited educational plans without inference or an invented LLM mode."""

from lifetwin.advisor.models import AdvisorRequest, AdvisorResponse, PlanAction
from lifetwin.research.models import ResearchResult, ResearchTopic
from lifetwin.research.sources import SOURCES, curated_sources
from lifetwin.research.tavily import TavilyResearch

_COPY: dict[ResearchTopic, tuple[str, str, str]] = {
    "physical_activity": (
        "Find movement you enjoy",
        "Choose a comfortable, accessible activity and start small. Build up gradually. "
        "If you have a health condition or disability, ask your care team what suits you.",
        "NIDDK advises starting slowly, building up, and discussing suitable activity "
        "with a health professional when health conditions affect what is appropriate.",
    ),
    "sleep": (
        "Make a sleep routine",
        "Choose a consistent bedtime and wake time that fit your routine. "
        "If sleep difficulties persist, discuss them with a healthcare professional.",
        "CDC lists consistent bed and wake times among sleep habits and advises "
        "consulting a healthcare provider about regular sleep difficulties.",
    ),
    "nutrition": (
        "Try one food change",
        "Pick a meal you enjoy and add a fruit or vegetable that fits your budget, "
        "preferences, allergies, and any existing care plan.",
        "CDC describes varied, nutrient-dense eating patterns and offers practical "
        "ways to include fruits and vegetables.",
    ),
    "smoking": (
        "Explore support for quitting",
        "If you smoke, read the CDC resource and consider discussing quitting support "
        "with a healthcare professional. If you do not smoke, this is educational only.",
        "CDC explains that quitting smoking has health benefits regardless of age "
        "or how long someone has smoked.",
    ),
    "supplements": (
        "Review supplement safety first",
        "If considering a supplement, ask a pharmacist or clinician to review it "
        "alongside your medicines. This plan does not select a product or dose.",
        "NIH ODS notes that supplements can interact with medicines and do not "
        "replace a varied eating pattern. Discuss their use with healthcare providers.",
    ),
}


async def build_plan(
    request: AdvisorRequest, research_client: TavilyResearch | None = None
) -> AdvisorResponse:
    sources = curated_sources(request.topics)
    if request.use_web_research:
        research = await (research_client or TavilyResearch()).research(request.topics)
    else:
        research = ResearchResult(
            status="not_requested",
            sources=sources,
            limitation="Web research was not requested. No external provider was contacted.",
        )
    actions = []
    for topic in request.topics:
        title, next_step, evidence = _COPY[topic]
        actions.append(
            PlanAction(
                id=f"learn-{topic}",
                topic=topic,
                title=title,
                next_step=next_step,
                evidence_summary=evidence,
                source_ids=[SOURCES[topic].id],
            )
        )
    limitations = [
        "This is a curated educational plan, not a personalized diagnosis or treatment plan.",
        "Actions follow your selected topic order; they are not ranked by predicted benefit.",
        "Effects are unmodeled, not zero. No physiological change is assumed from completing "
        "an action, and no confirmed measurements or experimental inputs are changed.",
        "Web queries contain fixed public-health topics only. Your profile is not sent "
        "to research providers. Retrieved content cannot change this reviewed plan.",
    ]
    if request.profile is not None and request.profile.age is not None:
        if request.profile.age < 18:
            limitations.append(
                "Age-specific targets are not assigned. A parent, guardian, or pediatric "
                "care team can help adapt educational activities to a young person's needs."
            )
    return AdvisorResponse(
        mascot_message="Let's choose a small step to explore! These ideas come from "
        "public-health guidance. You decide which fits your life.",
        actions=actions,
        sources=sources,
        research=research,
        limitations=limitations,
    )

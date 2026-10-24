"""Original authority sources checked on October 23, 2026 (Pacific time).

Only these reviewed page URLs may be sent to the extraction provider; no search
query is sent. Provider-written titles and retrieved instructions are never trusted
as clinical evidence. Adding a source requires reviewing the original page.
"""

from lifetwin.research.models import EvidenceSource, ResearchTopic

SOURCES: dict[ResearchTopic, EvidenceSource] = {
    "physical_activity": EvidenceSource(
        id="niddk-start-activity",
        topic="physical_activity",
        title="Tips for Starting Physical Activity",
        url="https://www.niddk.nih.gov/health-information/weight-management/"
        "tips-get-active/tips-starting-physical-activity",
        publisher="NIH National Institute of Diabetes and Digestive and Kidney Diseases",
    ),
    "sleep": EvidenceSource(
        id="cdc-about-sleep",
        topic="sleep",
        title="About Sleep",
        url="https://www.cdc.gov/sleep/about/",
        publisher="Centers for Disease Control and Prevention",
    ),
    "nutrition": EvidenceSource(
        id="cdc-healthy-eating",
        topic="nutrition",
        title="Healthy Eating Tips",
        url="https://www.cdc.gov/nutrition/features/healthy-eating-tips.html",
        publisher="Centers for Disease Control and Prevention",
    ),
    "smoking": EvidenceSource(
        id="cdc-quitting-smoking",
        topic="smoking",
        title="Benefits of Quitting Smoking",
        url="https://www.cdc.gov/tobacco/about/benefits-of-quitting.html",
        publisher="Centers for Disease Control and Prevention",
    ),
    "supplements": EvidenceSource(
        id="nih-supplements-consumer",
        topic="supplements",
        title="Dietary Supplements: What You Need to Know",
        url="https://ods.od.nih.gov/factsheets/WYNTK-Consumer/",
        publisher="NIH Office of Dietary Supplements",
    ),
}


def curated_sources(topics: list[ResearchTopic]) -> list[EvidenceSource]:
    return [SOURCES[topic].model_copy(deep=True) for topic in topics]

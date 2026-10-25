"""Health-document extraction contract (docs/document-upload.md).

The phone recognises the text on the device and sends only that text. The server
returns candidate values the person must confirm one by one; nothing is stored.
"""

from typing import Annotated, Literal

from pydantic import Field

from lifetwin.core.models import SCHEMA_VERSION, ApiModel

MAX_PAGES = 10
MAX_PAGE_CHARS = 12000
# A PDF the person chose to have Claude read (POST /api/documents/read).
MAX_PDF_BYTES = 10 * 1024 * 1024
MAX_PDF_PAGES = 20
MAX_PDF_BASE64_CHARS = 4 * -(-MAX_PDF_BYTES // 3)

# Model inputs use the survival model's own input names; the app maps them onto
# the profile it confirms (diabetes_diagnosed -> profile "diabetes").
ModelInputField = Literal[
    "height_cm", "weight_kg", "smoking_status", "diabetes_diagnosed", "hypertension_diagnosed"
]
# Shown to the person for information only; never a model input.
InformationField = Literal["blood_pressure", "hba1c", "ldl_cholesterol"]
DocumentField = Literal[
    "height_cm",
    "weight_kg",
    "smoking_status",
    "diabetes_diagnosed",
    "hypertension_diagnosed",
    "blood_pressure",
    "hba1c",
    "ldl_cholesterol",
]
MODEL_INPUTS: frozenset[str] = frozenset(ModelInputField.__args__)

Notice = Literal[
    # Lines about another person (spouse, family history) were left out.
    "other_person_skipped",
    # More than one patient's records: nothing is offered from this document.
    "multiple_patients",
    # The same field had different values on the same date: neither is offered.
    "conflicting_values",
    # Most of the text is not English; only English documents are read for now.
    "language_not_supported",
    # Some text looked garbled (blur, handwriting); those lines were skipped.
    "partly_unreadable",
]


class DocumentExtractRequest(ApiModel):
    # Recognised text, one string per page or photo, in order. Never the image.
    pages: list[Annotated[str, Field(max_length=MAX_PAGE_CHARS)]] = Field(
        min_length=1, max_length=MAX_PAGES
    )
    # The person's yes, for this document, to the active outside-AI provider reading the
    # (identifier-stripped) text; they must have been told and agreed on the phone.
    # Per provider: {"claude": true} or {"muse": true}. A bare true is the older app's
    # yes to Muse by Meta and never covers another provider.
    outside_ai_consent: bool | dict[Literal["claude", "muse"], bool] = False


class DocumentReadRequest(ApiModel):
    # The PDF itself, base64 (at most 10 MB decoded and 20 pages). Held in memory for this
    # request only, and sent to the documents provider only with the yes below.
    pdf_base64: str = Field(min_length=4, max_length=MAX_PDF_BASE64_CHARS)
    # The person's yes, for this document, to the documents provider reading the whole PDF:
    # {"claude": true}. Without it the PDF is sent nowhere.
    outside_ai_consent: dict[Literal["claude", "muse"], bool] = Field(default_factory=dict)


class DocumentCandidate(ApiModel):
    field: DocumentField
    use: Literal["model_input", "information"]
    # height_cm/weight_kg: number in cm/kg; smoking_status: never/former/current;
    # *_diagnosed: only ever true; blood_pressure: "128/82"; labs: number.
    value: float | bool | str
    unit: Literal["cm", "kg", "mmHg", "%", "mg/dL", "mmol/L"] | None = None
    # ISO date of the reading, or of the document when the line has none.
    date: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    date_basis: Literal["line", "document"] | None = None
    # The identifier-stripped line the value came from, for the read-back.
    source_text: str = Field(min_length=1, max_length=300)
    # Up to 10 recognised pages, or up to 20 pages of a PDF read by Claude.
    page: int = Field(ge=1, le=MAX_PDF_PAGES)
    # The heading the line sat under ("Vitals", "Assessment"), if any.
    section: str | None = Field(default=None, max_length=60)
    confidence: Literal["high", "medium", "low"]
    # parser, or the outside-AI provider that pointed at the line (with consent). A Claude
    # candidate's quote was found in the PDF's own text and read again by the parser.
    method: Literal["parser", "muse", "claude"] = "parser"


class DocumentExtractResponse(ApiModel):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    status: Literal["found", "nothing_found", "unreadable"]
    candidates: list[DocumentCandidate] = Field(default_factory=list, max_length=40)
    notices: list[Notice] = Field(default_factory=list, max_length=5)
    # How many identifiers (names, MRN, birth date, address, phone...) were removed.
    identifiers_removed: int = Field(ge=0)
    # not_requested: the parser was enough, or Muse is off for documents.
    # consent_required: Muse could read the messy lines if the person agrees.
    provider_status: Literal["not_requested", "consent_required", "used", "unavailable"] = (
        "not_requested"
    )
    limitations: list[str] = Field(
        default_factory=lambda: [
            "Every value is a suggestion until the person confirms it.",
            "Nothing from the document is stored. The text is discarded after this response.",
            "A missing diagnosis in a document does not mean the person does not have it.",
        ],
        max_length=5,
    )

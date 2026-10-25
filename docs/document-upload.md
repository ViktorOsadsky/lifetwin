# Health-document upload (Tracks B/C/D)

Decided at the [October 23 product meeting](https://github.com/ViktorOsadsky/lifetwin/blob/codex/d-product-vision/docs/meetings/2026-10-23-product-refinement.md)
(`docs/tech-stack.md`, "Health-document upload" row): offer upload at entry, alongside Apple Health and voice/text.
This is the design and contract. The app side is barebones: a working service and a test screen; a separate UI
session draws the real screens.

## Owner rulings this design follows

- History lives on the phone. The server stores nothing.
- Outside LLMs only after the person is told and agrees. Muse now, shown as **"Muse by Meta"**.
- No direct edits. A value is used only after a read-back confirmation ("Is this right?"). A "No" discards it and the
  person gives the right value by talking or typing to Mochi, the mascot. There is never a free-form edit field.

The binding rules in `MASTER_PLAN.md` ("Health-document intake (planned)") also apply:

- Every candidate carries its source page and section, measurement date, units and uncertainty.
- Conflicting records, old measurements, missing units and unreadable content get a clarification, never a guess.
- A diagnosis missing from a record is not a negative diagnosis. The server never sends `false` for a diagnosis.
- Upload is separate from Apple Health. Declining it, or a failure, keeps every confirmed value and offers a retry
  or talking or typing.

## What it does

1. The person scans a paper (camera), picks photos, or picks a PDF.
2. **On the phone**, Apple's Vision framework recognises the text. Nothing leaves the phone in this step.
3. The app sends **only the recognised text** to `POST /api/documents/extract`. The server removes identifiers, then a
   deterministic parser proposes candidate values. Muse by Meta may help with messy text only with consent (below).
4. The app asks "Is this document about you?". It then reads back each candidate in a compact way: value, units,
   date and the line it came from. Only "Yes, that's right" keeps it. "No, that's not right" drops it, and Mochi asks
   for that answer in the conversation, where the person corrects it by talking or typing.
5. Confirmed model inputs go into the conversation as an `import` (the same path as Apple Health), so the mascot skips
   those questions and asks only for what is still missing. Unconfirmed values are dropped.
6. The image, PDF and text are discarded as soon as extraction returns.

## Supported inputs and limits

| Input | How | Limit |
| --- | --- | --- |
| Paper, scanned | VisionKit document camera (`VNDocumentCameraViewController`): edge detection, auto-capture, perspective correction; several pages in one go | 10 pages |
| Photos | Photo library (`PHPickerViewController`): JPEG, PNG, HEIC | 10 photos, 20 MB each |
| PDF | Files (`UIDocumentPickerViewController`), read in place with PDFKit | 20 MB; the first 10 pages are read and the person is told if there were more. Password-protected PDFs are refused |

- A PDF page that already has a text layer (most patient-portal downloads) uses that text directly. Other pages are
  rendered at 2x and recognised with Vision.
- Vision runs `.accurate` with language correction, `en-US`. Each page's text is capped at 12,000 characters.
- Whole upload: at most 10 pages, about 30 seconds of recognition on the phone. The server request body is capped at
  384 KB for this route (the other routes keep 32 KB).
- English only for now. Other languages get a plain "I can only read English documents for now".

## Why a small Swift method channel, not a plugin

`app/ios/Runner/DocumentScanner.swift` (under 300 lines) does picking and recognition natively and returns only text
to Dart:

- **Bytes stay in memory.** `image_picker` and `file_picker` copy the chosen file into the app's temporary folder.
  The native pickers give image data in memory (camera, `PHPicker` data representation) and read PDFs in place from
  Files without copying.
- **No new dependency.** Vision, VisionKit and PDFKit ship with iOS. The maintained Flutter OCR plugin
  (`google_mlkit_text_recognition`) adds Google's ML Kit pods and does not run on Apple-silicon simulators; the Vision
  wrappers on pub.dev have little maintenance.
- **One boundary.** Dart never sees image bytes, so it cannot log or upload them by accident.

The channel `lifetwin/documents` has two methods. `scan` takes `source` (`camera`, `photos` or `pdf`), shows the
picker and returns `{pages: [String], page_count: int, truncated: bool}` or a coded error. `recognize` takes `bytes`
and `type` (`image` or `pdf`) and is used by tests with a synthetic document. Error codes are `cancelled`,
`camera_unavailable` (also on the simulator), `unsupported_type`, `too_large`, `password_protected`, `no_text` and
`failed`.

## The API

`POST /api/documents/extract`. It is stateless, no storage, no logs. Schemas:
[`contracts/documents.extract.request.schema.json`](../contracts/documents.extract.request.schema.json) and
[`contracts/documents.extract.schema.json`](../contracts/documents.extract.schema.json); source models in
`server/lifetwin/documents/models.py`.

Request:

```json
{ "pages": ["recognised text of page 1", "page 2"], "outside_ai_consent": false }
```

`pages` holds 1 to 10 strings of at most 12,000 characters each. `outside_ai_consent` must be an explicit `true`
for Muse.

Response, `200`:

```json
{
  "schema_version": "1.0",
  "status": "found",
  "candidates": [
    {"field": "weight_kg", "use": "model_input", "value": 82.6, "unit": "kg",
     "date": "2026-09-14", "date_basis": "document",
     "source_text": "BP 138/86  Pulse 72  Wt 182 lb  Ht 5' 6\"", "page": 1,
     "section": "Vitals", "confidence": "high", "method": "parser"},
    {"field": "blood_pressure", "use": "information", "value": "138/86", "unit": "mmHg",
     "date": "2026-09-14", "date_basis": "document", "source_text": "...", "page": 1,
     "section": "Vitals", "confidence": "high", "method": "parser"}
  ],
  "notices": ["other_person_skipped"],
  "identifiers_removed": 6,
  "provider_status": "not_requested",
  "limitations": ["Every value is a suggestion until the person confirms it.", "..."]
}
```

| Field | Use | Value, unit |
| --- | --- | --- |
| `height_cm`, `weight_kg` | model input | number in cm or kg; the original wording is in `source_text` |
| `smoking_status` | model input | `never`, `former` or `current`; "non-smoker" alone is ambiguous and gives nothing |
| `diabetes_diagnosed`, `hypertension_diagnosed` | model input | only `true`; absence or negation gives nothing, never `false` |
| `blood_pressure` | information | `"138/86"`, `mmHg`; a reading is not a diagnosis |
| `hba1c`, `ldl_cholesterol` | information | number, `%` or `mg/dL`/`mmol/L`; a lab value is never a diagnosis |

- `status`: `found`; `nothing_found` (readable, but no candidates); `unreadable` (almost nothing legible).
- `date` is the reading's own date when its line has one (`date_basis: "line"`). Otherwise it is the document date
  (`"document"`), taken by label priority: visit/service date, collection date, discharge date, report date, printed or
  fill date. Admission dates and birth dates are never used.
- `notices`: `other_person_skipped`, `multiple_patients` (nothing is offered), `conflicting_values`,
  `language_not_supported`, `partly_unreadable`.
- `page` and `section` give where the line was (`section` is the heading it sat under, such as "Vitals").
- `confidence` is the uncertainty: `high` for a labelled value with written units and a date; `medium` when the
  units were inferred from the size of the number (LDL) or no date was found; `low` for Muse.
- A labelled value with no units ("Height 66") is not offered. Mochi asks, since the server cannot tell inches from
  centimetres.
- `provider_status`: `not_requested`, `consent_required` (Muse could read lines the parser could not, if the person
  agrees), `used` or `unavailable`.
- Errors use `error.schema.json`. `422` for more than 10 pages, a page over 12,000 characters, or a non-boolean consent.
  `413` for a body over 384 KB. `429` and `504` come from the shared request budget.

### Extraction rules (deterministic parser)

1. **Strip identifiers first**, before anything else reads the text. Whole lines labelled name, patient, DOB or birth
   date, MRN, account, member or insurance ID, Rx number, SSN, address and phone are replaced with `[removed]`. Inline
   phone numbers, emails, SSN-like and MRN-like numbers, street addresses and city/state/ZIP lines are replaced too.
   Names after "Dr.", "Mr.", "Mrs.", "Ms." or "Dear", and every later use of a removed patient name, become `[name]`.
   Only the stripped text is used from then on; `source_text` comes from it.
2. **Sections.** A heading about another person (spouse, partner, family history, a relative) starts a skipped section,
   which ends at the next heading about the patient. Lines naming a relative are skipped.
3. **Measurements** (height, weight, blood pressure, A1c, LDL) need a label and a plausible value with units: height
   100-250 cm, weight 25-300 kg, systolic 70-260 above diastolic 40-150. Goal, target, ideal, change, loss/gain, birth and
   previous values are skipped. Garbled values (`1?4 lb`) are skipped.
4. **Diagnoses** come only from explicit wording (hypertension, HTN, I10; diabetes mellitus type 1/2, T2DM, DM2,
   E10/E11) on a line under, or starting with, Assessment, Assessment and Plan, Diagnosis or Diagnoses, Discharge
   Diagnoses, Problem List, Active Problems, Past Medical History/PMH or Impression. The line must have no negation,
   uncertainty or other-person cue (no, denies, rule out, r/o, screening, risk, possible, suspected, `?`, borderline,
   pre-, prediabetes, gestational, family history). Medication indications ("metformin for diabetes") and lab values
   are never diagnoses.
5. **Smoking** comes only from lines about the patient's smoking or tobacco: former (former, ex-smoker, quit), never,
   current (current, smokes, every day, ppd).
6. **Conflicts.** The same field with different values keeps the latest dated value. Equal or missing dates drop both
   and add `conflicting_values`. Blood pressure keeps up to 6 distinct readings, newest first.
7. **Two patients.** Two different names on "Patient:" or "Name:" lines mean nothing is offered (`multiple_patients`).

### Muse by Meta (optional, consented)

- Muse is used only if all of these hold: the request has `outside_ai_consent: true`, the server is configured for
  Muse (`LLM_PROVIDER=chat_completions`), and `DOCUMENT_MUSE_ENABLED=true`, which is **on by default** (owner ruling: Muse on, with consent;
  Claude replaces it later by configuration). Set it to `false` to keep document text away from Muse entirely.
- It runs only when the parser found no model inputs, or some lines could not be read.
- Muse receives the identifier-stripped text only, never the image.
- Muse can only point at evidence. Each answer must quote text that appears verbatim in the stripped document. The
  number must appear in the quote with a matching label. The quote passes the same plausibility, negation,
  other-person and explicit-diagnosis checks as the parser.
- Its candidates are marked `method: "muse"` and `confidence: "low"`. Where the parser and Muse both find a field, the
  parser's value wins.
- When consent is missing and Muse would help, the response says `provider_status: "consent_required"`. The app may
  then ask: "Some lines were hard to read. May Muse by Meta, an AI service, read the words from your document to help?
  Names and other details that identify you are removed first." On a yes, it sends the same text again with consent.
  The text is still only in memory.

## Privacy boundary

| Where | What exists | How long |
| --- | --- | --- |
| Phone, native | image or PDF bytes, rendered pages | until recognition returns; never written to disk by LifeTwin |
| Phone, Dart | recognised text | until the extract response, or a consent answer; then dropped |
| Network | recognised text (TLS in deployment) | one request |
| Server | text, then the stripped text | the request; never logged or stored. The middleware logs only an exception type |
| Muse (consented) | stripped text | one request; the provider's own retention applies (open question) |
| Phone, kept | confirmed values (and confirmed information notes) | the session today; history on the phone later |

- Documents and identifiers never go into logs, research (Tavily) queries, fixtures or Git. The corpus in
  `server/tests/data/documents/` is fully synthetic.
- The text in a document is data, never instructions. The parser does not follow it, and Muse is told to treat it
  as data.
- The intro tells the person: "The words from your document are sent to LifeTwin to find the numbers, then thrown
  away. Nothing is kept unless you say it's right."

## Failure modes

| Case | Behaviour |
| --- | --- |
| Blurry photo, glare, cut-off page | Garbled lines are skipped (`partly_unreadable`). If almost nothing is legible: `unreadable`, and the app offers "Try another photo" or "Tell me instead". Tips: flat surface, good light, whole page in view. The document camera's auto-capture helps |
| Handwriting | Vision reads neat print only; handwritten values usually come out garbled and are skipped. Never guessed |
| Non-English | `language_not_supported`; nothing extracted; continue by voice or text |
| Multiple patients, or another person's document | Two patient names give `multiple_patients` and nothing. A single other person's document cannot be detected (names are stripped), so the first question is always "Is this document about you?" A "No" discards everything |
| Spouse or family data in the same document | Those sections and lines are skipped (`other_person_skipped`) |
| Old values | The date is always read back. A reading more than a year old, or with no date, is read back with "That was in March 2019. Is it still right today?" The person decides; the selected model's eligibility rules still apply |
| Missing units | Not offered; Mochi asks |
| Conflicting records | The same field with two values on the same date (or no dates) is not offered (`conflicting_values`). The app says "Your document shows two different weights" and Mochi asks |
| Conflicts with Apple Health or earlier answers | The newer confirmation replaces the earlier one. The UI should mention the earlier value in the read-back |
| Server down, timeout, 429 | "I couldn't read it right now." Retry, or continue by voice or text. Values confirmed earlier are kept |
| Decline upload | Apple Health or conversation; nothing changes |

Values confirmed earlier (Apple Health, earlier answers) are never lost: an upload only adds confirmations.

## Accessibility for 65+

- One question per screen, large type (24 pt or more for read-backs), 72 pt buttons, and an undo with "Go back". There
  are no time limits.
- The document camera captures by itself, so a tremor does not need to hit a shutter button. The camera, photos and
  PDF choices have plain names: "Scan a paper", "Choose a photo", "Choose a PDF".
- Read-backs are full sentences in everyday units. Example: "Your visit summary from September 14, 2026 says you weigh
  182 pounds. Is this right?" Information items say what they are: "It also shows a blood pressure reading of 138 over
  86. I'll keep it as a note; it doesn't change your forecast." A1c and LDL get a one-line explanation.
- The source line is shown in large print, so it can be checked against the paper.
- Progress is spoken and shown ("Reading page 2 of 3…"). VoiceOver labels are on every control, and the mascot can
  speak the read-back when voice is on.
- Errors say what to do next, never just "failed".

## What the UI session must build

- **Entry choice:** Upload a document, Use Apple Health, or Talk or type. Upload is offered first, not after a long
  intake.
- **Upload intro**, with the privacy sentence and three source buttons.
- **Progress** while recognising and extracting.
- **"Is this document about you?"**
- **Candidate read-back**, one per screen and compact: value in everyday units, date, the source line in large print;
  "Yes, that's right", "No, that's not right", "Go back". There is no edit field. "No" hands that answer to Mochi.
- **Muse consent prompt**, shown only on `consent_required`.
- **Summary**, then hand off to the conversation with the confirmed values. The conversation asks only for the rest.
- **Failure screens:** unreadable, not English, more than one person, too large or too many pages, server
  unavailable. Each offers retry and "Tell me instead".
- **A source label** ("from your document") on confirmed values in the forecast.

The barebones `DocumentUploadScreen` (`app/lib/documents/`) shows the logic and wording but not the look.

## What is built

| Piece | Where |
| --- | --- |
| Vision OCR and pickers (method channel `lifetwin/documents`) | `app/ios/Runner/DocumentScanner.swift`, registered in `AppDelegate.swift`; `NSCameraUsageDescription` in `Info.plist` |
| Dart service: scan → text → extract → candidates; text dropped after the answer | `app/lib/documents/document_ocr.dart`, `document_extract.dart`, `document_upload.dart` |
| Confirmation logic: "about you", one-by-one yes/no, go back, and the mapping to profile names (`diabetes_diagnosed` → `diabetes`) | `DocumentConfirmation`, `DocumentImportResult` in `document_upload.dart` |
| Minimal screen and Room entry ("Upload a document", beside "Use my Apple Health") | `document_screen.dart`, `room/room_screen.dart`, `main.dart` |
| Conversation import, labelled as a document (`import_source: "document"`) so Mochi says "from your document", not Apple Health | `VoiceOnboardingController.importDocument`, `server/lifetwin/onboarding/` |
| Server endpoint, identifier stripping, parser, optional Muse grounding | `server/lifetwin/documents/` |
| Corpus (9 synthetic documents, 69 single-line cases) written before the parser | `server/tests/data/documents/` |
| Tests | `server/tests/test_documents.py`, `app/test/document_upload_test.dart`, `app/integration_test/document_ocr_sim_test.dart` |

On the iPhone 17 simulator, real Vision OCR read a synthetic visit summary drawn at run time. The vitals row came
back as one line, and the keyless server on port 8096 extracted all five expected candidates from it. Vision read
"182 lb" as "182 |b", so the parser accepts `|b` and `Ib` after a weight. A hand-built PDF page went through the
render-and-recognise path. The document camera reports `camera_unavailable` on the simulator. Photo, PDF and camera
pickers are native sheets and were not driven by the test.

## Not done yet, and open questions

- Showing the "Document" source label in the forecast screens (the source is recorded: `recordImport(..., source: 'document')` and a `document` history entry).
- Storing confirmed information notes (blood pressure, A1c, LDL) on the phone, once local history exists.

- **Ruled:** document text may go to Muse with the person's consent (owner, 2026-10-24). Muse's retention terms are
  still unverified; the consent copy must not claim any retention promise until they are checked.
- **Tier-1:** should confirmed information notes (blood pressure, labs) be kept in on-phone history, and for how long?
- The server must run behind TLS in deployment, since the text crosses the network.
- On-device validation: the real photo library, Files and document camera, with real paper documents and older
  users. The simulator test uses a rendered synthetic document.

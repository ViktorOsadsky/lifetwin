# Synthetic portal upload demo

These are **invented MyChart-style portal records for demonstration**, not real MyChart exports, patient records or medical advice. They use original LifeTwin demo styling without Epic logos, credentials or endorsement. Every page displays SYNTHETIC DEMO DATA and identifies the fictional clinic/person.

| Uploadable PDF | Matching text | What to demonstrate |
| --- | --- | --- |
| [After-visit summary](../../output/pdf/demo-visit-summary.pdf) | [Text](../../demo/health-records/demo-visit-summary.txt) | Height, weight, smoking history and explicit diagnoses are candidates to confirm; BP/A1c/LDL are informational readings |
| [Lab report](../../output/pdf/demo-lab-report.pdf) | [Text](../../demo/health-records/demo-lab-report.txt) | A1c/LDL alone do not fill a health profile or establish a diagnosis; Mochi still needs the missing inputs |
| [Historical visit](../../output/pdf/demo-historical-visit.pdf) | [Text](../../demo/health-records/demo-historical-visit.txt) | The 2023 measurements differ from the first record; confirm whether old values remain right today and preserve previously confirmed answers |

## Suggested sequence

1. Use an empty demo profile and choose the app's document-upload entry. Import the after-visit PDF from Files, confirm that it is about the fictional demo person, and review values one at a time. Saying No must drop the candidate, not silently save it.
2. Continue through the existing conversation for unsupported/missing inputs such as sleep and recreational activity. The document alone does not complete the model's required profile. No demo record includes a survival probability or invented forecast.
3. Try the labs-only PDF in another empty demo session. Do not infer diabetes from a test number or absence of a diagnosis list. Informational readings are not direct model inputs; persistence depends on the current app/repository implementation.
4. With the first record's 165 cm / 78 kg values already confirmed, upload the historical record (167 cm / 90 kg). Show the measurement date, retain confirmation and any current conflict-resolution behavior. The old record is not permission to overwrite the current profile.

Local text extraction tests cover these candidates and the PDF text layer separately. That does **not** prove iPhone Vision OCR, Files delivery, read-back UI or live-provider behavior. Validate those on the actual demo phone before presenting the flow as working end to end.

## Rebuild

Run `python tools/build_demo_health_records.py` in an environment with `reportlab`. It makes the three PDFs in `output/pdf/` and matching text fixtures in `demo/health-records/`. Sources contain only invented data and make no network calls. PDFs are static, selectable-text artifacts, not fillable medical forms. Do not replace these fixtures with real health data.

## Validation and handoff

All three one-page PDFs were rendered with Poppler and visually checked. Their extracted PDF text and matching text fixtures produced the same 8 / 2 / 4 candidates, including dates and information-only lab/BP status, through the existing keyless document extractor. The four new fixture/evidence-label tests pass; Ruff and `git diff --check` pass. The broader existing document test module could not collect in this checkout's lightweight virtualenv because `h5py` (an unrelated prediction import) is absent; full CI and native iPhone OCR remain separate checks. No server/model contract, provider or UI changed.

The associated synthetic usability dataset is described in [voice-usability-demo.md](voice-usability-demo.md). Keep real study results separate.

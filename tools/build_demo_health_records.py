"""Build fictional portal-style upload PDFs and matching plain-text fixtures.

Artifact tooling only: requires reportlab. No real patient data or network calls.
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

ROOT = Path(__file__).resolve().parents[1]
RECORDS = [
    {
        "id": "demo-visit-summary",
        "title": "After-visit summary",
        "date": "2026-10-20",
        "purpose": "Complete supported document fields; confirmation is still required.",
        "sections": [
            ("Vitals", ["Height: 165 cm", "Weight: 78 kg", "Blood pressure: 132/78 mmHg"]),
            ("Social History", ["Former smoker, quit 2010"]),
            ("Problem List", ["Type 2 diabetes mellitus", "Essential hypertension"]),
            ("Lab Results", ["Hemoglobin A1c: 6.8 %", "LDL Cholesterol: 122 mg/dL"]),
        ],
    },
    {
        "id": "demo-lab-report",
        "title": "Laboratory results",
        "date": "2026-10-21",
        "purpose": "Lab readings only; absence of a diagnosis is not a negative diagnosis.",
        "sections": [
            ("Lab Results", ["Hemoglobin A1c: 6.6 %", "LDL Cholesterol: 118 mg/dL"]),
            (
                "Report Notes",
                [
                    "No height, weight, smoking history or diagnosis list is included in this sample."
                ],
            ),
        ],
    },
    {
        "id": "demo-historical-visit",
        "title": "Historical visit summary",
        "date": "2023-06-15",
        "purpose": "Older measurements differ from the first demo record; check the date and confirm current values.",
        "sections": [
            ("Vitals", ["Height: 167 cm", "Weight: 90 kg", "Blood pressure: 128/76 mmHg"]),
            ("Social History", ["Former smoker, quit 2010"]),
            (
                "Record Notes",
                ["This is a historical sample, not the patient's current measurement."],
            ),
        ],
    },
]


def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#CFD7E4"))
    canvas.line(42, 45, 570, 45)
    canvas.setFillColor(colors.HexColor("#526176"))
    canvas.setFont("Helvetica", 8)
    canvas.drawString(
        42,
        31,
        "SYNTHETIC DEMO DATA | Not a real health record | Not affiliated with Epic or MyChart",
    )
    canvas.drawRightString(570, 19, f"Page {doc.page}")
    canvas.restoreState()


def build():
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="DemoTitle",
            fontName="Helvetica-Bold",
            fontSize=24,
            leading=29,
            textColor=colors.HexColor("#173558"),
            spaceAfter=7,
        )
    )
    styles.add(
        ParagraphStyle(
            name="DemoHeading",
            fontName="Helvetica-Bold",
            fontSize=12,
            leading=16,
            textColor=colors.HexColor("#173558"),
            spaceBefore=13,
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="DemoBody",
            fontName="Helvetica",
            fontSize=11,
            leading=16,
            textColor=colors.HexColor("#263344"),
            alignment=TA_LEFT,
        )
    )
    output = ROOT / "output" / "pdf"
    text_dir = ROOT / "demo" / "health-records"
    output.mkdir(parents=True, exist_ok=True)
    text_dir.mkdir(parents=True, exist_ok=True)
    for record in RECORDS:
        lines = [
            "SYNTHETIC DEMO DATA - NOT A REAL HEALTH RECORD",
            "LifeTwin Demonstration Clinic",
            record["title"],
            "Patient: Rosa Sample (fictional)",
            "DOB: 1960-04-12 | Sex: Female",
            "MRN: DEMO-0001",
            f"Date of service: {record['date']}",
        ]
        for title, rows in record["sections"]:
            lines.extend(["", title, *rows])
        lines.extend(
            ["", "Not affiliated with Epic or MyChart. All identities and values are invented."]
        )
        (text_dir / f"{record['id']}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        pdf = output / f"{record['id']}.pdf"
        doc = SimpleDocTemplate(
            str(pdf),
            pagesize=(612, 792),
            rightMargin=42,
            leftMargin=42,
            topMargin=38,
            bottomMargin=64,
            title=f"SYNTHETIC DEMO | {record['title']}",
            author="LifeTwin demo fixture",
            invariant=1,
        )
        story = []
        banner = Table(
            [
                [
                    Paragraph(
                        "<b>SYNTHETIC DEMO DATA - NOT A REAL HEALTH RECORD</b>", styles["DemoBody"]
                    )
                ]
            ],
            colWidths=[528],
        )
        banner.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF0C5")),
                    ("BOX", (0, 0), (-1, -1), 0.8, colors.HexColor("#B59444")),
                    ("TOPPADDING", (0, 0), (-1, -1), 10),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
                ]
            )
        )
        story += [
            banner,
            Spacer(1, 20),
            Paragraph("LifeTwin Demonstration Clinic", styles["DemoBody"]),
            Spacer(1, 5),
            Paragraph(record["title"], styles["DemoTitle"]),
        ]
        info = Table(
            [
                [Paragraph(line, styles["DemoBody"])]
                for line in [
                    "Patient: Rosa Sample (fictional)",
                    "DOB: 1960-04-12 | Sex: Female",
                    "MRN: DEMO-0001",
                    f"Date of service: {record['date']}",
                ]
            ],
            colWidths=[528],
        )
        info.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F1F5FA")),
                    ("TOPPADDING", (0, 0), (-1, -1), 5),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ]
            )
        )
        story.append(info)
        for title, rows in record["sections"]:
            story.append(Paragraph(title, styles["DemoHeading"]))
            story.extend(Paragraph(row, styles["DemoBody"]) for row in rows)
        story += [
            Spacer(1, 15),
            Paragraph(f"<b>Demo purpose:</b> {record['purpose']}", styles["DemoBody"]),
        ]
        doc.build(story, onFirstPage=footer, onLaterPages=footer)
        print(pdf.relative_to(ROOT))


if __name__ == "__main__":
    build()

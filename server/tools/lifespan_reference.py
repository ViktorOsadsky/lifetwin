"""Reference implementation of the LifeTwin expected-lifespan research prototype.

A rough, proof-of-concept estimate behind the app's one-time lifespan reveal
(TwinRepository.lifespanEstimate; owner override 2026-10-24). See docs/lifespan-estimate.md.

Method (relative-risk-adjusted period life table):

* Population baseline: CDC/NCHS United States Life Tables, 2024 (NVSR 75-5), by sex,
  single years of age 0-99 plus an open 100+ interval. Within each year deaths are
  spread uniformly (the table's own a=0.5 convention); past 100 the hazard is constant
  at 1/e100, which reproduces the table's T100 exactly.
* Personal relative hazard: from the packaged Cox model, using every term except age and
  sex (both are already in the sex-specific life table). The reference is the
  log-mean-hazard of NHANES training profiles of the same sex and similar age, so the
  average hazard among people of your age and sex is HR = 1.
* Age-band calibration: per sex and age band, one multiplicative hazard factor k so the
  mean life-table 5-year survival of the NHANES training profiles in that band equals the
  Cox model's own mean 5-year survival. Ages 18-34 and 80-85 use the nearest band's k
  (held constant). The adjusted log HR is log HR + log k.
* Proportional hazards: within the life-table year starting at age y the person's
  survival is ((1 - v*q_y) / (1 - u*q_y)) ** HR_y, and above 100 it is exp(-HR*t/e100).
  HR = 1 reproduces the table exactly.
* Attenuation: log HR is held for the model's validated 5 years, then halves every
  `half_life` years (default 20; None turns attenuation off).

Pure-Python math on purpose: app/lib/twin/lifespan.dart performs the same operations in
the same order, and golden tests require the two to agree to 1e-9.

Commands:
    python server/tools/lifespan_reference.py extract-cdc MALE.xlsx FEMALE.xlsx
    python server/tools/lifespan_reference.py build      # Dart data file + golden vectors
    python server/tools/lifespan_reference.py validate   # validation tables (markdown)
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import json
import math
import struct
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]
LIFE_TABLE_CSV = ROOT / "server/tools/data/us_life_table_2024.csv"
MODEL_JSON = ROOT / "model_handoff/lifetwin_on_device/assets/model.json"
SUPPORT_REFERENCE = ROOT / "model_handoff/lifetwin_on_device/assets/support_reference.f64.gz"
DART_DATA = ROOT / "app/lib/twin/lifespan_data.dart"
GOLDEN = ROOT / "app/test/twin/lifespan_golden.json"

LIFE_TABLE_SOURCE = (
    "Arias E, Xu J, Tejada-Vera B. United States Life Tables, 2024. National Vital "
    "Statistics Reports vol 75 no 5. Hyattsville, MD: NCHS; 2026 Aug 25. "
    "Tables 2 (males) and 3 (females)."
)
LIFE_TABLE_URLS = (
    "https://www.cdc.gov/nchs/data/nvsr/nvsr75/nvsr75-05.pdf",
    "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/75-05/Table02.xlsx",
    "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/75-05/Table03.xlsx",
)

VALIDATED_YEARS = 5.0
DEFAULT_HALF_LIFE = 20.0
REFERENCE_BANDWIDTH = 5.0
CHECKED_AGES = (35, 79)
PROFILE_AGES = (18, 85)  # the health score's extrapolated range (twin_model.dart)
# Age bands for the per-band hazard calibration (assessment age; outside, the nearest band).
CALIBRATION_BANDS = ((35, 44), (45, 54), (55, 64), (65, 74), (75, 79))
DAYS_PER_YEAR = 365.2425
MILESTONES = (80, 90, 100)
CURVE_END_AGE = 110
# Model columns used for the personal hazard: everything except age_decade and female.
EXCLUDED_FEATURES = ("age_decade", "female")
SEXES = {1: "male", 2: "female"}


# --------------------------------------------------------------------------- data


def load_life_table(path: Path = LIFE_TABLE_CSV) -> dict[str, dict[str, list[float] | float]]:
    """{'male': {'qx': [q0..q99], 'e100': e, 'ex': [published e0..e100]}, 'female': ...}."""
    rows: dict[str, list[dict[str, str]]] = {"male": [], "female": []}
    with path.open() as f:
        for row in csv.DictReader(line for line in f if not line.startswith("#")):
            rows[row["sex"]].append(row)
    out: dict[str, dict[str, list[float] | float]] = {}
    for sex, table in rows.items():
        table.sort(key=lambda r: int(r["age"]))
        if [int(r["age"]) for r in table] != list(range(101)):
            raise ValueError(f"{sex} life table must cover ages 0-100")
        out[sex] = {
            "qx": [float(r["qx"]) for r in table[:100]],
            "e100": float(table[100]["ex"]),
            "ex": [float(r["ex"]) for r in table],
            "lx": [float(r["lx"]) for r in table],
        }
    return out


def load_model(path: Path = MODEL_JSON) -> dict:
    return json.loads(path.read_text())


def risk_columns(model: dict) -> list[int]:
    names = model["encoded_features"]
    if names[0] != "age_decade" or names[8] != "female" or len(names) != 17:
        raise ValueError("Unexpected model feature layout; review lifespan_reference.py")
    return [i for i, name in enumerate(names) if name not in EXCLUDED_FEATURES]


def encode_risk(profile: dict) -> list[float]:
    """The model's encoding (lib/src/model.dart _encode) minus age_decade and female."""
    bmi = float(profile["bmi"])
    sleep = float(profile["sleep_hours"])
    smoking = profile["smoking_status"]
    health = profile["general_health"]
    return [
        max(23 - bmi, 0) / 5,
        max(bmi - 27, 0) / 5,
        float(max(7 - sleep, 0)),
        float(max(sleep - 8, 0)),
        math.log(1 + float(profile["vigorous_recreation_min_week"])) / math.log(76),
        math.log(1 + float(profile["moderate_recreation_min_week"])) / math.log(151),
        (float(profile["sedentary_min_day"]) - 360) / 120,
        1.0 if smoking == 1 else 0.0,
        1.0 if smoking == 2 else 0.0,
        float(profile["diabetes_diagnosed"]),
        float(profile["hypertension_diagnosed"]),
        *[1.0 if health == level else 0.0 for level in (2, 3, 4, 5)],
    ]


REQUIRED = (
    "age", "sex_nhanes", "bmi", "sleep_hours", "vigorous_recreation_min_week",
    "moderate_recreation_min_week", "sedentary_min_day", "smoking_status",
    "diabetes_diagnosed", "hypertension_diagnosed", "general_health",
)  # fmt: skip


def check_profile(profile: dict) -> None:
    missing = [k for k in REQUIRED if profile.get(k) is None]
    if missing:
        raise ValueError(f"missing inputs: {missing}")
    for key in REQUIRED:
        value = profile[key]
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
        ):
            raise ValueError(f"{key} must be a finite number")
    if profile["sex_nhanes"] not in (1, 2) or profile["smoking_status"] not in (0, 1, 2):
        raise ValueError("unsupported category")
    if profile["general_health"] not in (1, 2, 3, 4, 5):
        raise ValueError("unsupported category")
    if profile["diabetes_diagnosed"] not in (0, 1) or profile["hypertension_diagnosed"] not in (
        0,
        1,
    ):
        raise ValueError("unsupported category")
    if not PROFILE_AGES[0] <= profile["age"] <= PROFILE_AGES[1]:
        raise ValueError(f"age must be {PROFILE_AGES[0]}-{PROFILE_AGES[1]}")


def risk_score(encoded: list[float], coefficients: list[float]) -> float:
    total = 0.0
    for x, b in zip(encoded, coefficients, strict=True):
        total += b * x
    return total


def read_support(path: Path = SUPPORT_REFERENCE) -> list[list[float]]:
    raw = gzip.decompress(path.read_bytes())
    values = struct.unpack(f"<{len(raw) // 8}d", raw)
    return [list(values[i : i + 17]) for i in range(0, len(values), 17)]


def build_reference_scores(model: dict, support: list[list[float]]) -> dict[str, list[float]]:
    """Per sex, for integer ages 35..79: log of the kernel-weighted mean of exp(risk score)
    over NHANES training profiles (Gaussian kernel on age, bandwidth 5 years).

    Log-mean-exp, not the score of the mean profile: life-table death rates are the
    average hazard of everyone that age, so HR = 1 must mean "average hazard", which by
    Jensen's inequality is higher than the hazard of the average profile.
    """
    cols = risk_columns(model)
    coefs = [model["coefficients"][c] for c in cols]
    out: dict[str, list[float]] = {}
    for sex_code, sex in SEXES.items():
        rows = [r for r in support if (r[8] == 1.0) == (sex_code == 2)]
        ages = [55 + 10 * r[0] for r in rows]
        scores = [risk_score([r[c] for c in cols], coefs) for r in rows]
        shift = max(scores)
        table = []
        for age in range(CHECKED_AGES[0], CHECKED_AGES[1] + 1):
            num = den = 0.0
            for a, s in zip(ages, scores, strict=True):
                k = math.exp(-0.5 * ((a - age) / REFERENCE_BANDWIDTH) ** 2)
                num += k * math.exp(s - shift)
                den += k
            table.append(shift + math.log(num / den))
        out[sex] = table
    return out


def support_rows(model: dict, support: list[list[float]]) -> list[dict]:
    """Training profiles as (sex, whole age, risk score, full centred Cox score)."""
    cols = risk_columns(model)
    coefs = [model["coefficients"][c] for c in cols]
    beta, center = model["coefficients"], model["feature_center"]
    rows = []
    for r in support:
        full = sum(b * (x - c) for b, x, c in zip(beta, r, center, strict=True))
        age = 55 + 10 * r[0]
        if abs(age - round(age)) > 1e-6:
            raise ValueError("support ages are expected to be whole years")
        rows.append({
            "sex": "female" if r[8] == 1.0 else "male",
            "age": float(round(age)),
            "risk": risk_score([r[c] for c in cols], coefs),
            "full": full,
        })  # fmt: skip
    return rows


def five_year_survival(qx: list[float], age: int, log_hr: float) -> float:
    """Life-table survival from whole `age` to age + 5 (no attenuation inside 5 years)."""
    hr = math.exp(log_hr)
    s = 1.0
    for y in range(age, age + 5):
        s *= math.pow(1 - qx[y], hr)
    return s


def band_index(age: float) -> int:
    """Calibration band for an assessment age; nearest band outside 35-79."""
    for i, (_, hi) in enumerate(CALIBRATION_BANDS):
        if age < hi + 1:
            return i
    return len(CALIBRATION_BANDS) - 1


def build_band_adjustment(
    model: dict,
    life_table: dict,
    reference: dict[str, list[float]],
    rows: list[dict],
) -> dict[str, list[float]]:
    """Per sex, per band: log k such that mean life-table S5 (HR x k) == mean Cox S5."""
    s0_5 = model["baseline_survival"][4]
    out: dict[str, list[float]] = {}
    for sex in ("male", "female"):
        qx = life_table[sex]["qx"]
        logs = []
        for lo, hi in CALIBRATION_BANDS:
            sel = [r for r in rows if r["sex"] == sex and lo <= r["age"] <= hi]
            target = sum(s0_5 ** math.exp(r["full"]) for r in sel) / len(sel)
            lhrs = [
                (int(r["age"]), r["risk"] - reference_score(reference[sex], r["age"])) for r in sel
            ]

            def mean_s5(c: float, lhrs=lhrs, qx=qx) -> float:
                return sum(five_year_survival(qx, a, lhr + c) for a, lhr in lhrs) / len(lhrs)

            lo_c, hi_c = -3.0, 3.0  # mean S5 falls as c rises
            for _ in range(100):
                mid = 0.5 * (lo_c + hi_c)
                if mean_s5(mid) > target:
                    lo_c = mid
                else:
                    hi_c = mid
            logs.append(0.5 * (lo_c + hi_c))
        out[sex] = logs
    return out


class Inputs:
    """Everything the calculation needs, loaded once."""

    def __init__(self) -> None:
        self.model = load_model()
        self.life_table = load_life_table()
        self.columns = risk_columns(self.model)
        self.coefficients = [self.model["coefficients"][c] for c in self.columns]
        support = read_support()
        self.reference = build_reference_scores(self.model, support)
        self.rows = support_rows(self.model, support)
        self.band_log_adjustment = build_band_adjustment(
            self.model, self.life_table, self.reference, self.rows
        )


# --------------------------------------------------------------------------- math


def reference_score(table: list[float], age: float) -> float:
    """Linear interpolation over integer ages 35..79, held flat outside (ages 18-34, 80-85)."""
    lo, hi = CHECKED_AGES
    if age <= lo:
        return table[0]
    if age >= hi:
        return table[-1]
    i = int(math.floor(age))
    frac = age - i
    return table[i - lo] + frac * (table[i + 1 - lo] - table[i - lo])


def log_hazard_ratio(inputs: Inputs, profile: dict, adjusted: bool = True) -> float:
    """log HR versus same-sex, same-age peers; plus the band's log k when `adjusted`."""
    check_profile(profile)
    sex = SEXES[profile["sex_nhanes"]]
    age = float(profile["age"])
    score = risk_score(encode_risk(profile), inputs.coefficients)
    lhr = score - reference_score(inputs.reference[sex], age)
    if adjusted:
        lhr += inputs.band_log_adjustment[sex][band_index(age)]
    return lhr


def attenuation(years_from_now: float, half_life: float | None) -> float:
    if half_life is None or years_from_now <= VALIDATED_YEARS:
        return 1.0
    return math.pow(0.5, (years_from_now - VALIDATED_YEARS) / half_life)


def estimate(
    qx: list[float],
    e100: float,
    age: float,
    log_hr: float,
    half_life: float | None = DEFAULT_HALF_LIFE,
) -> dict:
    """Survival from exact `age` under hazard HR(t) * mu_population(age + t)."""
    if not (1.0 <= age < 100.0) or not math.isfinite(log_hr):
        raise ValueError("age must be in [1, 100) and log_hr finite")
    if half_life is not None and not half_life > 0:
        raise ValueError("half_life must be positive or None")
    first = int(math.floor(age))
    survival = 1.0  # survival to the start of the current piece
    mean = 0.0  # integral of S dt  = life expectancy
    second = 0.0  # integral of t S dt
    curve = [(age, 1.0)]
    targets = [0.75, 0.5, 0.25]
    quantiles: list[float] = []
    milestones: dict[int, float | None] = {m: None for m in MILESTONES}
    for y in range(first, 100):
        q = qx[y]
        u = age - y if y == first else 0.0
        t_mid = 0.5 * ((y + u) + (y + 1)) - age
        hr = math.exp(log_hr * attenuation(t_mid, half_life))
        a = 1 - u * q
        b = 1 - q
        ratio = b / a
        end = survival * math.pow(ratio, hr)
        i0 = (a - b * math.pow(ratio, hr)) / (q * (hr + 1))
        i1 = (
            (math.pow(a, hr + 1) - math.pow(b, hr + 1)) / (hr + 1)
            - (math.pow(a, hr + 2) - math.pow(b, hr + 2)) / (hr + 2)
        ) / (q * q * math.pow(a, hr))
        t0 = y - age
        mean += survival * i0
        second += survival * (t0 * i0 + i1)
        while len(quantiles) < len(targets) and end <= targets[len(quantiles)]:
            target = targets[len(quantiles)]
            v = (1 - a * math.pow(target / survival, 1 / hr)) / q
            quantiles.append(y + v)
        survival = end
        curve.append((float(y + 1), survival))
        if y + 1 in milestones:
            milestones[y + 1] = survival
    # Open interval 100+: constant hazard hr / e100.
    t100 = 100 - age
    hr = math.exp(log_hr * attenuation(t100, half_life))
    rate = hr / e100
    mean += survival / rate
    second += survival * (t100 / rate + 1 / (rate * rate))
    while len(quantiles) < len(targets):
        target = targets[len(quantiles)]
        quantiles.append(100 + math.log(survival / target) / rate)
    for a_end in range(101, CURVE_END_AGE + 1):
        curve.append((float(a_end), survival * math.exp(-rate * (a_end - 100))))
    variance = 2 * second - mean * mean
    return {
        "age": age,
        "log_hazard_ratio": log_hr,
        "half_life_years": half_life,
        "life_expectancy_years": mean,
        "expected_age_at_death": age + mean,
        "sd_years": math.sqrt(variance),
        "age_25th_percentile": quantiles[0],
        "median_age": quantiles[1],
        "age_75th_percentile": quantiles[2],
        "probability_reach": {str(m): milestones[m] for m in MILESTONES},
        "survival_curve": curve,
        # Owner ruling (option 1): headline = expected age, range = 25th-75th percentile.
        "headline_age": round_half_up(age + mean),
        "range_low_age": round_half_up(quantiles[0]),
        "range_high_age": round_half_up(quantiles[2]),
    }


ROUGH_ESTIMATE_NOTE = (
    "A rough estimate from people with a similar profile, not a prediction for you."
)


def round_half_up(x: float) -> int:
    return math.floor(x + 0.5)


def headline(result: dict) -> str:
    """Recommended wording. Never deterministic wording, never a day or date."""
    return (
        f"You're likely to live to about {result['headline_age']}. Most people like you live "
        f"to between {result['range_low_age']} and {result['range_high_age']}."
    )


def expected_calendar_year(as_of: dt.date, life_expectancy_years: float) -> int:
    """The current year + remaining life expectancy, rounded to a whole year.

    A year, never a day or date (owner ruling): a date would be false precision.
    """
    return as_of.year + round_half_up(life_expectancy_years)


def exact_age(birth: dt.date, as_of: dt.date) -> float:
    return (as_of - birth).days / DAYS_PER_YEAR


def estimate_profile(
    inputs: Inputs, profile: dict, half_life: float | None = DEFAULT_HALF_LIFE
) -> dict:
    log_hr = log_hazard_ratio(inputs, profile)
    table = inputs.life_table[SEXES[profile["sex_nhanes"]]]
    return estimate(table["qx"], table["e100"], float(profile["age"]), log_hr, half_life)


# --------------------------------------------------------------------------- tools


def _xlsx_rows(path: Path) -> list[list[str]]:
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    tag = f"{{{ns['m']}}}"
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ElementTree.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns):
                shared.append("".join(t.text or "" for t in si.iter(tag + "t")))
        sheet = ElementTree.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for r in sheet.iter(tag + "row"):
        values = []
        for c in r.findall("m:c", ns):
            v = c.find("m:v", ns)
            values.append("" if v is None else shared[int(v.text)] if c.get("t") == "s" else v.text)
        rows.append(values)
    return rows


def extract_cdc(male_xlsx: Path, female_xlsx: Path, out: Path = LIFE_TABLE_CSV) -> None:
    """Copy qx, lx, Lx, Tx, ex for ages 0-100+ from NCHS Tables 2 and 3 into a CSV."""
    lines = [f"# {LIFE_TABLE_SOURCE}"]
    lines += [f"# {url}" for url in LIFE_TABLE_URLS]
    lines.append("# Values copied unrounded from the NCHS spreadsheets; age 100 is '100 and over'.")
    lines.append("sex,age,qx,lx,Lx,Tx,ex")
    for sex, path in (("male", male_xlsx), ("female", female_xlsx)):
        body = [r for r in _xlsx_rows(path) if r and r[0][:1].isdigit()]
        if len(body) != 101 or not body[-1][0].startswith("100"):
            raise ValueError(f"{path}: unexpected layout")
        for age, row in enumerate(body):
            q, lx, _dx, big_l, big_t, ex = row[1:7]
            lines.append(f"{sex},{age},{q},{lx},{big_l},{big_t},{ex}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")


def _dart_list(values: list[float]) -> str:
    body = ",\n".join(f"    {v!r}" for v in values)
    return f"[\n{body},\n  ]"


def render_dart_data(inputs: Inputs) -> str:
    names = [inputs.model["encoded_features"][c] for c in inputs.columns]
    lt = inputs.life_table
    parts = [
        "// GENERATED by server/tools/lifespan_reference.py build. Do not edit by hand.",
        "// Data for lifespan.dart (rough, proof-of-concept lifespan reveal).",
        "// dart format off",
        "",
        f"/// {LIFE_TABLE_SOURCE}",
        *[f"/// {url}" for url in LIFE_TABLE_URLS],
        "const lifeTableSource = " + json.dumps(LIFE_TABLE_SOURCE) + ";",
        "",
        "/// Cox model whose coefficients and support reference produced the values below.",
        f"const lifespanModelVersion = {json.dumps(inputs.model['model_version'])};",
        "",
        "/// Encoded model columns used for the personal hazard (age and sex excluded).",
        "const riskFeatureNames = <String>[",
        *[f"  {json.dumps(n)}," for n in names],
        "];",
        "",
        f"const riskCoefficients = <double>{_dart_list(inputs.coefficients)};",
        "",
        "/// log mean exp(risk score) of NHANES training profiles, integer ages 35..79.",
        f"const referenceScoreMale = <double>{_dart_list(inputs.reference['male'])};",
        f"const referenceScoreFemale = <double>{_dart_list(inputs.reference['female'])};",
        "",
        "/// Per-band log hazard factor (calibrates life-table S5 to the Cox model), bands",
        f"/// {', '.join(f'{lo}-{hi}' for lo, hi in CALIBRATION_BANDS)}; ages outside use the nearest band.",
        f"const bandLogAdjustmentMale = <double>{_dart_list(inputs.band_log_adjustment['male'])};",
        f"const bandLogAdjustmentFemale = <double>{_dart_list(inputs.band_log_adjustment['female'])};",
        "",
        "/// q(x), ages 0..99; and e(100) for the open 100+ interval.",
        f"const qxMale = <double>{_dart_list(lt['male']['qx'])};",
        f"const qxFemale = <double>{_dart_list(lt['female']['qx'])};",
        f"const e100Male = {lt['male']['e100']!r};",
        f"const e100Female = {lt['female']['e100']!r};",
        "",
        "/// Published e(x), ages 0..100, for validation.",
        f"const publishedExMale = <double>{_dart_list(lt['male']['ex'])};",
        f"const publishedExFemale = <double>{_dart_list(lt['female']['ex'])};",
        "",
    ]
    return "\n".join(parts)


EXAMPLE_PROFILES: dict[str, dict] = {
    "female_20_typical": {
        "age": 20, "sex_nhanes": 2, "bmi": 22.0, "sleep_hours": 8,
        "vigorous_recreation_min_week": 90, "moderate_recreation_min_week": 60,
        "sedentary_min_day": 480, "smoking_status": 0, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 0, "general_health": 2,
    },
    "male_30_typical": {
        "age": 30, "sex_nhanes": 1, "bmi": 27.5, "sleep_hours": 7,
        "vigorous_recreation_min_week": 60, "moderate_recreation_min_week": 60,
        "sedentary_min_day": 420, "smoking_status": 0, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 0, "general_health": 2,
    },
    "male_45_readme": {
        "age": 45, "sex_nhanes": 1, "bmi": 25.0, "sleep_hours": 7,
        "vigorous_recreation_min_week": 60, "moderate_recreation_min_week": 120,
        "sedentary_min_day": 360, "smoking_status": 0, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 0, "general_health": 2,
    },
    "female_55_former_smoker_htn": {
        "age": 55, "sex_nhanes": 2, "bmi": 31.0, "sleep_hours": 6,
        "vigorous_recreation_min_week": 0, "moderate_recreation_min_week": 0,
        "sedentary_min_day": 480, "smoking_status": 1, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 1, "general_health": 3,
    },
    "female_72_never_smoker_active": {
        "age": 72, "sex_nhanes": 2, "bmi": 25.0, "sleep_hours": 7,
        "vigorous_recreation_min_week": 60, "moderate_recreation_min_week": 150,
        "sedentary_min_day": 300, "smoking_status": 0, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 0, "general_health": 2,
    },
    "female_72_smoker_diabetes": {
        "age": 72, "sex_nhanes": 2, "bmi": 25.0, "sleep_hours": 7,
        "vigorous_recreation_min_week": 60, "moderate_recreation_min_week": 150,
        "sedentary_min_day": 300, "smoking_status": 2, "diabetes_diagnosed": 1,
        "hypertension_diagnosed": 0, "general_health": 2,
    },
    "male_84_hypertension": {
        "age": 84, "sex_nhanes": 1, "bmi": 26.0, "sleep_hours": 8,
        "vigorous_recreation_min_week": 0, "moderate_recreation_min_week": 90,
        "sedentary_min_day": 480, "smoking_status": 1, "diabetes_diagnosed": 0,
        "hypertension_diagnosed": 1, "general_health": 3,
    },
}  # fmt: skip

GOLDEN_RAW_CASES = [
    # sex, exact age, log HR, half-life
    ("male", 30.0, 0.0, None),
    ("female", 47.31, 0.0, None),
    ("male", 65.0, 0.0, 20.0),
    ("female", 79.5, 0.6, None),
    ("male", 35.2, -0.45, 20.0),
    ("female", 84.9, 1.1, 10.0),
    ("male", 99.5, 0.3, 20.0),
    ("female", 1.0, -0.2, 20.0),
]


def build_golden(inputs: Inputs) -> dict:
    def pick(r: dict) -> dict:
        return {k: r[k] for k in r if k != "survival_curve"} | {
            "survival_curve": [[a, s] for a, s in r["survival_curve"]]
        }

    raw = []
    for sex, age, lhr, hl in GOLDEN_RAW_CASES:
        t = inputs.life_table[sex]
        raw.append({"sex": sex} | pick(estimate(t["qx"], t["e100"], age, lhr, hl)))
    profiles = []
    for name, profile in EXAMPLE_PROFILES.items():
        for hl in (None, 20.0, 10.0):
            r = estimate_profile(inputs, profile, hl)
            profiles.append({"name": name, "profile": profile} | pick(r))
    as_of = dt.date(2026, 10, 24)
    birth = dt.date(1981, 3, 14)
    age = exact_age(birth, as_of)
    t = inputs.life_table["male"]
    lhr = log_hazard_ratio(inputs, EXAMPLE_PROFILES["male_45_readme"] | {"age": age})
    r = estimate(t["qx"], t["e100"], age, lhr, DEFAULT_HALF_LIFE)
    dates = {
        "as_of": as_of.isoformat(),
        "birth": birth.isoformat(),
        "exact_age": age,
        "log_hazard_ratio": lhr,
        "life_expectancy_years": r["life_expectancy_years"],
        "expected_calendar_year": expected_calendar_year(as_of, r["life_expectancy_years"]),
        "headline": headline(r),
    }
    return {
        "generated_by": "server/tools/lifespan_reference.py build",
        "model_version": inputs.model["model_version"],
        "raw": raw,
        "profiles": profiles,
        "calendar_example": dates,
    }


def write_build(inputs: Inputs) -> None:
    DART_DATA.write_text(render_dart_data(inputs))
    GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN.write_text(json.dumps(build_golden(inputs), indent=1) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    ex = sub.add_parser("extract-cdc")
    ex.add_argument("male_xlsx", type=Path)
    ex.add_argument("female_xlsx", type=Path)
    sub.add_parser("build")
    sub.add_parser("validate")
    args = parser.parse_args(argv)
    if args.command == "extract-cdc":
        extract_cdc(args.male_xlsx, args.female_xlsx)
    elif args.command == "build":
        write_build(Inputs())
    else:
        from lifespan_validation import report

        print(report(Inputs()))
    return 0


if __name__ == "__main__":
    sys.exit(main())

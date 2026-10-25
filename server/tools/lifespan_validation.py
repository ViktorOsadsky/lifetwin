"""Validation tables for the lifespan prototype (printed as markdown).

Run: python server/tools/lifespan_reference.py validate
"""

from __future__ import annotations

import math
import statistics

import lifespan_reference as lr

BANDS = lr.CALIBRATION_BANDS
# Published age-adjusted-ish all-cause hazard ratios used only as a cross-check.
LITERATURE_HR = {
    # Jha et al., NEJM 2013;368:341-50: current vs never smokers, women 3.0, men 2.8.
    "current_smoker_female": 3.0,
    "current_smoker_male": 2.8,
    # Emerging Risk Factors Collaboration, NEJM 2011;364:829-41: diabetes vs none 1.80.
    "diabetes": 1.80,
}
PUBLISHED_E65 = {"male": 18.4, "female": 20.8}  # NVSR 75-5 Table A


def recompute_ex(qx: list[float], e100: float) -> list[float]:
    """Textbook life-table recomputation from qx alone (a=0.5 for ages >= 1)."""
    lx = [1.0]
    for q in qx:
        lx.append(lx[-1] * (1 - q))
    big_l = [(lx[i] + lx[i + 1]) / 2 for i in range(100)] + [lx[100] * e100]
    tx = [0.0] * 101
    running = 0.0
    for i in range(100, -1, -1):
        running += big_l[i]
        tx[i] = running
    return [tx[i] / lx[i] for i in range(101)]


def decoded_rows(inputs: lr.Inputs) -> list[dict]:
    """Support rows as (sex, age, risk score, full Cox score)."""
    return inputs.rows


def _fmt(x: float, digits: int = 2) -> str:
    return f"{x:.{digits}f}"


def life_table_section(inputs: lr.Inputs) -> list[str]:
    out = ["## 1. Life table reproduction (HR = 1, no attenuation)", ""]
    out.append(
        "| Sex | e65 published (Table A) | e65 spreadsheet | e65 this method | "
        "max abs diff vs spreadsheet e(x), ages 1-99 | max abs diff vs recomputation from q(x) |"
    )
    out.append("|---|---|---|---|---|---|")
    for sex in ("male", "female"):
        t = inputs.life_table[sex]
        ours = [
            lr.estimate(t["qx"], t["e100"], float(a), 0.0, None)["life_expectancy_years"]
            for a in range(1, 100)
        ]
        recomputed = recompute_ex(t["qx"], t["e100"])
        d_pub = max(abs(o - p) for o, p in zip(ours, t["ex"][1:100], strict=True))
        d_rec = max(abs(o - p) for o, p in zip(ours, recomputed[1:100], strict=True))
        out.append(
            f"| {sex} | {PUBLISHED_E65[sex]} | {t['ex'][65]:.4f} | {ours[64]:.4f} | "
            f"{d_pub:.1e} | {d_rec:.1e} |"
        )
    out.append("")
    return out


def reference_section(inputs: lr.Inputs, rows: list[dict]) -> list[str]:
    out = ["## 2. Personal hazard ratio among NHANES training profiles", ""]
    out.append(
        "HR relative to the same-sex, same-age reference (log-mean-exp). Mean HR should be ~1 "
        "by construction; the median sits below 1 because a minority of high-risk profiles "
        "carries most of the deaths."
    )
    out.append("")
    out.append(
        "| Sex | Ages | n | mean HR | median HR | 10th-90th pct HR | HR of the mean profile |"
    )
    out.append("|---|---|---|---|---|---|---|")
    for sex in ("male", "female"):
        for lo, hi in BANDS:
            sel = [r for r in rows if r["sex"] == sex and lo <= r["age"] <= hi]
            hrs = sorted(
                math.exp(r["risk"] - lr.reference_score(inputs.reference[sex], r["age"]))
                for r in sel
            )
            mean_risk = statistics.fmean(r["risk"] for r in sel)
            mean_age = statistics.fmean(r["age"] for r in sel)
            hr_mean_profile = math.exp(
                mean_risk - lr.reference_score(inputs.reference[sex], mean_age)
            )
            q = statistics.quantiles(hrs, n=10)
            out.append(
                f"| {sex} | {lo}-{hi} | {len(sel)} | {_fmt(statistics.fmean(hrs))} | "
                f"{_fmt(statistics.median(hrs))} | {_fmt(q[0])}-{_fmt(q[-1])} | "
                f"{_fmt(hr_mean_profile)} |"
            )
    out.append("")
    return out


def calibration_section(inputs: lr.Inputs, rows: list[dict]) -> list[str]:
    out = ["## 3. Five-year survival: Cox model vs. life-table version", ""]
    out.append(
        "Same NHANES training profiles. Cox = the packaged model (NHANES 2007-2012, deaths "
        "to 2019). Life table = this method (2024 US period table x personal HR), before and "
        "after the per-band hazard factor k. Gap = life table - Cox, percentage points."
    )
    out.append("")
    out.append(
        "| Sex | Ages | n | mean Cox S5 % | life-table S5 % before | gap before pp | k | "
        "life-table S5 % after | gap after pp | rank correlation |"
    )
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    s0_5 = inputs.model["baseline_survival"][4]
    for sex in ("male", "female"):
        t = inputs.life_table[sex]
        for band, (lo, hi) in enumerate(BANDS):
            sel = [r for r in rows if r["sex"] == sex and lo <= r["age"] <= hi]
            c = inputs.band_log_adjustment[sex][band]
            cox, lt, adj = [], [], []
            for r in sel:
                cox.append(s0_5 ** math.exp(r["full"]))
                lhr = r["risk"] - lr.reference_score(inputs.reference[sex], r["age"])
                five = r["age"] + 5
                for target, shift in ((lt, 0.0), (adj, c)):
                    est = lr.estimate(t["qx"], t["e100"], r["age"], lhr + shift, None)
                    target.append(_survival_at(est["survival_curve"], five))
            mc = statistics.fmean(cox)
            gap = 100 * (statistics.fmean(lt) - mc)
            gap_after = 100 * (statistics.fmean(adj) - mc)
            rho = _spearman(cox, adj)
            out.append(
                f"| {sex} | {lo}-{hi} | {len(sel)} | {100 * mc:.2f} | "
                f"{100 * statistics.fmean(lt):.2f} | {gap:+.2f} | {math.exp(c):.3f} | "
                f"{100 * statistics.fmean(adj):.2f} | {gap_after:+.2f} | {rho:.3f} |"
            )
    out.append("")
    return out


def _survival_at(curve: list[tuple[float, float]], age: float) -> float:
    """Survival at an integer age offset from an integer start (all support ages are whole)."""
    for a, s in curve:
        if abs(a - age) < 1e-9:
            return s
    raise ValueError(age)


def _spearman(a: list[float], b: list[float]) -> float:
    def ranks(v: list[float]) -> list[float]:
        order = sorted(range(len(v)), key=v.__getitem__)
        r = [0.0] * len(v)
        for rank, i in enumerate(order):
            r[i] = float(rank)
        return r

    return statistics.correlation(ranks(a), ranks(b))


def examples_section(inputs: lr.Inputs) -> list[str]:
    out = ["## 4. Example profiles (attenuation half-life: none / 20 y default / 10 y)", ""]
    out.append(
        "| Profile | HR | headline (20 y): about / range | table avg age at death | "
        "expected age (none / 20 / 10) | "
        "median | 25th-75th pct | SD y | P(80) | P(90) | P(100) |"
    )
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for name, p in lr.EXAMPLE_PROFILES.items():
        sex = lr.SEXES[p["sex_nhanes"]]
        t = inputs.life_table[sex]
        avg = lr.estimate(t["qx"], t["e100"], float(p["age"]), 0.0, None)
        res = {hl: lr.estimate_profile(inputs, p, hl) for hl in (None, 20.0, 10.0)}
        d = res[20.0]
        hr = math.exp(d["log_hazard_ratio"])
        pr = d["probability_reach"]
        reach = [("-" if pr[k] is None else f"{100 * pr[k]:.0f}%") for k in ("80", "90", "100")]
        out.append(
            f"| {name} | {hr:.2f} | {d['headline_age']} / {d['range_low_age']}-{d['range_high_age']} | "
            f"{avg['expected_age_at_death']:.1f} | "
            + " / ".join(f"{res[h]['expected_age_at_death']:.1f}" for h in (None, 20.0, 10.0))
            + f" | {d['median_age']:.1f} | {d['age_25th_percentile']:.1f}-"
            f"{d['age_75th_percentile']:.1f} | {d['sd_years']:.1f} | " + " | ".join(reach) + " |"
        )
    out.append("")
    return out


def sanity_section(inputs: lr.Inputs) -> list[str]:
    out = ["## 5. Sanity case: 72-year-old women", ""]
    a = lr.EXAMPLE_PROFILES["female_72_never_smoker_active"]
    b = lr.EXAMPLE_PROFILES["female_72_smoker_diabetes"]
    inactive = b | {
        "vigorous_recreation_min_week": 0,
        "moderate_recreation_min_week": 0,
        "sedentary_min_day": 600,
        "general_health": 4,
    }
    t = inputs.life_table["female"]
    lit = math.log(LITERATURE_HR["current_smoker_female"] * LITERATURE_HR["diabetes"])
    out.append("| Contrast | model log-HR gap | none | 20 y | 10 y |")
    out.append("|---|---|---|---|---|")

    def gap(p: dict, q: dict) -> list[float]:
        return [
            lr.estimate_profile(inputs, p, h)["life_expectancy_years"]
            - lr.estimate_profile(inputs, q, h)["life_expectancy_years"]
            for h in (None, 20.0, 10.0)
        ]

    for label, p, q in (
        ("active never-smoker vs same + current smoker + diabetes", a, b),
        ("active never-smoker vs inactive, fair health, smoker, diabetes", a, inactive),
    ):
        g = gap(p, q)
        lg = lr.log_hazard_ratio(inputs, q) - lr.log_hazard_ratio(inputs, p)
        out.append(
            f"| {label} | {lg:.2f} (HR x{math.exp(lg):.2f}) | "
            + " | ".join(f"{x:.1f} y" for x in g)
            + " |"
        )
    lit_gap = [
        lr.estimate(t["qx"], t["e100"], 72.0, 0.0, h)["life_expectancy_years"]
        - lr.estimate(t["qx"], t["e100"], 72.0, lit, h)["life_expectancy_years"]
        for h in (None, 20.0, 10.0)
    ]
    out.append(
        f"| literature HRs (smoking 3.0 x diabetes 1.80), average woman | {lit:.2f} "
        f"(HR x{math.exp(lit):.2f}) | " + " | ".join(f"{x:.1f} y" for x in lit_gap) + " |"
    )
    out.append("")
    return out


def edges_section(inputs: lr.Inputs) -> list[str]:
    out = ["## 6. Edge ages (expected age at death, default 20 y half-life)", ""]
    p = lr.EXAMPLE_PROFILES["male_45_readme"]
    q = lr.EXAMPLE_PROFILES["female_55_former_smoker_htn"]
    out.append("| Age | avg man | README man (HR) | avg woman | 55F profile (HR) |")
    out.append("|---|---|---|---|---|")
    for age in (18, 19, 30, 34, 35, 36, 44, 45, 78, 79, 80, 81, 84, 85):
        row = [str(age)]
        for sex, prof in (("male", p), ("female", q)):
            t = inputs.life_table[sex]
            avg = lr.estimate(t["qx"], t["e100"], float(age), 0.0, 20.0)
            pr = lr.estimate_profile(inputs, prof | {"age": age}, 20.0)
            row.append(f"{avg['expected_age_at_death']:.2f}")
            row.append(
                f"{pr['expected_age_at_death']:.2f} ({math.exp(pr['log_hazard_ratio']):.2f})"
            )
        out.append("| " + " | ".join(row) + " |")
    out.append("")
    return out


def date_section(inputs: lr.Inputs) -> list[str]:
    g = lr.build_golden(inputs)["calendar_example"]
    return [
        "## 7. Calendar-year computation (README man, born 1981-03-14, assessed 2026-10-24)",
        "",
        f"- exact age = {g['exact_age']:.4f} y; log HR = {g['log_hazard_ratio']:.4f}",
        f"- remaining life expectancy = {g['life_expectancy_years']:.4f} y "
        f"= {g['life_expectancy_years'] * lr.DAYS_PER_YEAR:.1f} days",
        f"- expected calendar year = {g['expected_calendar_year']} (no day or date is exposed)",
        f"- headline: {g['headline']}",
        "",
    ]


def report(inputs: lr.Inputs) -> str:
    rows = decoded_rows(inputs)
    lines = [f"# Lifespan prototype validation ({inputs.model['model_version']})", ""]
    for section in (
        life_table_section(inputs),
        reference_section(inputs, rows),
        calibration_section(inputs, rows),
        examples_section(inputs),
        sanity_section(inputs),
        edges_section(inputs),
        date_section(inputs),
    ):
        lines += section
    return "\n".join(lines)

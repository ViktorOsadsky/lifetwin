"""Build the synthetic two-week band demo (a retired ~64-year-old woman, thigh band).

Writes, deterministically (seeded; no randomness at runtime):
  - app/lib/band/band_demo_templates.dart     the in-app "Recorded demo" source (dates are applied at load time)
  - demo/band/band-two-weeks-demo.json        an importable lifetwin.band_days.v0 bundle

The app shifts dates at load time so the last demo day is always "yesterday"; the bundle is
dated so its last day is the day before --today (default: the machine's today). Day shapes are
keyed by (week, weekday), so weekends are always weekends. Every number is made up.

Usage: python3 tools/build_demo_band_days.py [--today YYYY-MM-DD] [--desktop DIR]
"""

import argparse
import datetime as dt
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = 64
START, END = 7 * 60, 22 * 60 + 29  # full-wear window 07:00-22:29


def hm(h, m=0):
    return h * 60 + m


# (week, weekday Mon=1..Sun=7) -> profile. walks: (start, minutes, brisk minutes).
# garden/chores/errand: (start, minutes). bouts: sitting-bout length range in minutes.
def day(**kw):
    base = dict(window=(START, END), off=[(hm(7, 10), 15)], bouts=(35, 65), tv=(hm(19, 30), hm(22, 0), 60, 110),
                walks=[], garden=[], potter=[(hm(7, 45), 60), (hm(9, 45), 150), (hm(13, 30), 190), (hm(16, 20), 60)], chores=[(hm(7, 25), 25), (hm(17, 30), 40)], errand=[], note="")
    base.update(kw)
    return base


PROFILES = {
    (0, 1): day(walks=[(hm(8, 15), 30, 14)], note="Weekday: morning walk"),
    (0, 2): day(walks=[(hm(8, 0), 45, 26)], note="Weekday: long brisk morning walk"),
    (0, 3): day(walks=[(hm(8, 20), 20, 8)], errand=[(hm(11, 0), 45)], note="Weekday: easy walk and shopping"),
    (0, 4): day(walks=[(hm(8, 30), 35, 18)], note="Weekday: morning walk"),
    (0, 5): day(walks=[(hm(8, 10), 25, 10)], bouts=(45, 80), note="Weekday: short walk, long sits"),
    (0, 6): day(walks=[(hm(9, 0), 30, 14)], garden=[(hm(14, 0), 100)], note="Weekend: walk and gardening"),
    (0, 7): day(walks=[(hm(10, 0), 12, 0)], errand=[(hm(11, 30), 30)], bouts=(45, 75), potter=[(hm(9, 45), 120), (hm(14, 0), 150)], chores=[(hm(8, 0), 20), (hm(17, 45), 30)], tv=(hm(19, 0), hm(22, 0), 70, 130),
                note="Rest day: low activity"),
    (1, 1): day(walks=[(hm(8, 0), 40, 27)], note="Weekday: morning walk"),
    (1, 2): day(walks=[(hm(8, 30), 30, 17)], note="Weekday: morning walk"),
    (1, 3): day(window=(hm(7, 30), hm(16, 29)), off=[], walks=[(hm(8, 15), 25, 12)], chores=[(hm(7, 40), 25)],
                tv=None, note="Partial wear: band taken off in the afternoon"),
    (1, 4): day(walks=[(hm(8, 20), 35, 25)], note="Weekday: morning walk"),
    (1, 5): day(walks=[(hm(8, 10), 30, 19)], errand=[(hm(10, 30), 40)], note="Weekday: walk and errands"),
    (1, 6): day(walks=[(hm(8, 45), 30, 12)], garden=[(hm(13, 0), 150)], bouts=(28, 50),
                note="Weekend: lively gardening day"),
    (1, 7): day(walks=[(hm(10, 30), 70, 24)], note="Weekend: long walk with a friend"),
}

STEP_RANGE = {"sit": (0, 0), "stand": (0, 3), "pot": (6, 22), "light": (56, 80), "mod": (100, 118), "off": (0, 0)}
BIN = {"sit": 0, "stand": 1, "light": 2, "pot": 2, "mod": 2, "off": 5}


def build(rng, p):
    start, end = p["window"]
    n = end - start + 1
    st = ["sit"] * n

    def put(a, length, state):
        for i in range(max(0, a - start), min(n, a - start + length)):
            st[i] = state

    def mix(a, length, weights):
        i = a - start
        stop = min(n, i + length)
        while i < stop:
            run = rng.randint(2, 6)
            state = rng.choices(list(weights), list(weights.values()))[0]
            for j in range(i, min(stop, i + run)):
                st[j] = state
            i += run

    t = 0  # base rhythm: sitting bouts broken by short stand/walk moments
    while t < n:
        tv = p["tv"]
        bout = rng.randint(*(tv[2:] if tv and tv[0] <= start + t < tv[1] else p["bouts"]))
        t += bout
        brk = rng.randint(2, 6)
        for j in range(t, min(n, t + brk)):
            st[j] = "stand" if j < t + brk - 1 or rng.random() < 0.5 else "pot"
        t += brk
    for a, length in p["chores"]:
        mix(a, length, {"stand": 55, "pot": 38, "sit": 7})
    for a, length in p["potter"]:
        mix(a, length, {"stand": 52, "pot": 30, "sit": 8})
    for a, length in p["errand"]:
        mix(a, length, {"light": 55, "stand": 30, "mod": 10, "sit": 5})
    for a, length in p["garden"]:
        mix(a, length, {"stand": 45, "pot": 30, "light": 8, "mod": 14, "sit": 3})
    for a, length, brisk in p["walks"]:
        put(a, length, "light")
        lo = a - start + 3 + (length - 6 - brisk) // 2
        for i in range(lo, lo + brisk):
            st[i] = "mod" if rng.random() > 0.08 else "light"
        for i in range(a - start + 3, a - start + length - 3):
            if rng.random() < 0.02:
                st[i] = "stand"
    for a, length in p["off"]:
        put(a, length, "off")

    rows, steps_total = {}, 0
    for i, s in enumerate(st):
        steps = rng.randint(*STEP_RANGE[s])
        steps_total += steps
        r = rows.setdefault((start + i) // 60, [0] * 7)
        r[BIN[s]] += 1
        r[6] += steps
    worn = [s for s in st if s != "off"]
    longest = cur = trans = 0
    prev = None
    for s in st:
        if s == "off":
            cur, prev = 0, None
            continue
        cur = cur + 1 if s == "sit" else 0
        longest = max(longest, cur)
        if prev == "sit" and s != "sit":
            trans += 1
        prev = s
    return dict(
        first=f"{start // 60:02d}:{start % 60:02d}", last=f"{end // 60:02d}:{end % 60:02d}", recorded=n,
        minutes=[worn.count("sit"), worn.count("stand"), worn.count("light") + worn.count("pot"), worn.count("mod"), 0, 0, st.count("off")],
        steps=steps_total, transitions=trans, longest=longest, hours=rows,
    )


def all_templates():
    rng = random.Random(SEED)
    return {k: dict(build(rng, PROFILES[k]), note=PROFILES[k]["note"]) for k in sorted(PROFILES)}


def to_report(t, date):
    m = t["minutes"]
    keys = ["sitting_or_lying", "standing", "walking_light", "walking_moderate", "running_vigorous",
            "other_posture", "not_worn", "positions_not_saved"]
    hourly = []
    for h in range(24):
        r = t["hours"].get(h, [0] * 7)
        hourly.append(dict(hour=h, sitting_lying_min=r[0], standing_min=r[1], walking_min=r[2], running_min=r[3],
                           other_min=r[4], not_worn_min=r[5], steps=r[6]))
    wear = t["recorded"] - m[6]
    return {
        "schema": "lifetwin.band_day.v0", "date": date.isoformat(), "timezone_offset_minutes": 0,
        "generated_at": f"{date.isoformat()}T23:59:00Z",
        "device": {"mount": "thigh_pocket", "firmware": "synthetic-demo", "record_format": 2},
        "coverage": {"minutes_recorded": t["recorded"], "wear_minutes": wear, "valid_day": wear >= 600,
                     "first_minute": t["first"], "last_minute": t["last"]},
        "minutes": dict(zip(keys, m + [0])),
        "moderate_vigorous_minutes": m[3] + m[4], "steps": t["steps"],
        "sit_to_stand_transitions": t["transitions"], "longest_sitting_minutes": t["longest"],
        "hourly": hourly,
        "notes": ["Synthetic demo data, not a hardware recording.", t["note"]],
        "synthetic_demo": True,
    }


def dart(templates):
    out = [f"// GENERATED by tools/build_demo_band_days.py (seed {SEED}). Do not edit by hand.",
           "// Synthetic demo only: a made-up 14-day pattern, not a hardware recording.", "",
           "/// One made-up day shape. [hours] maps an hour to [sitting, standing, walking, running, other,",
           "/// not worn, steps]; [minutes] is [sitting, standing, light, moderate, vigorous, other, not worn].",
           "class BandDemoTemplate {",
           "  const BandDemoTemplate(",
           "    this.week,",
           "    this.weekday,",
           "    this.first,",
           "    this.last,",
           "    this.recorded,",
           "    this.minutes,",
           "    this.steps,",
           "    this.transitions,",
           "    this.longest,",
           "    this.note,",
           "    this.hours,",
           "  );",
           "  final int week, weekday, recorded, steps, transitions, longest;",
           "  final String first, last, note;",
           "  final List<int> minutes;",
           "  final Map<int, List<int>> hours;",
           "}", "", "const bandDemoTemplates = <BandDemoTemplate>["]
    for (w, wd), t in templates.items():
        out += ["  BandDemoTemplate(", f"    {w},", f"    {wd},", f"    '{t['first']}',", f"    '{t['last']}',",
                f"    {t['recorded']},", f"    {t['minutes']},", f"    {t['steps']},", f"    {t['transitions']},",
                f"    {t['longest']},", f"    '{t['note']}',", "    {"]
        out += [f"      {h}: {t['hours'][h]}," for h in sorted(t["hours"])]
        out += ["    },", "  ),"]
    out.append("];")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--today", default=dt.date.today().isoformat())
    ap.add_argument("--desktop", default=None)
    a = ap.parse_args()
    today = dt.date.fromisoformat(a.today)
    templates = all_templates()
    days = []
    for back in range(14, 0, -1):
        d = today - dt.timedelta(days=back)
        days.append(to_report(templates[(0 if back > 7 else 1, d.isoweekday())], d))
    bundle = json.dumps({"schema": "lifetwin.band_days.v0", "days": days}, indent=1) + "\n"
    (ROOT / "demo/band").mkdir(parents=True, exist_ok=True)
    (ROOT / "demo/band/band-two-weeks-demo.json").write_text(bundle)
    (ROOT / "app/lib/band/band_demo_templates.dart").write_text(dart(templates))
    if a.desktop:
        Path(a.desktop).mkdir(parents=True, exist_ok=True)
        (Path(a.desktop) / "band-two-weeks-demo.json").write_text(bundle)
    print("date       dow steps mvpa sitH trans longest wear")
    for d in days:
        m = d["minutes"]
        print(d["date"], f"{dt.date.fromisoformat(d['date']):%a}", d["steps"], d["moderate_vigorous_minutes"],
              round(m["sitting_or_lying"] / 60, 1), d["sit_to_stand_transitions"], d["longest_sitting_minutes"],
              d["coverage"]["wear_minutes"])


main()

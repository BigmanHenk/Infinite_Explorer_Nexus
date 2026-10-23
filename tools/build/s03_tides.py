"""Step 3 - tide predictions for Margate/Birchington, 10 years ahead, into tools/work/tides.pkl.

    python tools/build/s03_tides.py

1. Harmonic analysis (UTide) of a year of 15-min Environment Agency readings at Dover and
   Sheerness (s00_tide_download.py; Open Government Licence).
2. Margate has no open gauge. It lies on the tidal wave's path between the two, so its
   constituents are placed between them: per species (diurnal+semidiurnal / shallow-water)
   a position w along the way (phase), an amplitude scale k, and the chart-datum offset.
   Those few numbers are fitted to a handful of published Margate high/low waters (times
   and heights; CALIB below), used only as reference points.
3. Dover is checked the same way against its published times (pure harmonic method, no
   fitting) - that is the honest accuracy figure for the method itself.
"""
import datetime as dt
import pickle
from pathlib import Path

import numpy as np
import utide
from scipy.optimize import minimize

from common import WORK

DOVER = "E71639"
SHEER = "E71539"

# Published high/low waters (UTC), used to calibrate Margate and check Dover.
def _ev(rows):
    out = []
    for d, t, h, kind in rows:
        out.append((np.datetime64(f"{d}T{t}"), h, kind))
    return out

CALIB_MARGATE = _ev([
    ("2026-10-23", "03:38", 1.35, "L"), ("2026-10-23", "09:37", 4.26, "H"),
    ("2026-10-23", "16:03", 0.88, "L"), ("2026-10-23", "22:11", 4.43, "H"),
    ("2026-10-26", "05:38", 0.88, "L"), ("2026-10-26", "11:34", 4.78, "H"), ("2026-10-26", "17:56", 0.62, "L"),
    ("2026-10-29", "01:19", 4.71, "H"), ("2026-10-29", "07:40", 0.71, "L"),
    ("2026-10-29", "13:41", 4.88, "H"), ("2026-10-29", "19:50", 0.79, "L"),
])
CHECK_DOVER = _ev([
    ("2026-10-23", "03:32", 1.89, "L"), ("2026-10-23", "08:41", 6.08, "H"),
    ("2026-10-23", "15:54", 1.54, "L"), ("2026-10-23", "21:06", 6.14, "H"),
    ("2026-10-26", "05:42", 1.15, "L"), ("2026-10-26", "10:33", 6.88, "H"),
    ("2026-10-26", "18:06", 0.94, "L"), ("2026-10-26", "22:53", 6.80, "H"),
    ("2026-10-29", "00:11", 6.85, "H"), ("2026-10-29", "07:42", 1.02, "L"),
    ("2026-10-29", "12:31", 6.87, "H"), ("2026-10-29", "20:05", 1.11, "L"),
])
LAT = 51.39
EPOCH = np.datetime64("1970-01-01T00:00")


def load(station):
    t, v = [], []
    for f in sorted((WORK / "tide").glob("*.csv")):
        for line in f.read_text().splitlines():
            parts = line.split(",")
            if len(parts) != 3 or station not in parts[1]:
                continue
            try:
                val = float(parts[2])
            except ValueError:
                continue
            t.append(np.datetime64(parts[0].rstrip("Z")))
            v.append(val)
    # "Mean-15_min" readings are stamped at the END of their 15 minutes: centre them
    t = np.array(t, dtype="datetime64[s]") - np.timedelta64(450, "s")
    v = np.array(v)
    order = np.argsort(t)
    t, v = t[order], v[order]
    keep = np.concatenate([[True], np.diff(t) > np.timedelta64(0, "m")])
    t, v = t[keep], v[keep]
    # spikes: > 0.6 m from the 5-point running median
    med = np.array([np.median(v[max(0, i - 2): i + 3]) for i in range(len(v))])
    ok = np.abs(v - med) < 0.6
    t, v = t[ok], v[ok]
    # whole-day quality check: a tidal day has a big spread and a mean near 0 mAOD
    # (Dover sat flat at the gauge zero for most of June-August 2026)
    day = t.astype("datetime64[D]")
    good = np.zeros(len(t), bool)
    for d in np.unique(day):
        m = day == d
        x = v[m]
        if m.sum() >= 80 and x.std() > 0.6 and -1.2 < x.mean() < 1.5 and len(np.unique(x)) > 40:
            good |= m
    print(f"  {station}: {len(np.unique(day[good]))} good days of {len(np.unique(day))}")
    return t[good], v[good]


def days(t):
    return (t - EPOCH) / np.timedelta64(1, "D")


def fit(station):
    t, v = load(station)
    print(f"{station}: {len(t)} readings {t[0]} .. {t[-1]}")
    coef = utide.solve(days(t), v, lat=LAT, method="ols", conf_int="none", trend=False,
                       constit="auto", verbose=False, epoch="1970-01-01")
    coef["name"] = np.array([n.strip() for n in coef.name])
    res = v - utide.reconstruct(days(t), coef, verbose=False, epoch="1970-01-01").h
    print(f"  {len(coef.name)} constituents, residual RMS {np.sqrt(np.mean(res**2)):.3f} m "
          f"(weather surge included), M2 {coef.A[list(coef.name).index('M2')]:.2f} m")
    return coef


def species(name):
    if name in ("Z0",):
        return 0
    if name.startswith(("SA", "SSA", "MM", "MSF", "MF", "MSM", "MTM", "MSQM", "MSQ")):
        return 0
    digits = "".join(ch for ch in name if ch.isdigit())
    if name in ("Q1", "O1", "P1", "K1", "J1", "OO1", "M1", "NO1", "2Q1", "SIG1", "RHO1", "TAU1", "BET1",
                "ALP1", "CHI1", "PI1", "PHI1", "THE1", "SO1", "UPS1", "S1", "PSI1", "KQ1"):
        return 1
    if digits:
        try:
            return int(digits[-1])
        except ValueError:
            return 2
    return 2


def blend(cd, cs, p):
    """Margate constituents between Dover (cd) and Sheerness (cs)."""
    w_lo, w_hi, k_lo, k_hi, z0 = p
    names = [n for n in cd.name if n in set(cs.name)]
    idx_d = {n: i for i, n in enumerate(cd.name)}
    idx_s = {n: i for i, n in enumerate(cs.name)}
    A, g = [], []
    for n in names:
        sp = species(n)
        w, k = (w_lo, k_lo) if sp <= 2 else (w_hi, k_hi)
        ad, as_ = cd.A[idx_d[n]], cs.A[idx_s[n]]
        gd, gs = cd.g[idx_d[n]], cs.g[idx_s[n]]
        dg = (gs - gd + 180) % 360 - 180
        A.append(k * (ad * (1 - w) + as_ * w))
        g.append((gd + w * dg) % 360)
    c = pickle.loads(pickle.dumps(cd))
    sel = [idx_d[n] for n in names]
    c["name"] = np.array(names)
    c["A"] = np.array(A)
    c["g"] = np.array(g)
    c["mean"] = z0
    aux = c["aux"]
    aux["frq"] = cd["aux"]["frq"][sel]
    aux["lind"] = cd["aux"]["lind"][sel]
    for k in ("A_ci", "g_ci"):
        if k in c:
            c[k] = np.zeros(len(names))
    return c


def extremes(coef, t0, t1, step_min=1):
    t = np.arange(t0, t1, np.timedelta64(step_min, "m")).astype("datetime64[s]")
    h = utide.reconstruct(days(t), coef, verbose=False, epoch="1970-01-01").h
    out = []
    for i in range(1, len(h) - 1):
        if h[i] > h[i - 1] and h[i] >= h[i + 1]:
            out.append((t[i], h[i], "H"))
        elif h[i] < h[i - 1] and h[i] <= h[i + 1]:
            out.append((t[i], h[i], "L"))
    # drop tiny wiggles (stand of the tide): pairs closer than 2 h or under 5 cm apart
    clean = []
    for e in out:
        if clean and clean[-1][2] == e[2]:
            if (e[2] == "H" and e[1] > clean[-1][1]) or (e[2] == "L" and e[1] < clean[-1][1]):
                clean[-1] = e
            continue
        if clean and (e[0] - clean[-1][0]) < np.timedelta64(120, "m") and abs(e[1] - clean[-1][1]) < 0.3:
            clean.pop()
            continue
        clean.append(e)
    return clean


def compare(pred, ref):
    dts, dhs = [], []
    for t, h, kind in ref:
        cand = [e for e in pred if e[2] == kind]
        t = t.astype("datetime64[s]")
        best = min(cand, key=lambda e: abs((e[0] - t) / np.timedelta64(1, "m")))
        dts.append((best[0] - t) / np.timedelta64(1, "m"))
        dhs.append(best[1] - h)
    return np.array(dts), np.array(dhs)


def main():
    cd = fit(DOVER)
    cs = fit(SHEER)
    t0 = np.datetime64("2026-10-22T12:00")
    t1 = np.datetime64("2026-10-30T12:00")

    # Dover check: published heights are above chart datum; fit only the datum offset
    pd_ = extremes(cd, t0, t1)
    dts, dhs = compare(pd_, CHECK_DOVER)
    off = -np.mean(dhs)
    print(f"Dover check (pure harmonic): time error mean {dts.mean():+.1f} min, max |{np.abs(dts).max():.0f}| min; "
          f"datum offset {off:.2f} m, height error RMS {np.sqrt(np.mean((dhs + off) ** 2)):.2f} m")

    def cost(p):
        w_lo, w_hi, k_lo, k_hi, _ = p
        if not (0 <= w_lo <= 1.2 and 0 <= w_hi <= 1.2 and 0.3 <= k_lo <= 1.5 and 0 <= k_hi <= 1.5):
            return 1e6
        c = blend(cd, cs, p)
        pm = extremes(c, t0, t1, step_min=3)
        dt_, dh_ = compare(pm, CALIB_MARGATE)
        return np.mean((dt_ / 10) ** 2) + np.mean((dh_ / 0.1) ** 2)

    best = None
    for w0 in (0.4, 0.6, 0.8):
        r = minimize(cost, [w0, w0, 0.85, 0.85, 2.5], method="Nelder-Mead",
                     options={"maxiter": 600, "xatol": 1e-3, "fatol": 1e-3})
        if best is None or r.fun < best.fun:
            best = r
    p = best.x
    cm = blend(cd, cs, p)
    dt_, dh_ = compare(extremes(cm, t0, t1), CALIB_MARGATE)
    print(f"Margate fit w={p[0]:.2f}/{p[1]:.2f} k={p[2]:.2f}/{p[3]:.2f} datum {p[4]:.2f}: "
          f"time error RMS {np.sqrt(np.mean(dt_**2)):.1f} min (max {np.abs(dt_).max():.0f}), "
          f"height RMS {np.sqrt(np.mean(dh_**2)):.2f} m")
    for (t, h, k), a, b in zip(CALIB_MARGATE, dt_, dh_):
        print(f"   {k} {t} {h:.2f} m  -> {a:+.0f} min {b:+.2f} m")

    # 10 years of predictions, UTC days
    start = np.datetime64("2026-01-01T00:00")
    end = np.datetime64("2036-01-01T00:00")
    out = {}
    y = start
    while y < end:
        ny = min(y + np.timedelta64(31, "D"), end)
        t = np.arange(y, ny, np.timedelta64(10, "m"))
        h = utide.reconstruct(days(t), cm, verbose=False, epoch="1970-01-01").h
        ex = extremes(cm, y - np.timedelta64(60, "m"), ny + np.timedelta64(60, "m"))
        for i in range(0, len(t), 144):
            day = str(t[i])[:10]
            out.setdefault(day, {"h": None, "x": []})
            out[day]["h"] = np.round(h[i:i + 144] * 100).astype(np.int16)
        for et, eh, ek in ex:
            day = str(et)[:10]
            if day in out or (start <= et < end):
                m = int((et - np.datetime64(day + "T00:00")) / np.timedelta64(1, "m"))
                d = out.setdefault(day, {"h": None, "x": []})
                if not any(abs(m - mm) < 30 for mm, _, _ in d["x"]):
                    d["x"].append((m, int(round(eh * 100)), ek))
        y = ny
    out = {k: v for k, v in out.items() if v["h"] is not None and len(v["h"]) == 144}
    lowest = min(int(v["h"].min()) for v in out.values())
    print(f"{len(out)} days, lowest predicted {lowest / 100:.2f} m (chart datum ~ LAT)")
    meta = {
        "tide_station": "Margate (for Birchington)",
        "tide_datum": "Heights in metres above chart datum (about the lowest astronomical tide).",
        "tide_accuracy": (f"Predicted from Environment Agency gauges at Dover and Sheerness and placed at Margate; "
                          f"checked against published Margate times: typically within "
                          f"{max(10, int(np.ceil(np.sqrt(np.mean(dt_**2)) / 5) * 5))} minutes and "
                          f"{max(0.1, round(float(np.sqrt(np.mean(dh_**2))), 1)):.1f} m. Wind and air pressure "
                          f"can shift real tides by more. Not for navigation."),
        "tide_first_day": min(out), "tide_last_day": max(out),
    }
    with open(WORK / "tides.pkl", "wb") as f:
        pickle.dump({"days": out, "meta": meta}, f)


if __name__ == "__main__":
    main()

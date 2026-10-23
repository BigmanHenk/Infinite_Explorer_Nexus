"""Step 6 - the PC planner: one self-contained HTML page (planner/Explorer Planner.html) with the
same places, events, walks, tides and sunsets as the app. Plan in any browser, then send the
week to the iPhone by QR code (explorernexus:// link) or an .explorerplan file.

    python tools/build/s06_pc_planner.py
"""
import json
import sqlite3
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from common import CONTENT, ROOT, TOOLS

sys.path.insert(0, str(TOOLS / "build"))
LONDON = ZoneInfo("Europe/London")
OUT = ROOT / "planner" / "Explorer Planner.html"


def sunset(d):
    """Sunset (local HH:MM) at Birchington by stepping the NOAA altitude formula."""
    import math
    lat, lon = 51.377, 1.305

    def alt(t):
        jd = t.timestamp() / 86400 + 2440587.5
        n = (jd - 2451545.0) / 36525
        l0 = (280.46646 + n * (36000.76983 + n * 0.0003032)) % 360
        m = math.radians(357.52911 + n * (35999.05029 - 0.0001537 * n))
        c = math.sin(m) * (1.914602 - n * (0.004817 + 0.000014 * n)) + math.sin(2 * m) * (0.019993 - 0.000101 * n)
        lam = math.radians(l0 + c - 0.00569)
        eps = math.radians(23.439 - 0.013 * n)
        dec = math.asin(math.sin(eps) * math.sin(lam))
        e = 0.016708634
        y = math.tan(eps / 2) ** 2
        l0r = math.radians(l0)
        eq = 4 * math.degrees(y * math.sin(2 * l0r) - 2 * e * math.sin(m) + 4 * e * y * math.sin(m) * math.cos(2 * l0r))
        mins = (t.hour * 60 + t.minute + eq + 4 * lon) % 1440
        ha = math.radians(mins / 4 - 180)
        la = math.radians(lat)
        return math.degrees(math.asin(math.sin(la) * math.sin(dec) + math.cos(la) * math.cos(dec) * math.cos(ha)))

    t = datetime(d.year, d.month, d.day, 12, tzinfo=timezone.utc)
    prev = alt(t)
    for _ in range(12 * 60):
        t2 = t + timedelta(minutes=1)
        a = alt(t2)
        if prev > -0.833 >= a:
            return t2.astimezone(LONDON).strftime("%H:%M")
        prev, t = a, t2
    return None


def main():
    db = sqlite3.connect(CONTENT / "explorer.sqlite")
    q = lambda sql: db.execute(sql).fetchall()
    places = [dict(id=r[0], name=r[1], category=r[2], town=r[3], summary=r[4], tags=(r[5] or "").split(","),
                   subjects=(r[6] or "").split(","))
              for r in q("SELECT id, name, category, town, summary, tags, subjects FROM places ORDER BY name")]
    events = [dict(id=r[0], title=r[1], category=r[2], venue=r[3], town=r[4], start=r[5], end=r[6], start_time=r[7],
                   recurrence=json.loads(r[8]) if r[8] else None, confidence=r[9])
              for r in q("SELECT id, title, category, venue, town, start_date, end_date, start_time, recurrence, confidence FROM events")]
    walks = [dict(id=r[0], title=r[1], km=r[2], circular=bool(r[3]), tide=bool(r[4]), summary=r[5])
             for r in q("SELECT id, title, distance_km, circular, tide_warning IS NOT NULL, summary FROM walks ORDER BY distance_km")]
    built = (q("SELECT value FROM meta WHERE key = 'built'") or [("?",)])[0][0]

    # tides & sunsets, local days, from today - 7 to 15 months ahead
    start = date.today() - timedelta(days=7)
    end = start + timedelta(days=460)
    tides = {}
    for day, ex in q(f"SELECT day, extremes FROM tide_days WHERE day >= '{start - timedelta(days=1)}' AND day <= '{end}'"):
        base = datetime.fromisoformat(day).replace(tzinfo=timezone.utc)
        for part in (ex or "").split("|"):
            if not part:
                continue
            m, cm, k = part.split(":")
            t = (base + timedelta(minutes=int(m))).astimezone(LONDON)
            tides.setdefault(t.strftime("%Y-%m-%d"), []).append((t.strftime("%H:%M"), k, round(int(cm) / 100, 1)))
    for v in tides.values():
        v.sort()
    sunsets = {}
    d = start
    while d <= end:
        sunsets[d.isoformat()] = sunset(d)
        d += timedelta(days=1)

    data = dict(places=places, events=events, walks=walks, tides=tides, sunset=sunsets)
    html = (TOOLS / "build" / "planner_template.html").read_text(encoding="utf-8")
    qrlib = (TOOLS / "vendor" / "qrcode.min.js").read_text(encoding="utf-8")
    html = html.replace("__QRLIB__", qrlib).replace("__BUILT__", built)
    html = html.replace("__DATA__", json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/"))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html, encoding="utf-8")
    print(f"{OUT} ({OUT.stat().st_size / 1e3:.0f} kB): {len(places)} places, {len(events)} events, {len(walks)} walks, "
          f"{len(tides)} tide days")


if __name__ == "__main__":
    main()

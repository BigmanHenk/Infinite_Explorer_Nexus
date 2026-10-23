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
    photos = {}
    for owner, title, author, licence, page, url in q("SELECT owner, title, author, licence, page, url FROM photos ORDER BY owner, seq"):
        photos.setdefault(owner, []).append(dict(u=url, a=author, l=licence, p=page))
    pcols = ["id", "name", "category", "town", "lat", "lon", "summary", "description", "address", "postcode", "phone",
             "website", "opening_hours", "price", "dogs", "accessibility", "tips", "duration_min", "tags", "source_urls",
             "subjects", "best_time", "tide", "wildlife", "facilities", "hours_osm", "menu_url", "hygiene",
             "hygiene_date", "hygiene_url"]
    places = []
    for r in q("SELECT " + ", ".join(pcols) + " FROM places ORDER BY name"):
        d = {k: v for k, v in zip(pcols, r) if v not in (None, "")}
        d["tags"] = (d.get("tags") or "").split(",")
        d["subjects"] = (d.get("subjects") or "").split(",")
        d["source_urls"] = (d.get("source_urls") or "").split(chr(10))
        d["photos"] = photos.get(d["id"], [])
        places.append(d)
    ecols = ["id", "title", "category", "venue", "town", "lat", "lon", "start_date", "end_date", "start_time", "end_time",
             "recurrence", "price", "website", "booking", "description", "confidence", "source_urls"]
    events = []
    for r in q("SELECT " + ", ".join(ecols) + " FROM events"):
        d = {k: v for k, v in zip(ecols, r) if v not in (None, "")}
        d["start"], d["end"] = d.pop("start_date", None), d.pop("end_date", None)
        d["recurrence"] = json.loads(d["recurrence"]) if d.get("recurrence") else None
        d["source_urls"] = (d.get("source_urls") or "").split(chr(10))
        events.append(d)
    import struct
    wcols = ["id", "title", "distance_km", "duration_min", "difficulty", "surface", "circular", "start", "summary",
             "description", "toilets", "refreshments", "parking", "public_transport", "dogs", "accessibility",
             "tide_warning", "source_urls", "route"]
    walks = []
    for r in q("SELECT " + ", ".join(wcols) + " FROM walks ORDER BY distance_km"):
        d = {k: v for k, v in zip(wcols, r) if v not in (None, "")}
        blob = d.pop("route", b"") or b""
        d["route"] = [[round(a, 5), round(b, 5)] for a, b in struct.iter_unpack("<ff", blob)]
        d["km"] = d.pop("distance_km")
        d["circular"] = bool(d.get("circular"))
        d["tide"] = d.get("tide_warning")
        d["source_urls"] = (d.get("source_urls") or "").split(chr(10))
        d["points"] = [dict(name=a, lat=b, lon=c, note=e) for a, b, c, e in
                       db.execute("SELECT name, lat, lon, note FROM walk_points WHERE walk_id = ? ORDER BY seq", (d["id"],))]
        d["photos"] = photos.get("walk:" + d["id"], [])
        walks.append(d)
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

    streets = [[n, t, la, lo] for n, t, la, lo in q("SELECT name, town, lat, lon FROM streets")]
    data = dict(places=places, events=events, walks=walks, tides=tides, sunset=sunsets, streets=streets)
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

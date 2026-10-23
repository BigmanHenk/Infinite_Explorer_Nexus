"""Step 7 - photos for places, photo spots and walks from Wikimedia Commons (openly licensed,
credited). Writes tools/work/photos.json and caches images in tools/work/photos/.

    python tools/build/s07_photos.py [--limit N]

Per place: (1) the lead image of the English Wikipedia article about it (found by search,
accepted only when the article's coordinates are within 2 km), then (2) geotagged Commons
photos near the place whose title shares a significant word with the place name. Only CC BY,
CC BY-SA, CC0 and public-domain photos; each keeps photographer, licence and file page.
Walks get photos of their named waypoints the same way. Run s04 afterwards.
"""
import argparse
import hashlib
import html
import io
import json
import math
import re
import sqlite3
import time
import urllib.parse
import urllib.request

from PIL import Image

from common import CONTENT, RESEARCH, WORK

UA = "ExplorerNexusBuild/0.1 (https://github.com/BigmanHenk/Infinite_Explorer_Nexus)"
CACHE = WORK / "photos"
OUT = WORK / "photos.json"
STOP = set("""the a an of and at on in to by for with from road street lane way bay beach park house museum church
centre center hall gardens garden walk trail view point st saint sea on-sea kent margate ramsgate broadstairs
birchington westgate thanet herne canterbury station old new north south east west upper lower great little
cafe café pub inn bar restaurant shop market farm hotel""".split())
OK_LICENCE = re.compile(r"^(cc[- ]by(-sa)?[- ]?[0-9.]*|cc0|public domain|pd|attribution)", re.I)
_last = [0.0]


def get(url, params):
    wait = 0.25 - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    q = url + "?" + urllib.parse.urlencode({**params, "format": "json", "formatversion": 2})
    for attempt in range(5):
        try:
            req = urllib.request.Request(q, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as r:
                _last[0] = time.time()
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(10 * (attempt + 1))
                continue
            return {}
        except Exception:
            time.sleep(3)
    return {}


def hav(a, b, c, d):
    r = 6371000
    p1, p2 = math.radians(a), math.radians(c)
    x = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(d - b) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(x))


def words(s):
    return {w for w in re.findall(r"[a-z][a-z'-]{2,}", s.lower().replace("’", "'")) if w not in STOP}


def clean(s):
    s = re.sub(r"<[^>]+>", "", s or "")
    return html.unescape(s).strip()[:120]


def info(titles, width=1000):
    """imageinfo for File: titles -> list of dicts (only usable licences, real photos)."""
    if not titles:
        return []
    d = get("https://commons.wikimedia.org/w/api.php", {
        "action": "query", "titles": "|".join(titles[:40]), "prop": "imageinfo",
        "iiprop": "url|extmetadata|size|mime", "iiurlwidth": width})
    out = []
    for p in d.get("query", {}).get("pages", []):
        ii = (p.get("imageinfo") or [{}])[0]
        if not ii or ii.get("mime") not in ("image/jpeg", "image/png", "image/webp"):
            continue
        m = ii.get("extmetadata", {})
        lic = clean(m.get("LicenseShortName", {}).get("value", ""))
        if not OK_LICENCE.match(lic):
            continue
        if ii.get("width", 0) < 640 or ii.get("height", 0) < 400:
            continue
        out.append({
            "title": p["title"], "thumb": ii.get("thumburl") or ii.get("url"), "page": ii.get("descriptionurl"),
            "author": clean(m.get("Artist", {}).get("value", "")) or "Unknown", "licence": lic,
            "w": ii.get("width"), "h": ii.get("height"),
        })
    return out


def wiki_lead(name, town, lat, lon):
    d = get("https://en.wikipedia.org/w/api.php", {
        "action": "query", "list": "search", "srsearch": f"{name} {town}", "srlimit": 3})
    for hit in d.get("query", {}).get("search", []):
        t = hit["title"]
        want = words(name)
        if len(want & words(t)) < max(1, min(2, len(want))):
            continue
        p = get("https://en.wikipedia.org/w/api.php", {
            "action": "query", "titles": t, "prop": "coordinates|pageimages", "piprop": "name"})
        for pg in p.get("query", {}).get("pages", []):
            co = (pg.get("coordinates") or [{}])[0]
            if not co or hav(lat, lon, co["lat"], co["lon"]) > 2000:
                continue
            if pg.get("pageimage"):
                return "File:" + pg["pageimage"]
    return None


def nearby(name, lat, lon, radius, n):
    d = get("https://commons.wikimedia.org/w/api.php", {
        "action": "query", "list": "geosearch", "gscoord": f"{lat}|{lon}", "gsradius": radius,
        "gslimit": 60, "gsnamespace": 6})
    want = words(name)
    scored = []
    for g in d.get("query", {}).get("geosearch", []):
        t = g["title"]
        tl = t.lower()
        if any(x in tl for x in (".svg", " map", "plan of", "logo", "sign ", "diagram")):
            continue
        overlap = len(want & words(t))
        if overlap < min(2, len(want)) or overlap == 0:
            continue
        scored.append((-overlap, g["dist"], t))
    scored.sort()
    return [t for _, _, t in scored[: n * 3]]


def fetch(item):
    """Download + resize to <= 900 px wide JPEG; returns cache file name."""
    h = hashlib.sha1(item["title"].encode()).hexdigest()[:16] + ".jpg"
    path = CACHE / h
    if not path.exists():
        req = urllib.request.Request(item["thumb"], headers={"User-Agent": UA})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
                break
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(15 * (attempt + 1))
                    continue
                return None
            except Exception:
                time.sleep(3)
        else:
            return None
        im = Image.open(io.BytesIO(data)).convert("RGB")
        if im.width > 900:
            im = im.resize((900, round(im.height * 900 / im.width)), Image.LANCZOS)
        im.save(path, "JPEG", quality=72, optimize=True, progressive=True)
        time.sleep(0.2)
    return h


def photos_for(name, town, lat, lon, category, n=3):
    titles = []
    lead = wiki_lead(name, town, lat, lon) if category not in ("pub", "cafe", "restaurant", "food", "shop", "practical") else None
    if lead:
        titles.append(lead)
    radius = 600 if category in ("beach", "nature", "photo", "hide", "daytrip", "viewpoint") else 250
    for t in nearby(name, lat, lon, radius, n):
        if t not in titles:
            titles.append(t)
    got = []
    for it in info(titles):
        if len(got) >= n:
            break
        f = fetch(it)
        if f:
            it["file"] = f
            got.append(it)
    # keep the lead image first
    got.sort(key=lambda x: 0 if lead and x["title"] == lead else 1)
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    done = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {"places": {}, "walks": {}}
    db = sqlite3.connect(CONTENT / "explorer.sqlite")
    places = db.execute("SELECT id, name, town, lat, lon, category FROM places").fetchall()
    if args.limit:
        places = places[: args.limit]
    for i, (pid, name, town, lat, lon, cat) in enumerate(places):
        if pid in done["places"] or cat == "practical":
            continue
        ph = photos_for(name, town, lat, lon, cat, n=3 if cat not in ("pub", "cafe", "restaurant", "food", "shop") else 1)
        done["places"][pid] = ph
        print(f"[{i + 1}/{len(places)}] {name}: {len(ph)}", flush=True)
        if i % 10 == 0:
            OUT.write_text(json.dumps(done, indent=1), encoding="utf-8")
    walks = db.execute("SELECT id, title FROM walks").fetchall()
    for wid, title in walks:
        if wid in done["walks"]:
            continue
        pts = db.execute("SELECT seq, name, lat, lon FROM walk_points WHERE walk_id = ? ORDER BY seq", (wid,)).fetchall()
        got = []
        for seq, name, lat, lon in pts:
            if len(got) >= 6:
                break
            ph = photos_for(name, "", lat, lon, "sight", n=1)
            for p in ph:
                if all(p["title"] != g["title"] for g in got):
                    p["point"] = seq
                    got.append(p)
        done["walks"][wid] = got
        print(f"walk {title}: {len(got)}", flush=True)
        OUT.write_text(json.dumps(done, indent=1), encoding="utf-8")
    OUT.write_text(json.dumps(done, indent=1), encoding="utf-8")
    n = sum(len(v) for v in done["places"].values()) + sum(len(v) for v in done["walks"].values())
    with_photo = sum(1 for v in done["places"].values() if v)
    print(f"{n} photos; {with_photo}/{len(done['places'])} places have at least one")


if __name__ == "__main__":
    main()

"""Step 4 - build the app's offline database ios/ExplorerNexus/Content/explorer.sqlite and copy
the map tiles next to it.

    python tools/build/s04_database.py

Reads tools/research/*.json (places, events, walks, photo spots, practical facts) and
tools/work/tides.pkl. Each walk is routed along OpenStreetMap paths and streets between its
waypoints (walkers' graph from the Kent extract, footpaths preferred over main roads), so the
app can draw it and follow you along it without signal.
"""
import heapq
import json
import math
import pickle
import shutil
import sqlite3
import struct
import sys
from collections import defaultdict
from datetime import date

import osmium

from common import CONTENT, DETAIL, OSM_FILE, RESEARCH, WIDE, WORK

PLACE_FILES = ["places_birchington.json", "places_thanet.json", "places_food.json", "places_drink.json", "photo_spots.json", "places_wildlife_extra.json", "places_scenic_extra.json", "places_ev.json", "places_osm.json"]
EVENT_FILES = ["events_winter.json", "events_2027.json"]


def load(name):
    p = RESEARCH / name
    if not p.exists():
        print(f"  (missing {name})")
        return []
    return json.loads(p.read_text(encoding="utf-8"))


def in_wide(lat, lon):
    return lat is not None and lon is not None and WIDE[1] <= lat <= WIDE[3] and WIDE[0] <= lon <= WIDE[2]


# ---- walkers' graph -----------------------------------------------------------------------------
WALK_COST = {
    "footway": 0.85, "path": 0.85, "pedestrian": 0.85, "bridleway": 0.9, "steps": 1.0, "track": 0.95,
    "cycleway": 0.95, "living_street": 0.95, "residential": 1.0, "service": 1.0, "unclassified": 1.05,
    "road": 1.05, "tertiary": 1.15, "tertiary_link": 1.15, "secondary": 1.3, "secondary_link": 1.3,
    "primary": 1.5, "primary_link": 1.5, "trunk": 2.5, "trunk_link": 2.5,
}


class Graph(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.adj = defaultdict(list)
        self.pos = {}

    def way(self, w):
        hw = w.tags.get("highway")
        if hw not in WALK_COST or w.tags.get("foot") in ("no", "private") or w.tags.get("access") in ("private", "no") and w.tags.get("foot") not in ("yes", "designated", "permissive"):
            return
        nodes = []
        for n in w.nodes:
            if not n.location.valid():
                return
            nodes.append((n.ref, n.location.lat, n.location.lon))
        if not any(DETAIL[1] <= la <= DETAIL[3] and DETAIL[0] <= lo <= DETAIL[2] for _, la, lo in nodes):
            return
        f = WALK_COST[hw]
        for (a, la, loa), (b, lb, lob) in zip(nodes, nodes[1:]):
            d = hav(la, loa, lb, lob)
            self.pos[a] = (la, loa)
            self.pos[b] = (lb, lob)
            self.adj[a].append((b, d * f, d))
            self.adj[b].append((a, d * f, d))


def hav(la1, lo1, la2, lo2):
    r = 6371000.0
    p1, p2 = math.radians(la1), math.radians(la2)
    dp = p2 - p1
    dl = math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def big_component_nodes(adj, min_size=300):
    """Nodes in connected pieces of the network big enough to walk anywhere from
    (stray unconnected footway fragments would strand a route)."""
    seen = set()
    keep = set()
    for start in adj:
        if start in seen:
            continue
        comp = [start]
        seen.add(start)
        i = 0
        while i < len(comp):
            for v, _, _ in adj[comp[i]]:
                if v not in seen:
                    seen.add(v)
                    comp.append(v)
            i += 1
        if len(comp) >= min_size:
            keep.update(comp)
    return keep


class Snapper:
    def __init__(self, pos, adj):
        self.cell = defaultdict(list)
        big = big_component_nodes(adj)
        for n, (la, lo) in pos.items():
            if n in big:
                self.cell[(int(la * 500), int(lo * 300))].append(n)
        self.pos = pos

    def nearest(self, la, lo):
        ci, cj = int(la * 500), int(lo * 300)
        best = (1e18, None)
        for r in range(0, 6):
            for i in range(ci - r, ci + r + 1):
                for j in range(cj - r, cj + r + 1):
                    if max(abs(i - ci), abs(j - cj)) != r:
                        continue
                    for n in self.cell.get((i, j), []):
                        d = hav(la, lo, *self.pos[n])
                        if d < best[0]:
                            best = (d, n)
            if best[1] is not None and r >= 1:
                break
        return best


def astar(adj, pos, s, t):
    tl = pos[t]
    openh = [(0.0, 0.0, s)]
    g = {s: 0.0}
    prev = {}
    while openh:
        _, gc, u = heapq.heappop(openh)
        if u == t:
            break
        if gc > g.get(u, 1e18):
            continue
        for v, c, _ in adj[u]:
            ng = gc + c
            if ng < g.get(v, 1e18):
                g[v] = ng
                prev[v] = u
                h = hav(*pos[v], *tl) * 0.85
                heapq.heappush(openh, (ng + h, ng, v))
    if t not in g:
        return None
    path = [t]
    while path[-1] != s:
        path.append(prev[path[-1]])
    return path[::-1]


def route_walk(walk, adj, pos, snap):
    pts = walk.get("waypoints") or []
    coords = []
    problems = []
    for a, b in zip(pts, pts[1:]):
        da, na = snap.nearest(a["lat"], a["lon"])
        db, nb = snap.nearest(b["lat"], b["lon"])
        if na is None or nb is None:
            problems.append(f"no path near {a['name'] if na is None else b['name']}")
            seg = [(a["lat"], a["lon"]), (b["lat"], b["lon"])]
        else:
            if max(da, db) > 60:
                problems.append(f"waypoint {(a if da > db else b)['name']} is {max(da, db):.0f} m from any path")
            p = astar(adj, pos, na, nb)
            if p is None:
                problems.append(f"no connection {a['name']} -> {b['name']}")
                seg = [(a["lat"], a["lon"]), (b["lat"], b["lon"])]
            else:
                seg = [pos[n] for n in p]
                straight = hav(a["lat"], a["lon"], b["lat"], b["lon"])
                along = sum(hav(*x, *y) for x, y in zip(seg, seg[1:]))
                if straight > 80 and along > 2.2 * straight + 300:
                    problems.append(f"detour {a['name']} -> {b['name']}: {along:.0f} m for {straight:.0f} m straight")
        if coords and seg and coords[-1] == seg[0]:
            seg = seg[1:]
        coords += seg
    length = sum(hav(*x, *y) for x, y in zip(coords, coords[1:]))
    return coords, length, problems


def simplify(coords, tol_m=2.5):
    """Douglas-Peucker in local metres."""
    if len(coords) < 3:
        return coords
    lat0 = math.radians(coords[0][0])
    xy = [((lo - coords[0][1]) * 111320 * math.cos(lat0), (la - coords[0][0]) * 110540) for la, lo in coords]
    keep = [False] * len(coords)
    keep[0] = keep[-1] = True
    stack = [(0, len(coords) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay = xy[i]
        bx, by = xy[j]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        best, bi = 0.0, None
        for k in range(i + 1, j):
            px, py = xy[k]
            # start == end (circular walk): distance from the point itself
            d = abs(dy * (px - ax) - dx * (py - ay)) / L if L > 0.5 else math.hypot(px - ax, py - ay)
            if d > best:
                best, bi = d, k
        if bi is not None and best > tol_m:
            keep[bi] = True
            stack += [(i, bi), (bi, j)]
    return [c for c, k in zip(coords, keep) if k]


# ---- database -------------------------------------------------------------------------------------
def s(v):
    if v is None:
        return None
    if isinstance(v, bool):
        return "Yes" if v else "No"
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return str(v).strip() or None


def main():
    CONTENT.mkdir(parents=True, exist_ok=True)
    out = CONTENT / "explorer.sqlite"
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.executescript("""
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE places (id TEXT PRIMARY KEY, name TEXT, category TEXT, town TEXT, lat REAL, lon REAL,
        summary TEXT, description TEXT, address TEXT, postcode TEXT, phone TEXT, website TEXT, opening_hours TEXT,
        price TEXT, dogs TEXT, accessibility TEXT, tips TEXT, duration_min INTEGER, tags TEXT, source_urls TEXT,
        verified TEXT, subjects TEXT, best_time TEXT, tide TEXT, wildlife TEXT, facilities TEXT,
        hours_osm TEXT, menu_url TEXT, hygiene TEXT, hygiene_date TEXT, hygiene_url TEXT, drink TEXT);
    CREATE TABLE events (id TEXT PRIMARY KEY, title TEXT, category TEXT, venue TEXT, town TEXT, lat REAL, lon REAL,
        start_date TEXT, end_date TEXT, start_time TEXT, end_time TEXT, recurrence TEXT, price TEXT, website TEXT,
        booking TEXT, description TEXT, confidence TEXT, source_urls TEXT, verified TEXT);
    CREATE TABLE walks (id TEXT PRIMARY KEY, title TEXT, distance_km REAL, duration_min INTEGER, difficulty TEXT,
        surface TEXT, circular INTEGER, start TEXT, summary TEXT, description TEXT, toilets TEXT, refreshments TEXT,
        parking TEXT, public_transport TEXT, dogs TEXT, accessibility TEXT, tide_warning TEXT, source_urls TEXT,
        route BLOB);
    CREATE TABLE walk_points (walk_id TEXT, seq INTEGER, name TEXT, lat REAL, lon REAL, note TEXT);
    CREATE TABLE facts (topic TEXT, text TEXT);
    CREATE TABLE tide_days (day TEXT PRIMARY KEY, heights BLOB, extremes TEXT);
    CREATE TABLE photos (owner TEXT, seq INTEGER, point INTEGER, data BLOB, title TEXT, author TEXT, licence TEXT,
        page TEXT, url TEXT);
    CREATE INDEX photos_owner ON photos (owner);
    CREATE TABLE streets (name TEXT, town TEXT, lat REAL, lon REAL);
    CREATE TABLE parking (name TEXT, lat REAL, lon REAL, fee TEXT, capacity INTEGER, disabled INTEGER,
        operator TEXT, hours TEXT, maxstay TEXT, kind TEXT);
    """)

    # places
    seen = set()
    n_places = 0
    practical = load("practical.json")
    prac_places = practical.get("places", []) if isinstance(practical, dict) else practical
    facts = practical.get("facts", []) if isinstance(practical, dict) else []
    all_places = []
    for f in PLACE_FILES:
        all_places += load(f)
    all_places += prac_places
    def opt(name):
        f = RESEARCH / name
        return json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
    hours = opt("hours.json")        # structured opening_hours (OSM syntax) per id
    menus = opt("menus.json")
    hygiene = opt("hygiene.json")
    drinks = opt("drink_attributes.json")   # CAMRA / venue facts for pubs, taprooms
    # websites found dead or hijacked (menu research 2026-10-23)
    DEAD_SITES = ("conqueror-alehouse.co.uk", "thepubmicropub.com", "kakawaartisan.com")
    for p in all_places:
        if p.get("website") and any(d in p["website"] for d in DEAD_SITES):
            p["website"] = None
        pid = p.get("id")
        if not pid or pid in seen:
            continue
        if not in_wide(p.get("lat"), p.get("lon")):
            print(f"  place without usable coordinates skipped: {pid}")
            continue
        seen.add(pid)
        cat = p.get("category") or "sight"
        if cat == "takeaway":
            cat = "food"
        hy = hygiene.get(pid) or {}
        h_osm = hours.get(pid) or p.get("hours_osm") or (p.get("opening_hours") if cat == "ev" else None) or ("24/7" if cat == "ev" else None)
        db.execute("INSERT INTO places VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            pid, p.get("name"), cat, p.get("town") or "", p["lat"], p["lon"], s(p.get("summary")) or "",
            s(p.get("description")) or "", s(p.get("address")), s(p.get("postcode")), s(p.get("phone")),
            s(p.get("website")), s(p.get("opening_hours")), s(p.get("price")), s(p.get("dogs")),
            s(p.get("accessibility")), s(p.get("tips")),
            p.get("duration_min") if isinstance(p.get("duration_min"), int) else None,
            ",".join(p.get("tags") or []), "\n".join(p.get("source_urls") or []), p.get("verified"),
            ",".join(p.get("subjects") or []), s(p.get("best_time")), s(p.get("tide")), s(p.get("wildlife")),
            s(p.get("facilities")), h_osm, (menus.get(pid) or {}).get("menu_url"),
            str(hy["rating"]) if hy else None, hy.get("date"), hy.get("url"),
            json.dumps({k: v for k, v in drinks[pid].items() if k != "source_urls"}) if pid in drinks else None))
        n_places += 1
    for f in facts:
        db.execute("INSERT INTO facts VALUES (?,?)", (f.get("topic"), f.get("text")))

    # events
    n_events = 0
    seen = set()
    for f in EVENT_FILES:
        for e in load(f):
            eid = e.get("id")
            if not eid or eid in seen:
                continue
            seen.add(eid)
            lat, lon = e.get("lat"), e.get("lon")
            if not in_wide(lat, lon):
                lat = lon = None
            rec = e.get("recurrence")
            db.execute("INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                eid, e.get("title"), e.get("category") or "community", e.get("venue") or "", e.get("town") or "",
                lat, lon, e.get("start_date"), e.get("end_date"), e.get("start_time"), e.get("end_time"),
                json.dumps(rec) if rec else None, s(e.get("price")), s(e.get("website")), s(e.get("booking")),
                s(e.get("description")) or "", e.get("confidence") or "confirmed",
                "\n".join(e.get("source_urls") or []), e.get("verified")))
            n_events += 1

    # walks
    walks = load("walks.json")
    if walks:
        print("building walkers' graph ...")
        g = Graph()
        g.apply_file(str(OSM_FILE), locations=True)
        snap = Snapper(g.pos, g.adj)
        print(f"  {len(g.pos)} nodes")
        for w in walks:
            coords, length, problems = route_walk(w, g.adj, g.pos, snap)
            coords = simplify(coords)
            blob = b"".join(struct.pack("<ff", la, lo) for la, lo in coords)
            stated = w.get("distance_km") or 0
            flag = "" if not stated or abs(length / 1000 - stated) < max(0.6, 0.2 * stated) else "  <-- distance differs"
            print(f"  {w['id']}: routed {length / 1000:.1f} km (stated {stated}), {len(coords)} pts{flag}")
            for pr in problems:
                print(f"      ! {pr}")
            db.execute("INSERT INTO walks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                w["id"], w.get("title"), round(length / 1000, 1) if length > 0 else stated, w.get("duration_min"),
                w.get("difficulty") or "easy", s(w.get("surface")), 1 if w.get("circular") else 0, w.get("start") or "",
                s(w.get("summary")) or "", s(w.get("description")) or "", s(w.get("toilets")), s(w.get("refreshments")),
                s(w.get("parking")), s(w.get("public_transport")), s(w.get("dogs")), s(w.get("accessibility")),
                s(w.get("tide_warning")), "\n".join(w.get("source_urls") or []), blob))
            for i, p in enumerate(w.get("waypoints") or []):
                db.execute("INSERT INTO walk_points VALUES (?,?,?,?,?,?)",
                           (w["id"], i, p.get("name"), p.get("lat"), p.get("lon"), s(p.get("note"))))

    # tides
    tp = WORK / "tides.pkl"
    if tp.exists():
        t = pickle.load(open(tp, "rb"))
        for day, v in sorted(t["days"].items()):
            ex = "|".join(f"{m}:{cm}:{k}" for m, cm, k in sorted(v["x"]))
            db.execute("INSERT INTO tide_days VALUES (?,?,?)", (day, v["h"].astype("<i2").tobytes(), ex))
        for k, v in t["meta"].items():
            db.execute("INSERT INTO meta VALUES (?,?)", (k, v))
    else:
        print("  (no tides.pkl - run s03_tides.py)")

    # street index for map search: every named road/path in the detailed area, one point per
    # street and town (the middle of its longest piece), town = nearest village/town/suburb node
    fp = WORK / "features.pkl"
    if fp.exists():
        feats = pickle.load(open(fp, "rb"))
        towns = [(n, p.y, p.x) for k, n, p in feats["places"] if k in ("town", "village", "suburb", "hamlet", "city")]
        best = {}
        for kind, name, g in feats["features"]:
            if not name or kind not in ("road_major", "road_mid", "road_minor", "path", "track", "steps") or name[:1].isdigit():
                continue
            if len(name) <= 4 and name[:1] in "ABM" and name[1:2].isdigit():
                continue   # bare road numbers (A28) - not a street name
            lines = [g] if g.geom_type == "LineString" else list(getattr(g, "geoms", []))
            for l in lines:
                if l.is_empty:
                    continue
                c = l.interpolate(0.5, normalized=True)
                if not (WIDE[1] <= c.y <= WIDE[3] and WIDE[0] <= c.x <= WIDE[2]):
                    continue
                town = min(towns, key=lambda t: (t[1] - c.y) ** 2 + ((t[2] - c.x) * 0.62) ** 2)[0] if towns else ""
                key = (name, town)
                if key not in best or l.length > best[key][0]:
                    best[key] = (l.length, c.y, c.x)
        db.executemany("INSERT INTO streets VALUES (?,?,?,?)",
                       [(n, t, round(la, 6), round(lo, 6)) for (n, t), (_, la, lo) in sorted(best.items())])
        print(f"  {len(best)} streets in the search index")

    # public car parks (OpenStreetMap) - the apps pick the nearest few for each destination
    class Parks(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.rows = []

        def add(self, t, lat, lon):
            if t.get("amenity") != "parking" or t.get("access") in ("private", "no", "customers", "permit", "residents"):
                return
            if t.get("parking") in ("street_side", "lane", "on_kerb") and not t.get("name"):
                return
            if not (WIDE[1] <= lat <= WIDE[3] and WIDE[0] <= lon <= WIDE[2]):
                return
            try:
                cap = int(t.get("capacity", "0").split(";")[0])
            except ValueError:
                cap = 0
            if not t.get("name") and cap < 15:
                return
            try:
                dis = int(t.get("capacity:disabled", "0"))
            except ValueError:
                dis = 1 if t.get("capacity:disabled") == "yes" else 0
            fee = {"yes": "Pay & display", "no": "Free"}.get(t.get("fee", ""), t.get("fee"))
            if t.get("charge"):
                fee = (fee + " · " if fee else "") + t["charge"]
            self.rows.append((t.get("name") or "Car park", round(lat, 6), round(lon, 6), fee, cap or None, dis or None,
                              t.get("operator"), t.get("opening_hours"), t.get("maxstay"),
                              t.get("parking") or "surface"))

        def node(self, n):
            self.add(n.tags, n.location.lat, n.location.lon)

        def area(self, a):
            if a.tags.get("amenity") != "parking":
                return
            try:
                ring = next(iter(a.outer_rings()))
                pts = [(nd.lat, nd.lon) for nd in ring]
            except Exception:
                return
            self.add(a.tags, sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))

    pk = Parks()
    pk.apply_file(str(OSM_FILE), locations=True)
    db.executemany("INSERT INTO parking VALUES (?,?,?,?,?,?,?,?,?,?)", pk.rows)
    print(f"  {len(pk.rows)} public car parks")

    # photos (s07_photos.py): owner = place id or "walk:<id>"
    pj = WORK / "photos.json"
    n_photos = 0
    if pj.exists():
        ph = json.loads(pj.read_text(encoding="utf-8"))
        groups = [(k, v) for k, v in ph.get("places", {}).items()] + [("walk:" + k, v) for k, v in ph.get("walks", {}).items()]
        for owner, items in groups:
            for i, it in enumerate(items):
                f = WORK / "photos" / it.get("file", "")
                if not it.get("file") or not f.exists():
                    continue
                db.execute("INSERT INTO photos VALUES (?,?,?,?,?,?,?,?,?)", (
                    owner, i, it.get("point"), f.read_bytes(), it["title"], it["author"], it["licence"], it["page"], it["thumb"]))
                n_photos += 1
        print(f"  {n_photos} photos")
    else:
        print("  (no photos.json - run s07_photos.py)")

    db.execute("INSERT INTO meta VALUES ('built', ?)", (date.today().isoformat(),))
    db.execute("INSERT INTO meta VALUES ('version', '1')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{n_places} places, {n_events} events, {len(walks)} walks -> {out} ({out.stat().st_size / 1e6:.1f} MB)")

    # map tiles in three files (GitHub refuses single files over 100 MB): z9-15, z16, z17
    tiles = WORK / "map.sqlite"
    if tiles.exists():
        for old in list(CONTENT.glob("map*.sqlite")):
            old.unlink()
        src = sqlite3.connect(tiles)
        for name, lo, hi in (("map-a.sqlite", 0, 15), ("map-b.sqlite", 16, 16), ("map-c.sqlite", 17, 30)):
            dst_path = CONTENT / name
            if dst_path.exists():
                dst_path.unlink()
            dst = sqlite3.connect(dst_path)
            dst.execute("CREATE TABLE tiles (z INTEGER, x INTEGER, y INTEGER, data BLOB, PRIMARY KEY (z, x, y))")
            dst.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
            dst.executemany("INSERT INTO tiles VALUES (?,?,?,?)",
                            src.execute("SELECT z, x, y, data FROM tiles WHERE z BETWEEN ? AND ?", (lo, hi)))
            dst.executemany("INSERT INTO meta VALUES (?,?)", src.execute("SELECT key, value FROM meta"))
            dst.commit()
            dst.execute("VACUUM")
            dst.close()
            print(f"map tiles z{lo}-{min(hi, 17)} -> {name} ({dst_path.stat().st_size / 1e6:.0f} MB)")

if __name__ == "__main__":
    main()

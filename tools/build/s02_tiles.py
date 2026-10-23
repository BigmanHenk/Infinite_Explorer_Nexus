"""Step 2 - render the offline walking map into tools/work/map.sqlite (z, x, y, png).

    python tools/build/s02_tiles.py [--zooms 9-17] [--workers 6]

Standard 256-grid tile numbers, 512-px images (crisp on Retina; the app's MKTileOverlay keeps
tileSize 256). Rendered in 8x8 metatiles with a buffer; labels are placed once per zoom over
the whole map (collision-checked), then every metatile draws the ones that touch it, so names
are never cut at tile edges. PNGs are quantised to a 96-colour palette.
"""
import argparse
import io
import math
import pickle
import sqlite3
from multiprocessing import Pool

import cairo
import numpy as np
from PIL import Image
from shapely import affinity
from shapely.geometry import box, LineString, MultiLineString, Polygon, MultiPolygon, GeometryCollection
from shapely.strtree import STRtree

from common import WORK, DETAIL, WIDE, CORE, ZOOM_WIDE, ZOOM_DETAIL, ZOOM_CORE, TILE_PX

META = 8
BUF = 96  # px around a metatile so lines/labels continue over the edges

# ---- style ---------------------------------------------------------------------------------
LAND = (0.957, 0.945, 0.918)
AREA = {  # kind: (fill, stroke or None, min zoom)
    "farm": ((0.937, 0.945, 0.871), None, 11),
    "residential": ((0.925, 0.910, 0.886), None, 11),
    "commercial": ((0.949, 0.902, 0.886), None, 13),
    "industrial": ((0.918, 0.894, 0.910), None, 13),
    "airport": ((0.902, 0.898, 0.906), None, 10),
    "grass": ((0.855, 0.922, 0.788), None, 13),
    "park": ((0.800, 0.910, 0.722), None, 12),
    "golf": ((0.820, 0.910, 0.745), None, 12),
    "pitch": ((0.733, 0.871, 0.663), (0.62, 0.79, 0.56), 15),
    "allotments": ((0.851, 0.890, 0.761), None, 14),
    "cemetery": ((0.788, 0.863, 0.761), None, 13),
    "wood": ((0.706, 0.839, 0.627), None, 10),
    "scrub": ((0.780, 0.871, 0.690), None, 12),
    "reserve": (None, (0.38, 0.62, 0.36), 12),
    "sea": ((0.663, 0.827, 0.910), None, 0),
    "wetland": ((0.776, 0.871, 0.824), None, 11),
    "beach": ((0.965, 0.902, 0.725), None, 11),
    "mud": ((0.851, 0.831, 0.761), None, 11),
    "water": ((0.663, 0.827, 0.910), None, 11),
    "pier": ((0.86, 0.85, 0.83), (0.62, 0.60, 0.57), 13),
    "building": ((0.851, 0.816, 0.769), (0.773, 0.733, 0.682), 15),
}
AREA_ORDER = ["farm", "residential", "commercial", "industrial", "airport", "grass", "park", "golf",
              "allotments", "cemetery", "wood", "scrub", "sea", "wetland", "beach", "mud", "water",
              "pitch", "reserve", "pier", "building"]

# kind: (colour, casing colour, width px @z15 on a 512 tile, min zoom, dash)
LINE = {
    "stream": ((0.56, 0.76, 0.86), None, 1.4, 14, None),
    "river": ((0.56, 0.76, 0.86), None, 3.0, 11, None),
    "pier_line": ((0.60, 0.58, 0.55), None, 2.4, 14, None),
    "track": ((0.62, 0.48, 0.30), None, 2.2, 14, (6, 4)),
    "path": ((0.80, 0.30, 0.20), None, 2.4, 14, (5, 3.5)),
    "steps": ((0.80, 0.30, 0.20), None, 4.0, 15, (2, 2)),
    "road_minor": ((1.0, 1.0, 1.0), (0.80, 0.77, 0.72), 5.0, 13, None),
    "rail": ((0.55, 0.55, 0.58), None, 3.0, 10, None),
    "road_mid": ((0.992, 0.914, 0.659), (0.79, 0.70, 0.48), 7.0, 11, None),
    "road_major": ((0.969, 0.784, 0.451), (0.83, 0.61, 0.23), 8.5, 9, None),
}
LINE_ORDER = ["stream", "river", "pier_line", "track", "path", "steps", "road_minor", "rail", "road_mid", "road_major"]
PLACE_ZOOM = {"city": 9, "town": 10, "village": 12, "suburb": 13, "hamlet": 14, "neighbourhood": 15, "locality": 15}
PLACE_SIZE = {"city": 30, "town": 26, "village": 21, "suburb": 20, "hamlet": 18, "neighbourhood": 17, "locality": 17}
FONT = "Segoe UI"


def merc(lon, lat):
    x = (lon + 180.0) / 360.0
    s = math.sin(math.radians(lat))
    y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)
    return x, y


def to_merc(g):
    from shapely.ops import transform
    def f(x, y, z=None):
        x = np.asarray(x); y = np.asarray(y)
        mx = (x + 180.0) / 360.0
        s = np.sin(np.radians(y))
        my = 0.5 - np.log((1 + s) / (1 - s)) / (4 * math.pi)
        return mx, my
    return transform(f, g)


def tile_range(bb, z):
    n = 2 ** z
    x0, y1 = merc(bb[0], bb[1])
    x1, y0 = merc(bb[2], bb[3])
    return int(x0 * n), int(y0 * n), int(x1 * n), int(y1 * n)


def width_at(w15, z):
    return max(0.6, w15 * (2 ** ((z - 15) * 0.75)))


# ---- shared state per worker ------------------------------------------------------------------
G = {}


def init_worker(path):
    with open(path, "rb") as f:
        d = pickle.load(f)
    G.update(d)
    G["tree"] = STRtree([g for _, _, g in d["feats"]])


def iter_lines(g):
    if isinstance(g, LineString):
        yield g
    elif isinstance(g, (MultiLineString, GeometryCollection)):
        for p in g.geoms:
            yield from iter_lines(p)
    elif isinstance(g, Polygon):
        yield g.exterior
        for i in g.interiors:
            yield i
    elif isinstance(g, MultiPolygon):
        for p in g.geoms:
            yield from iter_lines(p)


def iter_polys(g):
    if isinstance(g, Polygon):
        yield g
    elif isinstance(g, (MultiPolygon, GeometryCollection)):
        for p in g.geoms:
            yield from iter_polys(p)


def render_meta(job):
    z, mx, my, labels = job
    n = 2 ** z
    W = n * TILE_PX
    size = META * TILE_PX + 2 * BUF
    ox = mx * META * TILE_PX - BUF
    oy = my * META * TILE_PX - BUF
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, size, size)
    c = cairo.Context(surf)
    c.set_source_rgb(*LAND)
    c.paint()
    q = box(ox / W, oy / W, (ox + size) / W, (oy + size) / W)
    idx = G["tree"].query(q)
    feats = [G["feats"][i] for i in idx]
    tol = 0.4 / W

    def px(coords):
        return [((x * W) - ox, (y * W) - oy) for x, y in coords]

    def path_line(coords):
        pts = px(coords)
        c.move_to(*pts[0])
        for p in pts[1:]:
            c.line_to(*p)

    by_kind = {}
    for kind, name, g in feats:
        by_kind.setdefault(kind, []).append(g)

    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    for kind in AREA_ORDER:
        fill, stroke, mz = AREA[kind]
        if z < mz:
            continue
        for g in by_kind.get(kind, []):
            g = g.intersection(q) if kind == "sea" else g
            g = g.simplify(tol, preserve_topology=True)
            for poly in iter_polys(g):
                if poly.is_empty:
                    continue
                if poly.area * W * W < 3 and kind != "sea":
                    continue
                c.new_path()
                for ring in [poly.exterior, *poly.interiors]:
                    path_line(ring.coords)
                    c.close_path()
                c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
                if fill:
                    c.set_source_rgb(*fill)
                    if stroke:
                        c.fill_preserve()
                    else:
                        c.fill()
                if stroke:
                    c.set_source_rgb(*stroke)
                    c.set_line_width(1.0 if kind != "reserve" else 2.0)
                    if kind == "reserve":
                        c.set_dash([8, 5])
                    c.stroke()
                    c.set_dash([])
                c.new_path()

    # casings first, then fills, so junctions merge
    for phase in ("casing", "fill"):
        for kind in LINE_ORDER:
            col, casing, w15, mz, dash = LINE[kind]
            if z < mz:
                continue
            if phase == "casing" and casing is None:
                continue
            w = width_at(w15, z)
            if kind in ("path", "track", "steps") and phase == "fill":
                # pale under-line so dashed paths read on any background
                c.set_source_rgba(1, 1, 1, 0.75)
                c.set_line_width(w + 2.2)
                c.set_dash([])
                for g in by_kind.get(kind, []):
                    for l in iter_lines(g.simplify(tol)):
                        path_line(l.coords)
                c.stroke()
            for g in by_kind.get(kind, []):
                for l in iter_lines(g.simplify(tol)):
                    path_line(l.coords)
            if phase == "casing":
                c.set_source_rgb(*casing)
                c.set_line_width(w + 2.4)
                c.set_dash([])
            else:
                c.set_source_rgb(*col)
                c.set_line_width(w)
                c.set_dash([d * max(1.0, w / 2.4) for d in dash] if dash else [])
            c.stroke()
            if kind == "rail" and phase == "fill" and z >= 13:
                for g in by_kind.get(kind, []):
                    for l in iter_lines(g.simplify(tol)):
                        path_line(l.coords)
                c.set_source_rgb(1, 1, 1)
                c.set_line_width(w * 0.45)
                c.set_dash([6, 6])
                c.stroke()
                c.set_dash([])

    # labels (already placed globally, in world px)
    for lab in labels:
        draw_label(c, lab, ox, oy)

    data = surf.get_data()
    arr = np.ndarray((size, size, 4), np.uint8, data, strides=(surf.get_stride(), 4, 1))
    rgb = arr[:, :, [2, 1, 0]].copy()
    out = []
    for ty in range(META):
        for tx in range(META):
            x = mx * META + tx
            y = my * META + ty
            if x >= n or y >= n:
                continue
            crop = rgb[BUF + ty * TILE_PX: BUF + (ty + 1) * TILE_PX, BUF + tx * TILE_PX: BUF + (tx + 1) * TILE_PX]
            im = Image.fromarray(crop).quantize(96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
            b = io.BytesIO()
            im.save(b, "PNG", optimize=True)
            out.append((z, x, y, b.getvalue()))
    return out


def draw_label(c, lab, ox, oy):
    text, x, y, ang, size, colour, halo = lab
    c.save()
    c.select_font_face(FONT, cairo.FONT_SLANT_NORMAL,
                       cairo.FONT_WEIGHT_BOLD if size >= 20 else cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(size)
    ext = c.text_extents(text)
    c.translate(x - ox, y - oy)
    c.rotate(ang)
    c.move_to(-ext.width / 2 - ext.x_bearing, size * 0.35)
    c.text_path(text)
    c.set_source_rgb(*halo)
    c.set_line_width(4.0)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.stroke_preserve()
    c.set_source_rgb(*colour)
    c.fill()
    c.restore()


# ---- global label placement ------------------------------------------------------------------
def text_width(text, size, bold):
    surf = cairo.ImageSurface(cairo.FORMAT_A8, 8, 8)
    c = cairo.Context(surf)
    c.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(size)
    return c.text_extents(text).x_advance


def place_labels(z, feats, places, bounds_px):
    W = (2 ** z) * TILE_PX
    taken = []  # AABBs
    out = []

    def free(bb):
        for t in taken:
            if bb[0] < t[2] and bb[2] > t[0] and bb[1] < t[3] and bb[3] > t[1]:
                return False
        return True

    def inside(x, y):
        return bounds_px[0] <= x <= bounds_px[2] and bounds_px[1] <= y <= bounds_px[3]

    # places by importance
    rank = ["city", "town", "village", "suburb", "hamlet", "neighbourhood", "locality"]
    for kind in rank:
        if z < PLACE_ZOOM[kind]:
            continue
        for k, name, (mx, my) in places:
            if k != kind:
                continue
            x, y = mx * W, my * W
            if not inside(x, y):
                continue
            size = PLACE_SIZE[kind] + (2 if z >= 15 else 0)
            w = text_width(name, size, size >= 20)
            bb = (x - w / 2 - 6, y - size, x + w / 2 + 6, y + size * 0.6)
            if free(bb):
                taken.append(bb)
                out.append((name, x, y, 0.0, size, (0.20, 0.20, 0.25), (1, 1, 1)))

    # road + path names along their longest straight piece
    if z >= 15:
        seen = {}
        lines = []
        for kind, name, g in feats:
            if not name or kind not in ("road_major", "road_mid", "road_minor", "path", "track"):
                continue
            if z == 15 and kind not in ("road_major", "road_mid"):
                continue
            lines.append((["road_major", "road_mid", "road_minor", "path", "track"].index(kind), kind, name, g))
        lines.sort(key=lambda t: t[0])
        size = 15 if z < 17 else 17
        for _, kind, name, g in lines:
            for l in iter_lines(g.simplify(2.0 / W)):
                pts = [(x * W, y * W) for x, y in l.coords]
                best = None
                for a, b in zip(pts, pts[1:]):
                    d = math.hypot(b[0] - a[0], b[1] - a[1])
                    if best is None or d > best[0]:
                        best = (d, a, b)
                if not best:
                    continue
                d, a, b = best
                w = text_width(name, size, False)
                if d < w + 24:
                    continue
                x, y = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
                if not inside(x, y):
                    continue
                key = name
                if any(math.hypot(x - px_, y - py_) < 900 for px_, py_ in seen.get(key, [])):
                    continue
                ang = math.atan2(b[1] - a[1], b[0] - a[0])
                if ang > math.pi / 2:
                    ang -= math.pi
                if ang < -math.pi / 2:
                    ang += math.pi
                hw = abs(math.cos(ang)) * w / 2 + abs(math.sin(ang)) * size / 2 + 3
                hh = abs(math.sin(ang)) * w / 2 + abs(math.cos(ang)) * size / 2 + 3
                bb = (x - hw, y - hh, x + hw, y + hh)
                if not free(bb):
                    continue
                taken.append(bb)
                seen.setdefault(key, []).append((x, y))
                colour = (0.55, 0.22, 0.14) if kind in ("path", "track") else (0.25, 0.25, 0.28)
                out.append((name, x, y, ang, size, colour, (1, 1, 1)))
    # water / park / wood names
    if z >= 15:
        for kind, name, g in feats:
            if not name or kind not in ("park", "wood", "water", "reserve", "golf", "beach", "cemetery"):
                continue
            a = g.area * W * W
            if a < 60000:
                continue
            p = g.representative_point()
            x, y = p.x * W, p.y * W
            if not inside(x, y):
                continue
            size = 15
            w = text_width(name, size, False)
            bb = (x - w / 2 - 4, y - size, x + w / 2 + 4, y + size * 0.6)
            if free(bb):
                taken.append(bb)
                col = (0.15, 0.40, 0.60) if kind in ("water", "beach") else (0.20, 0.45, 0.22)
                out.append((name, x, y, 0.0, size, col, (1, 1, 1)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zooms", default="9-17")
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args()
    z0, z1 = (int(v) for v in args.zooms.split("-"))

    with open(WORK / "features.pkl", "rb") as f:
        d = pickle.load(f)
    feats = [(k, n, to_merc(g)) for k, n, g in d["features"]]
    places = [(k, n, merc(p.x, p.y)) for k, n, p in d["places"]]
    mp = WORK / "features_merc.pkl"
    with open(mp, "wb") as f:
        pickle.dump({"feats": feats}, f)

    db_path = WORK / "map.sqlite"
    db = sqlite3.connect(db_path)
    db.execute("CREATE TABLE IF NOT EXISTS tiles (z INTEGER, x INTEGER, y INTEGER, data BLOB, PRIMARY KEY (z, x, y))")
    db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")

    with Pool(args.workers, initializer=init_worker, initargs=(str(mp),)) as pool:
        for z in range(z0, z1 + 1):
            bb = WIDE if z in ZOOM_WIDE else (CORE if z >= ZOOM_CORE else DETAIL)
            x0, y0, x1, y1 = tile_range(bb, z)
            bounds_px = (x0 * TILE_PX, y0 * TILE_PX, (x1 + 1) * TILE_PX, (y1 + 1) * TILE_PX)
            # label features: only those inside this zoom's box
            labels = place_labels(z, feats, places, bounds_px)
            jobs = []
            for my in range(y0 // META, y1 // META + 1):
                for mx in range(x0 // META, x1 // META + 1):
                    lo_x = mx * META * TILE_PX - BUF - 300
                    lo_y = my * META * TILE_PX - BUF - 300
                    hi_x = (mx + 1) * META * TILE_PX + BUF + 300
                    hi_y = (my + 1) * META * TILE_PX + BUF + 300
                    mine = [l for l in labels if lo_x <= l[1] <= hi_x and lo_y <= l[2] <= hi_y]
                    jobs.append((z, mx, my, mine))
            count = 0
            nbytes = 0
            db.execute("DELETE FROM tiles WHERE z = ?", (z,))
            for res in pool.imap_unordered(render_meta, jobs):
                for zz, x, y, png in res:
                    if x0 <= x <= x1 and y0 <= y <= y1:
                        db.execute("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", (zz, x, y, png))
                        count += 1
                        nbytes += len(png)
            db.commit()
            print(f"z{z}: {count} tiles, {nbytes / 1e6:.1f} MB, {len(labels)} labels", flush=True)
            db.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", (f"range_z{z}", f"{x0},{y0},{x1},{y1}"))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('minzoom', ?)", (str(z0),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('maxzoom', ?)", (str(z1),))
    db.execute("INSERT OR REPLACE INTO meta VALUES ('attribution', ?)", ("© OpenStreetMap contributors (ODbL)",))
    db.commit()
    db.execute("VACUUM")
    db.close()


if __name__ == "__main__":
    main()

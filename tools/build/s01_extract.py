"""Step 1 - pull the map features out of the Geofabrik Kent extract.

    python tools/build/s01_extract.py            (needs tools/osm/kent.osm.pbf)

Writes tools/work/features.pkl: a list of (kind, name, shapely geometry) in WGS84, plus the
sea polygons built from the coastline. Detailed features (buildings, paths, small roads)
only inside DETAIL; the wider WIDE box keeps the big things for the low zoom levels.
"""
import pickle
import sys
from pathlib import Path

import osmium
import shapely
from shapely import wkb
from shapely.geometry import box, LineString, Point
from shapely.ops import linemerge, split, unary_union

from common import DETAIL, DETAIL_BOXES, WIDE, WORK, OSM_FILE

detail_box = unary_union([box(*b) for b in DETAIL_BOXES])
wide_box = box(*WIDE)

ROAD_MAJOR = {"motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"}
ROAD_MID = {"secondary", "tertiary", "secondary_link", "tertiary_link"}
ROAD_MINOR = {"residential", "unclassified", "living_street", "service", "road"}
PATHS = {"footway", "path", "bridleway", "cycleway", "steps", "pedestrian", "track"}

GREEN = {
    ("leisure", "park"): "park", ("leisure", "garden"): "park", ("leisure", "recreation_ground"): "park",
    ("leisure", "playground"): "park", ("leisure", "pitch"): "pitch", ("leisure", "golf_course"): "golf",
    ("leisure", "nature_reserve"): "reserve", ("landuse", "grass"): "grass", ("landuse", "village_green"): "park",
    ("landuse", "recreation_ground"): "park", ("landuse", "meadow"): "grass", ("landuse", "cemetery"): "cemetery",
    ("amenity", "grave_yard"): "cemetery", ("landuse", "allotments"): "allotments",
    ("landuse", "forest"): "wood", ("natural", "wood"): "wood", ("natural", "scrub"): "scrub",
    ("natural", "grassland"): "grass", ("natural", "heath"): "scrub",
    ("natural", "beach"): "beach", ("natural", "sand"): "beach", ("natural", "shingle"): "beach",
    ("natural", "wetland"): "wetland", ("natural", "mud"): "mud",
    ("natural", "water"): "water", ("landuse", "reservoir"): "water", ("landuse", "basin"): "water",
    ("leisure", "swimming_pool"): "water",
    ("landuse", "farmland"): "farm", ("landuse", "orchard"): "farm", ("landuse", "vineyard"): "farm",
    ("landuse", "residential"): "residential", ("landuse", "commercial"): "commercial",
    ("landuse", "retail"): "commercial", ("landuse", "industrial"): "industrial",
    ("aeroway", "aerodrome"): "airport",
    ("man_made", "pier"): "pier",
}
WIDE_AREAS = {"wood", "water", "residential", "airport", "beach", "mud", "wetland", "reserve", "golf", "park"}


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.wkb = osmium.geom.WKBFactory()
        self.out = []
        self.coast = []
        self.places = []

    def node(self, n):
        t = n.tags
        place = t.get("place")
        if place in ("city", "town", "village", "hamlet", "suburb", "neighbourhood", "locality") and "name" in t:
            p = Point(n.location.lon, n.location.lat)
            if wide_box.contains(p):
                self.places.append((place, t["name"], p))

    def way(self, w):
        t = w.tags
        if t.get("natural") == "coastline":
            try:
                g = wkb.loads(self.wkb.create_linestring(w), hex=True)
            except Exception:
                return
            if g.intersects(wide_box):
                self.coast.append(g)
            return
        hw = t.get("highway")
        rw = t.get("railway")
        ww = t.get("waterway")
        mm = t.get("man_made")
        kind = None
        if hw in ROAD_MAJOR:
            kind = "road_major"
        elif hw in ROAD_MID:
            kind = "road_mid"
        elif hw in ROAD_MINOR:
            kind = "road_minor"
        elif hw in PATHS and t.get("footway") in ("sidewalk", "crossing"):
            return   # pavements beside roads: the road already shows the way
        elif hw in PATHS:
            kind = "steps" if hw == "steps" else ("track" if hw == "track" else "path")
        elif rw == "rail":
            kind = "rail"
        elif ww in ("river", "canal"):
            kind = "river"
        elif ww in ("stream", "drain", "ditch"):
            kind = "stream"
        elif mm in ("pier", "groyne", "breakwater") or t.get("barrier") == "sea_wall":
            kind = "pier_line"
        if kind is None or w.is_closed() and kind not in ("road_minor", "path", "pier_line"):
            if kind is None:
                return
        try:
            g = wkb.loads(self.wkb.create_linestring(w), hex=True)
        except Exception:
            return
        # all roads and paths across the whole area (street-level map z13-15 everywhere)
        if not g.intersects(wide_box):
            return
        self.out.append((kind, t.get("name") or t.get("ref") or "", g))

    def area(self, a):
        t = a.tags
        kind = None
        if "building" in t:
            kind = "building"
        else:
            for (k, v), name in GREEN.items():
                if t.get(k) == v:
                    kind = name
                    break
        if kind is None:
            return
        try:
            g = wkb.loads(self.wkb.create_multipolygon(a), hex=True)
        except Exception:
            return
        if not g.is_valid:
            g = g.buffer(0)
        test = detail_box if kind == "building" else wide_box   # buildings only where we draw z16
        if not g.intersects(test):
            return
        self.out.append((kind, t.get("name", ""), g))


def build_sea(coast_lines):
    """Split the WIDE box by the coastline; OSM coastline has the sea on its RIGHT."""
    merged = linemerge(unary_union(coast_lines))
    lines = list(merged.geoms) if hasattr(merged, "geoms") else [merged]
    lines = [l for l in lines if l.intersects(wide_box)]
    parts = split(wide_box, unary_union(lines + [wide_box.exterior]))
    sea = []
    cl = unary_union(lines)
    for poly in parts.geoms:
        p = poly.representative_point()
        # nearest coastline segment: sea if the point is right of the way direction
        best = None
        for l in lines:
            d = l.distance(p)
            if best is None or d < best[0]:
                best = (d, l)
        line = best[1]
        s = line.project(p)
        a = line.interpolate(max(0.0, s - 1e-5))
        b = line.interpolate(min(line.length, s + 1e-5))
        q = line.interpolate(s)
        cross = (b.x - a.x) * (p.y - q.y) - (b.y - a.y) * (p.x - q.x)
        if cross < 0:
            sea.append(poly)
    return unary_union(sea)


def main():
    if not OSM_FILE.exists():
        sys.exit(f"missing {OSM_FILE}")
    h = Handler()
    h.apply_file(str(OSM_FILE), locations=True)
    print(f"features {len(h.out)}, coast ways {len(h.coast)}, places {len(h.places)}")
    sea = build_sea(h.coast)
    print("sea area (deg2)", round(sea.area, 4))
    feats = [("sea", "", sea)] + h.out
    WORK.mkdir(parents=True, exist_ok=True)
    with open(WORK / "features.pkl", "wb") as f:
        pickle.dump({"features": feats, "places": h.places}, f)
    from collections import Counter
    print(Counter(k for k, _, _ in feats).most_common())


if __name__ == "__main__":
    main()

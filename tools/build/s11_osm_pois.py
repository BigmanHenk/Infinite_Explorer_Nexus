"""Step 11 - every named place of interest in East Kent from OpenStreetMap (attractions, heritage,
nature, food & drink, shops, markets), so the map and search cover the whole area - not only the
places researched by hand. Entries already in the researched files are skipped.

    python tools/build/s11_osm_pois.py   -> tools/research/places_osm.json   (then run s04)

Each entry says it comes from OpenStreetMap and keeps the OSM opening_hours, website and phone.
"""
import difflib
import json
import math
import re

import osmium

from common import OSM_FILE, RESEARCH, WIDE

RESEARCHED = ["places_birchington.json", "places_thanet.json", "places_food.json", "places_drink.json",
              "photo_spots.json", "places_wildlife_extra.json", "places_scenic_extra.json"]

SHOP_LABEL = {
    "supermarket": "Supermarket", "convenience": "Convenience store", "bakery": "Bakery", "butcher": "Butcher",
    "deli": "Delicatessen", "farm": "Farm shop", "greengrocer": "Greengrocer", "seafood": "Fishmonger",
    "cheese": "Cheese shop", "chocolate": "Chocolatier", "confectionery": "Sweet shop", "wine": "Wine shop",
    "alcohol": "Off-licence", "beverages": "Drinks shop", "coffee": "Coffee shop (beans)", "tea": "Tea shop",
    "gift": "Gift shop", "books": "Bookshop", "antiques": "Antiques", "art": "Art shop / gallery", "craft": "Craft shop",
    "clothes": "Clothes", "shoes": "Shoes", "boutique": "Boutique", "jewelry": "Jeweller", "department_store": "Department store",
    "mall": "Shopping centre", "garden_centre": "Garden centre", "charity": "Charity shop", "second_hand": "Second-hand",
    "vintage": "Vintage", "outdoor": "Outdoor gear", "sports": "Sports", "bicycle": "Bike shop", "toys": "Toys",
    "music": "Music", "musical_instrument": "Musical instruments", "camera": "Camera shop", "photo": "Photo shop",
    "games": "Games", "hobby": "Hobby", "variety_store": "Variety store", "pharmacy": "Pharmacy",
    "chemist": "Chemist", "newsagent": "Newsagent", "fishing": "Fishing tackle", "surf": "Surf shop", "frame": "Framer",
    "interior_decoration": "Homeware", "houseware": "Homeware", "furniture": "Furniture", "pottery": "Pottery",
}
FOOD = {"pub": "pub", "bar": "pub", "biergarten": "pub", "cafe": "cafe", "restaurant": "restaurant",
        "fast_food": "food", "ice_cream": "food"}
TOURISM = {"museum": "museum", "gallery": "museum", "attraction": "sight", "viewpoint": "viewpoint", "zoo": "family",
           "theme_park": "family", "aquarium": "family", "picnic_site": "nature"}
HISTORIC = {"castle": "history", "ruins": "history", "fort": "history", "archaeological_site": "history",
            "manor": "history", "monastery": "history", "city_gate": "history", "tower": "history", "building": "history",
            "ship": "history", "lighthouse": "history", "windmill": "history", "church": "church", "abbey": "history"}
LEISURE = {"nature_reserve": "nature", "park": "nature", "garden": "nature", "bird_hide": "hide",
           "beach_resort": "beach", "golf_course": "sight", "water_park": "family", "miniature_golf": "family"}


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", (s or "").lower().replace("&", "and")).replace("the ", "").strip()


def hav(a, b, c, d):
    p1, p2 = math.radians(a), math.radians(c)
    x = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(d - b) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(x))


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.out = {}

    def take(self, t, lat, lon, oid, area_m2=0):
        name = t.get("name")
        if not name or not (WIDE[1] <= lat <= WIDE[3] and WIDE[0] <= lon <= WIDE[2]):
            return
        if t.get("access") in ("private", "no"):
            return
        cat, label = None, None
        if t.get("amenity") in FOOD:
            cat = FOOD[t["amenity"]]
            label = {"pub": "Pub", "bar": "Bar", "biergarten": "Beer garden", "cafe": "Café", "restaurant": "Restaurant",
                     "fast_food": "Takeaway", "ice_cream": "Ice cream"}[t["amenity"]]
            if t.get("cuisine"):
                label += " · " + t["cuisine"].replace(";", ", ").replace("_", " ")
        elif t.get("craft") in ("brewery", "winery", "distillery", "cider"):
            cat = "vineyard" if t["craft"] == "winery" else "brewery"
            label = {"brewery": "Brewery", "winery": "Winery", "distillery": "Distillery", "cider": "Cider maker"}[t["craft"]]
        elif t.get("landuse") == "vineyard" and name:
            cat, label = "vineyard", "Vineyard"
        elif t.get("amenity") == "marketplace":
            cat, label = "market", "Market"
        elif t.get("shop") in SHOP_LABEL:
            cat, label = "shop", SHOP_LABEL[t["shop"]]
        elif t.get("tourism") in TOURISM:
            cat = TOURISM[t["tourism"]]
            label = t["tourism"].replace("_", " ").capitalize()
        elif t.get("historic") in HISTORIC:
            cat = HISTORIC[t["historic"]]
            label = "Historic " + t["historic"].replace("_", " ")
        elif t.get("man_made") in ("windmill", "lighthouse"):
            cat, label = "history", t["man_made"].capitalize()
        elif t.get("leisure") in LEISURE:
            if t["leisure"] == "park" and area_m2 and area_m2 < 15000:
                return   # pocket parks
            cat = LEISURE[t["leisure"]]
            label = t["leisure"].replace("_", " ").capitalize()
        elif t.get("natural") == "beach":
            cat, label = "beach", "Beach"
        if not cat:
            return
        town = t.get("addr:city") or t.get("addr:town") or t.get("addr:village") or t.get("addr:suburb") or ""
        desc = [f"{label}{' in ' + town if town else ''} (from OpenStreetMap)."]
        if t.get("description"):
            desc.append(t["description"])
        if t.get("real_ale") == "yes":
            desc.append("Serves real ale.")
        if t.get("microbrewery") == "yes":
            desc.append("Has its own microbrewery.")
        if t.get("heritage") or t.get("heritage:operator"):
            desc.append("Listed heritage site.")
        if t.get("operator"):
            desc.append(f"Run by {t['operator']}.")
        if t.get("wheelchair") == "yes":
            desc.append("Wheelchair accessible.")
        tags = ["osm"]
        if t.get("real_ale") == "yes":
            tags.append("real-ale")
        if t.get("dog") == "yes":
            tags.append("dogs")
        if t.get("wheelchair") == "yes":
            tags.append("wheelchair")
        if t.get("fee") == "no" and cat in ("museum", "nature", "history", "viewpoint", "beach"):
            tags.append("free")
        key = oid
        self.out[key] = {
            "id": "osm-" + oid.replace("/", "-"),
            "name": name, "category": cat, "town": town,
            "lat": round(lat, 6), "lon": round(lon, 6),
            "summary": label + (f" · {town}" if town else ""),
            "description": " ".join(desc),
            "address": " ".join(x for x in (t.get("addr:housenumber"), t.get("addr:street")) if x) or None,
            "postcode": t.get("addr:postcode"),
            "phone": t.get("phone") or t.get("contact:phone"),
            "website": t.get("website") or t.get("contact:website") or t.get("url"),
            "opening_hours": t.get("opening_hours"),
            "hours_osm": t.get("opening_hours") or ("24/7" if cat in ("viewpoint", "beach") else None),
            "price": None, "dogs": None, "accessibility": "Wheelchair accessible" if t.get("wheelchair") == "yes" else None,
            "tips": None, "duration_min": None, "tags": tags,
            "source_urls": [f"https://www.openstreetmap.org/{oid.replace('area/', 'way/')}"],
            "verified": "2026-10-24",
        }

    def node(self, n):
        if n.tags.get("name"):
            self.take(n.tags, n.location.lat, n.location.lon, f"node/{n.id}")

    def area(self, a):
        if not a.tags.get("name"):
            return
        try:
            ring = next(iter(a.outer_rings()))
            pts = [(nd.lat, nd.lon) for nd in ring]
        except Exception:
            return
        lat = sum(p[0] for p in pts) / len(pts)
        lon = sum(p[1] for p in pts) / len(pts)
        # rough area for the pocket-park filter
        x = [(p[1] - lon) * 69000 for p in pts]
        y = [(p[0] - lat) * 111000 for p in pts]
        area = abs(sum(x[i] * y[i - 1] - x[i - 1] * y[i] for i in range(len(pts)))) / 2
        oid = f"way/{a.orig_id()}" if a.from_way() else f"relation/{a.orig_id()}"
        self.take(a.tags, lat, lon, oid, area)


def main():
    known = []
    for f in RESEARCHED:
        p = RESEARCH / f
        if p.exists():
            known += [(norm(x["name"]), x.get("lat"), x.get("lon")) for x in json.loads(p.read_text(encoding="utf-8")) if x.get("lat")]
    h = H()
    h.apply_file(str(OSM_FILE), locations=True)
    # town for entries without an address: the nearest town/village/suburb node
    import pickle
    from common import WORK
    feats = pickle.load(open(WORK / "features.pkl", "rb"))
    towns = [(n, p.y, p.x) for k, n, p in feats["places"] if k in ("town", "village", "suburb", "city")]
    for e in h.out.values():
        if not e["town"] and towns:
            e["town"] = min(towns, key=lambda t: (t[1] - e["lat"]) ** 2 + ((t[2] - e["lon"]) * 0.62) ** 2)[0]
            e["summary"] = e["summary"] + " · " + e["town"]
            e["description"] = e["description"].replace(" (from OpenStreetMap).", f" near {e['town']} (from OpenStreetMap).", 1)
    out = []
    dup = 0
    for e in h.out.values():
        n = norm(e["name"])
        if any(k[1] and hav(e["lat"], e["lon"], k[1], k[2]) < 250 and
               (n in k[0] or k[0] in n or difflib.SequenceMatcher(None, n, k[0]).ratio() > 0.7) for k in known):
            dup += 1
            continue
        out.append(e)
    (RESEARCH / "places_osm.json").write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
    from collections import Counter
    print(f"{len(out)} OSM places ({dup} skipped as already researched)")
    print(Counter(e["category"] for e in out).most_common())


if __name__ == "__main__":
    main()

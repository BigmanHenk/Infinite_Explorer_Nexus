"""Step 9 - EV charge points from OpenStreetMap, marked where the Allstar EV card is accepted.

    python tools/build/s09_ev.py      (needs tools/research/allstar_networks.json)

Writes tools/research/places_ev.json (category "ev"; tag "allstar" when the station's operator,
network or brand matches a network Allstar lists). Run s04 afterwards.
"""
import json
import re
import sys

import osmium

from common import OSM_FILE, RESEARCH, WIDE

KW = {"type2": "Type 2", "type2_combo": "CCS", "chademo": "CHAdeMO", "type2_cable": "Type 2 (tethered)",
      "tesla_supercharger": "Tesla", "type1": "Type 1", "type1_combo": "CCS1", "uk": "3-pin UK"}


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.out = []

    def _add(self, tags, lat, lon, oid):
        if tags.get("amenity") != "charging_station":
            return
        if not (WIDE[1] <= lat <= WIDE[3] and WIDE[0] <= lon <= WIDE[2]):
            return
        if tags.get("access") in ("private", "no", "customers") and tags.get("access") != "yes":
            if tags.get("access") in ("private", "no"):
                return
        self.out.append({"osm": oid, "lat": round(lat, 6), "lon": round(lon, 6), **{k: v for k, v in tags}})

    def node(self, n):
        self._add(n.tags, n.location.lat, n.location.lon, f"node/{n.id}")

    def area(self, a):
        if a.tags.get("amenity") != "charging_station":
            return
        try:
            ring = next(iter(a.outer_rings()))
            pts = [(nd.lat, nd.lon) for nd in ring]
            lat = sum(p[0] for p in pts) / len(pts)
            lon = sum(p[1] for p in pts) / len(pts)
        except Exception:
            return
        self._add(a.tags, lat, lon, f"area/{a.orig_id()}")


def sockets(t):
    out = []
    for k, label in KW.items():
        v = t.get(f"socket:{k}")
        if v and v not in ("no", "0"):
            power = t.get(f"socket:{k}:output") or ""
            out.append(f"{label}{' ×' + v if v.isdigit() and v != '1' else ''}{' ' + power if power else ''}")
    return ", ".join(out)


def main():
    nets = json.loads((RESEARCH / "allstar_networks.json").read_text(encoding="utf-8"))
    h = H()
    h.apply_file(str(OSM_FILE), locations=True)
    places = []
    allstar = 0
    for t in h.out:
        who = " ".join(t.get(k, "") for k in ("operator", "network", "brand", "name")).lower()
        # whole words only: short names ("mer", "raw", "source") must not match inside other words
        net = next((n for n in nets["networks"]
                    if any(re.search(r"(?<![a-z])" + re.escape(m) + r"(?![a-z])", who) for m in n["match"])), None)
        operator = t.get("network") or t.get("operator") or t.get("brand") or "Unknown operator"
        name = t.get("name") or (t.get("brand") or operator) + " charge point"
        sk = sockets(t)
        cap = t.get("capacity")
        summary = (f"{operator}: " + (sk or "connectors not recorded") + (f"; {cap} bays" if cap else "")
                   + (" — Allstar card accepted" if net else ""))[:200]
        desc = [f"Public EV charge point operated by {operator} (OpenStreetMap)."]
        if net:
            desc.append(f"Allstar lists the {net['name']} network as accepted" + (f" ({net['notes']})" if net.get("notes") else "") + ".")
        else:
            desc.append("This network is not on Allstar's accepted list, so pay by the operator's app or contactless.")
        if t.get("fee"):
            desc.append(f"Fee: {t['fee']}.")
        if t.get("charge"):
            desc.append(f"Price: {t['charge']}.")
        if t.get("payment:contactless") == "yes":
            desc.append("Contactless payment.")
        if net:
            allstar += 1
        places.append({
            "id": "ev-" + t["osm"].replace("/", "-"),
            "name": name,
            "category": "ev",
            "town": t.get("addr:city") or t.get("addr:town") or t.get("addr:suburb") or "",
            "lat": t["lat"], "lon": t["lon"],
            "summary": summary,
            "description": " ".join(desc),
            "address": " ".join(x for x in (t.get("addr:housenumber"), t.get("addr:street")) if x) or None,
            "postcode": t.get("addr:postcode"),
            "phone": t.get("phone") or t.get("contact:phone"),
            "website": t.get("website") or t.get("contact:website"),
            "opening_hours": t.get("opening_hours"),
            "price": t.get("charge") or ("Paid" if t.get("fee") == "yes" else ("Free" if t.get("fee") == "no" else None)),
            "dogs": None, "accessibility": None,
            "tips": "Check the operator's app for live availability before you go.",
            "duration_min": None,
            "tags": ["ev"] + (["allstar"] if net else []),
            "source_urls": [f"https://www.openstreetmap.org/{t['osm'].replace('area/', 'way/')}"] + (nets.get("source_urls", []) if net else []),
            "verified": "2026-10-23",
        })
    (RESEARCH / "places_ev.json").write_text(json.dumps(places, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(places)} public charge points, {allstar} on Allstar networks")
    from collections import Counter
    print(Counter((p["summary"].split(":")[0], "allstar" in p["tags"]) for p in places).most_common(25))


if __name__ == "__main__":
    main()

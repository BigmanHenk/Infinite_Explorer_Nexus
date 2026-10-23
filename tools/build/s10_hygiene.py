"""Step 10 - Food Standards Agency hygiene ratings (0-5) for places to eat and drink.

    python tools/build/s10_hygiene.py     -> tools/research/hygiene.json   (then run s04)

FSA open data (Open Government Licence). Each place is matched to the FSA establishment near
its coordinates whose business name shares the most words with ours; nothing is guessed when
no establishment within ~400 m matches.
"""
import difflib
import json
import re
import sqlite3
import time
import urllib.parse
import urllib.request

from common import CONTENT, RESEARCH

API = "https://api.ratings.food.gov.uk/Establishments"
STOP = {"the", "and", "at", "of", "on", "sea", "cafe", "café", "bar", "pub", "restaurant", "kitchen", "ltd", "&",
        # generic and place words must not make a match on their own
        "brewery", "brewers", "brew", "taproom", "tap", "room", "house", "inn", "arms", "micropub", "alehouse", "ale",
        "tours", "tour", "visitor", "centre", "vineyard", "wine", "estate", "farm", "shop", "food", "hall", "village",
        "tasting", "cider", "beer", "distillers", "collections", "artisan", "chocolate", "oyster", "fish", "chips",
        "margate", "ramsgate", "broadstairs", "birchington", "westgate", "minnis", "bay", "canterbury", "faversham",
        "whitstable", "herne", "sandwich", "folkestone", "cliftonville", "westbrook", "minster", "thanet", "chartham",
        "staple", "barham", "bekesbourne", "acol", "nicholas", "wade", "reculver", "quex", "kent", "family"}


def words(s):
    return {w for w in re.findall(r"[a-z0-9']+", s.lower()) if w not in STOP and len(w) > 1}


def query(**params):
    url = API + "?" + urllib.parse.urlencode({**params, "pageSize": 50})
    req = urllib.request.Request(url, headers={"x-api-version": "2", "Accept": "application/json"})
    for _ in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r).get("establishments", [])
        except Exception:
            time.sleep(2)
    return []


def score(ours, theirs):
    a, b = words(ours), words(theirs)
    overlap = len(a & b)
    ratio = difflib.SequenceMatcher(None, ours.lower(), theirs.lower()).ratio()
    return overlap + ratio


def main():
    db = sqlite3.connect(CONTENT / "explorer.sqlite")
    rows = db.execute("SELECT id, name, lat, lon FROM places WHERE category IN "
                      "('pub','cafe','restaurant','food','brewery','vineyard','shop')").fetchall()
    out = {}
    for pid, name, lat, lon in rows:
        short = re.split(r"[,(]", name)[0].strip()
        cands = query(name=short, latitude=lat, longitude=lon, maxDistanceLimit=0.25)
        if not cands:
            cands = query(latitude=lat, longitude=lon, maxDistanceLimit=0.06)
        best = None
        for e in cands:
            sc = score(short, e["BusinessName"])
            if words(short) & words(e["BusinessName"]) or sc > 0.85:
                if best is None or sc > best[0]:
                    best = (sc, e)
        if best:
            e = best[1]
            out[pid] = {"rating": e["RatingValue"], "date": (e.get("RatingDate") or "")[:10], "fhrsid": e["FHRSID"],
                        "fsa_name": e["BusinessName"], "url": f"https://ratings.food.gov.uk/business/{e['FHRSID']}"}
            print(f"{name}  ->  {e['BusinessName']}: {e['RatingValue']} ({out[pid]['date']})")
        else:
            print(f"{name}  ->  (no match)")
        time.sleep(0.15)
    (RESEARCH / "hygiene.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(out)}/{len(rows)} matched")


if __name__ == "__main__":
    main()

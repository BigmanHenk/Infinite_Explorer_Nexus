"""Step 0 - tide gauge record for the harmonic fit (Environment Agency, Open Government Licence).

    python tools/build/s00_tide_download.py [days=370]

Streams the EA daily archive CSVs (~60 MB each) and keeps only the Dover and Sheerness
tidal-level lines (tools/work/tide/<date>.csv), so a year costs a few MB on disk. Days already
fetched are skipped; four downloads run at once.
"""
import datetime as dt
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from common import WORK

KEEP = (b"E71639-level-tidal_level-Mean-15_min-mAOD", b"E71539-level-tidal_level-Mean-15_min-mAOD")
OUT = WORK / "tide"


def fetch(day):
    out = OUT / f"{day}.csv"
    if out.exists():
        return day, "cached"
    url = f"https://environment.data.gov.uk/flood-monitoring/archive/readings-{day}.csv"
    try:
        lines = []
        with urllib.request.urlopen(url, timeout=300) as r:
            for line in r:
                if any(k in line for k in KEEP):
                    lines.append(line)
    except Exception as e:
        return day, f"failed {e}"
    tmp = out.with_suffix(".part")
    tmp.write_bytes(b"".join(lines))
    tmp.replace(out)
    return day, f"{len(lines)} rows"


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 370
    OUT.mkdir(parents=True, exist_ok=True)
    today = dt.date.today()
    todo = [str(today - dt.timedelta(days=i)) for i in range(2, days + 2)]
    with ThreadPoolExecutor(4) as ex:
        for day, msg in ex.map(fetch, todo):
            print(day, msg, flush=True)


if __name__ == "__main__":
    main()

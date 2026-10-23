"""Step 8 - the GitHub Pages site (branch gh-pages): the PC planner as index.html plus the
app's own map tiles as tiles/z/x/y.png, so the planner's maps need no third-party tile server
(OpenStreetMap's and CARTO's refuse pages opened from a file).

    python tools/build/s08_site.py      -> tools/work/site/  (then commit it to gh-pages)

Site: https://bigmanhenk.github.io/Infinite_Explorer_Nexus/
"""
import shutil
import sqlite3

from common import ROOT, WORK

SITE = WORK / "site"


def main():
    tiles = SITE / "tiles"
    if tiles.exists():
        shutil.rmtree(tiles)
    db = sqlite3.connect(WORK / "map.sqlite")
    n = 0
    for z, x, y, data in db.execute("SELECT z, x, y, data FROM tiles"):
        d = tiles / str(z) / str(x)
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{y}.png").write_bytes(data)
        n += 1
    shutil.copyfile(ROOT / "planner" / "Explorer Planner.html", SITE / "index.html")
    (SITE / ".nojekyll").write_text("")
    (SITE / "README.md").write_text(
        "# Explorer Planner\n\nPC week planner for the Infinite Explorer Nexus iPhone app, plus its offline map tiles "
        "(© OpenStreetMap contributors, ODbL). Built by tools/build/s08_site.py on the main branch.\n")
    print(f"{n} tiles + index.html in {SITE}")


if __name__ == "__main__":
    main()

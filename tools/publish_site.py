"""Publish the PC planner + map tiles to GitHub Pages (branch gh-pages).

    python tools/publish_site.py

Runs s06 (planner page) and s08 (site folder in tools/work/site), then commits that folder to
the gh-pages branch and pushes. Works from a fresh clone: the site folder gets its own git repo
the first time. Site: https://bigmanhenk.github.io/Infinite_Explorer_Nexus/
"""
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
SITE = TOOLS / "work" / "site"
REMOTE = "https://github.com/BigmanHenk/Infinite_Explorer_Nexus.git"


def run(args, cwd=None):
    print("$", " ".join(args))
    subprocess.run(args, cwd=cwd, check=True)


def main():
    if not (TOOLS / "work" / "map.sqlite").exists():
        sys.exit("tools/work/map.sqlite missing - run s01_extract.py and s02_tiles.py first (see docs/HANDOVER.md).")
    run([sys.executable, str(TOOLS / "build" / "s06_pc_planner.py")])
    run([sys.executable, str(TOOLS / "build" / "s08_site.py")])
    if not (SITE / ".git").exists():
        run(["git", "init", "-q", "-b", "gh-pages"], cwd=SITE)
    run(["git", "config", "user.name", "BigmanHenk"], cwd=SITE)
    run(["git", "config", "user.email", "232571103+BigmanHenk@users.noreply.github.com"], cwd=SITE)
    run(["git", "add", "-A"], cwd=SITE)
    subprocess.run(["git", "commit", "-q", "-m", "Update planner site"], cwd=SITE)
    run(["git", "push", "-q", "-f", REMOTE, "gh-pages"], cwd=SITE)
    print("Published - GitHub Pages updates within a few minutes.")


if __name__ == "__main__":
    main()

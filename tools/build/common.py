"""Shared constants for the content build."""
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
WORK = TOOLS / "work"
RESEARCH = TOOLS / "research"
OSM_FILE = TOOLS / "osm" / "kent.osm.pbf"
CONTENT = ROOT / "ios" / "ExplorerNexus" / "Content"

# (min lon, min lat, max lon, max lat)
DETAIL = (1.10, 51.26, 1.46, 51.41)   # Herne Bay / Reculver .. Ramsgate, Sandwich: all detail
WIDE = (0.85, 51.08, 1.50, 51.46)     # Faversham .. Dover: big features for low zooms
CORE = (1.17, 51.30, 1.45, 51.40)     # Thanet: rendered to the deepest zoom

ZOOM_WIDE = range(9, 13)      # 9..12 over WIDE
ZOOM_DETAIL = range(13, 17)   # 13..16 over DETAIL
ZOOM_CORE = 17                # 17 over CORE (the app over-zooms 18/19 from these)
TILE_PX = 512                 # @2x tiles on the standard 256 grid

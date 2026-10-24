# Infinite Explorer Nexus — handover (2026-10-24)

The offline iPhone app **Explorer** (sightseeing and week planner for Birchington-on-Sea,
Thanet and East Kent) and its **PC planner** web page. This file gives Claude Code (or anyone)
on a new machine everything needed to carry on. Read it first, then `README.md`.

## 1. Set up a new laptop (Windows)

1. Install **Git for Windows** (it includes Git Credential Manager), **Python 3.12**,
   **VS Code**, and the **Claude Code** extension or CLI.
2. Get the code:
   ```
   git clone https://github.com/BigmanHenk/Infinite_Explorer_Nexus.git
   cd Infinite_Explorer_Nexus
   python -m venv .venv && .venv\Scripts\activate
   pip install -r requirements.txt
   ```
   - **Avast HTTPS scanning:** on the old PC it made pip fail certificate checks. Add
     `--trusted-host pypi.org --trusted-host files.pythonhosted.org` if pip complains.
   - **Avast and api.anthropic.com:** it also once blocked Anthropic's API as "malicious".
     That was a false positive. Report it to Avast or add a URL exception; don't switch
     Avast off.
3. **Push once**, for example by editing a README line, so Git Credential Manager stores
   your GitHub login. `tools/ci_download.py` reuses that login to fetch builds.
4. **Map source data.** This is only needed to rebuild the map or the content; the app and
   the page build without it.
   ```
   mkdir tools\osm
   curl -L -o tools/osm/kent.osm.pbf https://download.geofabrik.de/europe/united-kingdom/england/kent-latest.osm.pbf
   python tools/build/s01_extract.py
   python tools/build/s02_tiles.py      # ~3 min -> tools/work/map.sqlite
   ```
5. **Sideloadly**, to install the IPA on the iPhone. Set the Bundle ID field to
   `com.infiniteaperture.explorernexus`. If the field still holds an ID from another app,
   Sideloadly installs over that app.

## 2. Day-to-day workflow

| Task | Command |
|---|---|
| Change the app | Edit `ios/ExplorerNexus/Sources/**`, commit, push. A push touching `ios/**` builds on GitHub Actions; the repo is public, so builds are free. |
| Get the IPA | `python tools/ci_download.py`. It waits for the build and saves `Desktop\Explorer iPhone\Explorer.ipa`, or prints the compiler errors. |
| Rebuild content (DB) | `python tools/build/s04_database.py`. It writes `ios/ExplorerNexus/Content/*.sqlite`. |
| Update the PC page | `python tools/build/s06_pc_planner.py` updates `planner/Explorer Planner.html`; `python tools/publish_site.py` publishes it to https://bigmanhenk.github.io/Infinite_Explorer_Nexus/ (needs `tools/work/map.sqlite`). |

There is **no Mac**. Swift is only compiled on GitHub Actions, so review Swift by eye
before pushing:
- **Long expressions:** the first build failed only because one long string concatenation
  timed out the type-checker. Keep expressions short and use typed `let`s.
- **Imports:** `ObservableObject` and `@Published` need `import Combine` in files that only
  import Foundation.

The app's own Settings → Sources lists the credits.

## 3. Repository map

```
ios/ExplorerNexus/project.yml        XcodeGen spec (iOS 17, bundle com.infiniteaperture.explorernexus, URL scheme explorernexus://, .explorerplan files)
ios/ExplorerNexus/Content/           explorer.sqlite (all content) + map-a (z9-15) / map-b (z16) / map-c (z17) tiles - split for GitHub's 100 MB limit
ios/ExplorerNexus/Sources/
  App/ExplorerApp.swift              tabs, splash, Router, plan import (onOpenURL)
  Common/                            Theme (Nexus themes, Twilight default), Components, Navigation, PhotoGallery, QR
  Data/  Store (DB load), Models (Place/Event/Walk/Cat), EventCalendar, Tides, Sun, Weather (Open-Meteo ukmo_seamless),
         Planner (week store), PlanShare (QR/link/file), Base (base + radius + home), OpeningHours (OSM syntax evaluator),
         TourPlanner (tour builder), Interests (Suggest tick boxes + suggestFair), Location, SQLite
  Map/   OfflineMap (MKTileOverlay from sqlite + pins/route/circle), MapScreen (+search), MapSearch, FullScreenMap,
         Travel (estimates, NavigateMenu Apple/Google/Waze), Parking
  Places/ Events/ Walks/ Planner/ Tides/ Photo/ Today/ Settings/   screens
tools/build/  content pipeline (below); planner_template.html = PC page source
tools/research/*.json   researched data (SCHEMA.md); hours.json, menus.json, hygiene.json, drink_attributes.json, allstar_networks.json
tools/work/   photos/ photos.json tides.pkl tide/ are kept in git (can't be fetched again); the rest is rebuildable
planner/Explorer Planner.html   built PC page (single file; maps/photos need internet)
```

## 4. Content pipeline (tools/build)

| Step | Script | What it does |
|---|---|---|
| s00 | s00_tide_download.py | Environment Agency daily archives, keeping only the Dover (E71639) and Sheerness (E71539) lines. Only about a year is online, so keep `tools/work/tide/`. |
| s01 | s01_extract.py | Map features from the Kent extract (pyosmium + shapely, sea built from the coastline). |
| s02 | s02_tiles.py | Cairo raster tiles (@2x on the 256 grid). z9–15 cover the whole WIDE box; z16 covers DETAIL plus the Canterbury, Whitstable, Faversham, Dover and Wingham islands; z17 covers Thanet. |
| s03 | s03_tides.py | UTide harmonic fit for 2026–2035. Margate is placed between Dover and Sheerness. |
| s04 | s04_database.py | Builds `explorer.sqlite`: places, events, walks routed with A* on the OSM walk graph, tides, photos, streets, parking. It also copies the map tiles. |
| s05 | s05_icons.py | App icon per Nexus theme. |
| s06 | s06_pc_planner.py | The PC page. |
| s07 | s07_photos.py | Wikimedia Commons photos. Cached; only CC/PD licences; credits kept. |
| s08 | s08_site.py | The Pages site folder. `publish_site.py` wraps s06 + s08 + the push. |
| s09 | s09_ev.py | EV chargers from OSM, Allstar networks marked (whole-word match). |
| s10 | s10_hygiene.py | FSA hygiene ratings. Town and generic words must not count as a name match. |
| s11 | s11_osm_pois.py | About 3,600 East Kent places from OSM (shops, pubs, cafés, attractions…), tagged `osm`. |

Notes on s03:
- `utide.solve` needs `epoch="1970-01-01"`, or it returns zero constituents.
- EA "Mean-15_min" timestamps mark the **end** of the interval, so shift them by −7.5 min.
- Dover flat-lined from June to August 2026; daily quality checks remove it.
- Accuracy: about 7 min RMS against the published Margate tables (calibration days only).

Order after changing research data: s04, then s06, then publish_site. Run s07 again, then s04,
when new places should get photos.

## 5. Decisions and rules (keep to them)

- **No copying TripAdvisor or Google reviews or scores.** Their terms and copyright forbid
  it. Link to them instead ("TripAdvisor reviews" / "Google reviews" buttons). Rankings use
  facts: CAMRA Good Beer Guide, awards, craft/real ale, hygiene rating.
- **Research text is in our own words, with `source_urls`.** Unknown facts stay null and are
  never invented. Event dates the organisers haven't confirmed are marked `"expected"`.
- **Commits** use `BigmanHenk <232571103+BigmanHenk@users.noreply.github.com>`, not the
  owner's Gmail, because the repo is public.
- **OpenStreetMap and CARTO tile servers refuse pages opened from a file.** The PC page
  therefore uses our own tiles from GitHub Pages.
- **Map files must stay under 100 MB each**, which is why they're split by zoom level.
- **The owner's preferences:**
  - Nexus look (themes from the Nexus Windows, Android and iOS apps).
  - Things done, not listed.
  - He tests on an iPhone via Sideloadly and plans on the PC.
- **Shell trap on Windows:** Python inside bash heredocs mangles `\n` and `\(`. Write patch
  scripts as files.

## 6. Features (all built, as of 2026-10-24)

- **Content:**
  - Places: 324 researched plus about 3,600 from OSM, including shops.
  - 162 events (confirmed or expected).
  - 16 walks routed along real paths.
  - 376 photos.
  - EV chargers, with the Allstar card marked.
  - 174 car parks.
  - 10,179 streets for search.
  - Tide tables for 2026–2035.
  - Photo spots and hides.
  - Menus (41), FSA hygiene ratings (50), CAMRA facts (50 venues).
- **App:**
  - Today: sun, tides, Met Office forecast, plan.
  - Explore, with filters for category, tags, base and radius, and opening times
    (day and time range).
  - Offline map with search, travel times, a radius circle and full screen.
  - Walks with follow mode.
  - My week: Suggest from tick-box interests (weather, opening hours, radius), the tour
    builder, and sharing by QR, link or file.
  - Tide tables, photo/wildlife page, practical info, parking, home location.
  - Directions via Apple Maps, Google Maps or Waze.
- **PC page:** the same data, laid out as catalogue | week strip + big map | info panel.
  It has the same Suggest, tour builder, opening-times filter, parking, base/home/radius,
  and sends plans to the iPhone by QR.

## 7. Open items

- **Research still running when this was written:** `places_wildlife_extra.json` (every
  individual bird hide, seal watching…) and `places_scenic_extra.json` (photo and beauty
  spots). s04 already lists both files, so if they're missing, re-run that research in the
  SCHEMA.md format, then run s07, s04, s06 and publish_site.
- **Not yet tested on a phone:** the latest features (tour builder, Suggest tick boxes,
  parking, home, wider map). Check the IPA on the iPhone.
- **Opening-hours gaps:** 57 researched places have unknown hours. Seasonal venues show
  "unknown" outside their published season.
- **Dead websites** are removed in s04 (DEAD_SITES); add new ones there if found.

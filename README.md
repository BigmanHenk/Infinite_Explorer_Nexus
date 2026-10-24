# Infinite Explorer Nexus

An offline iPhone sightseeing guide and week planner for Birchington-on-Sea and the Isle of
Thanet (home-screen name **Explorer**). Everything works without signal. The only things that
need a connection are the weather forecast (it is kept for offline use) and the website and
phone links.

## What is in it

- **Today**: sunrise, sunset, golden hour and moon; the Met Office forecast; today's tide
  curve; what's on; and your plan for the day.
- **Explore**: 200+ places (sights, history, museums, beaches, nature, food and drink, day
  trips, practical information). Each has a description, opening times, prices, tips and its
  sources.
- **Map**: an offline OpenStreetMap map, from zoom 9 (Faversham to Dover) down to street and
  footpath level across Thanet. It shows category pins and your position.
- **Walks**: 16 walks routed along real paths. A follow mode tracks you along the route and
  shows the distance left, the next point and an off-route warning.
- **My week**: a seven-day planner. **Suggest** fills empty days using events, tides and the
  forecast. You can share a plan as text, as a link, as an `.explorerplan` file or as a QR
  code.
- **What's on**: about 160 events from October 2026 through 2027. Dates that organisers have
  not yet confirmed are marked "expected".
- **Tide tables**: Margate, 2026–2035, computed on the PC (see below).
- **Photo spots & hides**: subjects, best light, tide notes and wildlife, plus a light
  calculator.

## Planning on the PC

Open `planner/Explorer Planner.html` in any browser. Plan the week (Suggest works there too,
using the live forecast), then press **Send to iPhone**:

- scan the QR code with the iPhone camera, and Explorer opens with the plan; or
- save the `.explorerplan` file and AirDrop or e-mail it, or put it in iCloud Drive.

Plans also go from the iPhone to the PC: share as file on the phone, then **Import plan file**
in the page.

## Building the content (PC, Python 3.12)

```
pip install -r requirements.txt     (add --trusted-host flags if Avast breaks pip)
curl -L -o tools/osm/kent.osm.pbf https://download.geofabrik.de/europe/united-kingdom/england/kent-latest.osm.pbf
python tools/build/s00_tide_download.py      # a year of EA tide gauge data (Dover, Sheerness)
python tools/build/s01_extract.py            # map features from the OSM extract
python tools/build/s02_tiles.py              # offline map tiles (Cairo), ~1 min
python tools/build/s03_tides.py              # harmonic fit, Margate placed and checked, 10 years
python tools/build/s04_database.py           # explorer.sqlite + routed walks + map tile files
python tools/build/s05_icons.py              # app icons for every Nexus theme
python tools/build/s06_pc_planner.py         # planner/Explorer Planner.html
python tools/build/s07_photos.py             # Wikimedia Commons photos (cached in tools/work/photos)
python tools/build/s09_ev.py                 # EV charge points, Allstar networks marked
python tools/build/s10_hygiene.py            # Food Standards Agency hygiene ratings
python tools/build/s11_osm_pois.py           # all East Kent places of interest from OpenStreetMap
python tools/publish_site.py                 # PC planner + tiles to GitHub Pages
python tools/ci_download.py                  # wait for the iPhone build, download Explorer.ipa
```

New machine? Read `docs/HANDOVER.md`.

The research data lives in `tools/research/*.json`, and `SCHEMA.md` describes it.

## Building the app (no Mac)

XcodeGen spec in `ios/ExplorerNexus/project.yml`. The GitHub Actions workflow `iOS build`
(started by hand) makes an unsigned `Explorer.ipa`, which Sideloadly signs and installs.
Bundle id `com.infiniteaperture.explorernexus`: check the Bundle ID field in Sideloadly when
you switch between apps.

## Credits

- Map data © OpenStreetMap contributors (ODbL).
- Tide gauge data from the Environment Agency (Open Government Licence). The predictions are
  not for navigation.
- Weather from the Met Office UK models via Open-Meteo (CC BY 4.0).
- QR codes made with qrcode-generator (MIT, Kazuhiko Arase).

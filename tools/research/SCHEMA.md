# Research output schema (Birchington Explorer offline database)

Today is 2026-10-23. Every file is a JSON array written with the Write tool, UTF-8.
Write descriptions IN YOUR OWN WORDS (never paste text from websites). Never invent a fact:
if you could not confirm something, leave the field null. Coordinates: WGS84 decimal degrees,
5 decimals, taken from OpenStreetMap / Nominatim (https://nominatim.openstreetmap.org/search?q=...&format=json),
Wikipedia or the venue's own site — never guessed. Put every page you used in source_urls.

## places_*.json
{
  "id": "kebab-case-unique",            e.g. "quex-park-powell-cotton-museum"
  "name": "Powell-Cotton Museum, Quex Park",
  "category": "sight|museum|beach|nature|church|history|family|food|pub|cafe|restaurant|shop|market|practical|viewpoint|daytrip",
  "town": "Birchington-on-Sea",
  "lat": 51.37, "lon": 1.33,
  "summary": "one sentence, <= 140 chars",
  "description": "80-250 words, own words: what it is, history, what to see",
  "address": "...", "postcode": "CT7 0BH",
  "phone": "...", "website": "https://...",
  "opening_hours": "free text, as published; say which season",
  "price": "free text e.g. 'Adult £12, child £6 (2026)' or 'Free'",
  "dogs": "free text or null", "accessibility": "free text or null",
  "tips": "practical tip or null",
  "duration_min": 90,                   typical visit length, or null
  "tags": ["rainy-day","free","kids","dogs","coast","history","wheelchair"],
  "source_urls": ["..."],
  "verified": "2026-10-23"
}

## events_*.json
{
  "id": "kebab-case-unique",
  "title": "...",
  "category": "festival|market|music|theatre|film|family|sport|heritage|food|seasonal|nature|art|community|talk",
  "venue": "...", "town": "...", "lat": .., "lon": ..,
  "start_date": "2026-10-31", "end_date": "2026-10-31",      single dated occurrence; null when recurring
  "start_time": "18:00", "end_time": "21:00",                null if unknown
  "recurrence": null  OR  {"freq":"weekly","weekdays":["Sat"],"from":"2026-01-01","until":null,"months":[1,2,...]}
                      OR  {"freq":"monthly","weekdays":["Sun"],"nth":[1],"from":..,"until":..}   (1st Sunday each month; nth -1 = last)
  "price": "...", "website": "...", "booking": "free text or null",
  "description": "40-150 words, own words",
  "confidence": "confirmed" (date published by organiser) | "expected" (annual event, organiser has not yet published this year's date — give your best estimated dates from previous years and say so in the description),
  "source_urls": ["..."], "verified": "2026-10-23"
}

## walks.json
{
  "id": "...", "title": "...", "distance_km": 5.2, "duration_min": 90,
  "difficulty": "easy|moderate|hard", "surface": "...", "circular": true,
  "start": "name of start point", "start_lat": .., "start_lon": ..,
  "summary": "...", "description": "100-300 words, own words",
  "waypoints": [ {"name":"Minnis Bay","lat":..,"lon":..,"note":"own words, what to see here"} ... ]   ordered, 6-20 points along the real route (the app routes along OpenStreetMap paths between them, so put a point at every turn/junction choice),
  "toilets": "...", "refreshments": "...", "parking": "...", "public_transport": "...",
  "dogs": "...", "accessibility": "...", "tide_warning": "text or null",
  "source_urls": [...], "verified": "2026-10-23"
}

## practical.json — same shape as places with category "practical" (toilets, car parks,
station, bus stops, tourist info, pharmacies, defibrillators near the beaches, lifeguard
beaches) plus an optional "facts" array of {"topic": "...", "text": "..."} objects for things
like beach dog bans, bus routes, tide safety, emergency numbers, bin days are NOT needed.

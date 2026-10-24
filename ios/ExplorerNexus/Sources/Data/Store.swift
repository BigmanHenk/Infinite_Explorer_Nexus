import Combine
import CoreLocation
import Foundation

/// The offline content, loaded once from the bundled explorer.sqlite (a few hundred rows;
/// tides are read per day on demand).
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    let places: [Place]
    let events: [EventItem]
    let walks: [Walk]
    let facts: [Fact]
    let meta: [String: String]
    let tides: TideTable?

    private init() {
        var places: [Place] = []
        var events: [EventItem] = []
        var walks: [Walk] = []
        var facts: [Fact] = []
        var meta: [String: String] = [:]
        if let path = Bundle.main.path(forResource: "explorer", ofType: "sqlite", inDirectory: "Content"),
           let db = SQLiteDB(path: path) {
            db.query("SELECT key, value FROM meta") { r in meta[r.text(0)] = r.text(1) }
            db.query("""
                SELECT id, name, category, town, lat, lon, summary, description, address, postcode, phone, website,
                       opening_hours, price, dogs, accessibility, tips, duration_min, tags, source_urls, verified,
                       subjects, best_time, tide, wildlife, facilities,
                       hours_osm, menu_url, hygiene, hygiene_date, hygiene_url, drink
                FROM places ORDER BY name
                """) { r in
                places.append(Place(
                    id: r.text(0), name: r.text(1), category: r.text(2), town: r.text(3),
                    lat: r.double(4) ?? 0, lon: r.double(5) ?? 0, summary: r.text(6), description: r.text(7),
                    address: r.string(8), postcode: r.string(9), phone: r.string(10), website: r.string(11),
                    openingHours: r.string(12), price: r.string(13), dogs: r.string(14), accessibility: r.string(15),
                    tips: r.string(16), durationMin: r.int(17), tags: Store.list(r.string(18), ","),
                    sources: Store.list(r.string(19), "\n"), verified: r.string(20),
                    subjects: Store.list(r.string(21), ","), bestTime: r.string(22), tide: r.string(23),
                    wildlife: r.string(24), facilities: r.string(25),
                    hoursOSM: r.string(26), menuURL: r.string(27), hygiene: r.string(28),
                    hygieneDate: r.string(29), hygieneURL: r.string(30),
                    drink: r.string(31).flatMap { try? JSONDecoder().decode(DrinkInfo.self, from: Data($0.utf8)) }))
            }
            let dec = JSONDecoder()
            db.query("""
                SELECT id, title, category, venue, town, lat, lon, start_date, end_date, start_time, end_time,
                       recurrence, price, website, booking, description, confidence, source_urls, verified
                FROM events
                """) { r in
                let rec = r.string(11).flatMap { try? dec.decode(Recurrence.self, from: Data($0.utf8)) }
                events.append(EventItem(
                    id: r.text(0), title: r.text(1), category: r.text(2), venue: r.text(3), town: r.text(4),
                    lat: r.double(5), lon: r.double(6), startDate: r.string(7), endDate: r.string(8),
                    startTime: r.string(9), endTime: r.string(10), recurrence: rec, price: r.string(12),
                    website: r.string(13), booking: r.string(14), description: r.text(15),
                    confidence: r.text(16), sources: Store.list(r.string(17), "\n"), verified: r.string(18)))
            }
            var points: [String: [WalkPoint]] = [:]
            db.query("SELECT walk_id, name, lat, lon, note FROM walk_points ORDER BY walk_id, seq") { r in
                points[r.text(0), default: []].append(
                    WalkPoint(name: r.text(1), lat: r.double(2) ?? 0, lon: r.double(3) ?? 0, note: r.string(4)))
            }
            db.query("""
                SELECT id, title, distance_km, duration_min, difficulty, surface, circular, start, summary, description,
                       toilets, refreshments, parking, public_transport, dogs, accessibility, tide_warning,
                       source_urls, route
                FROM walks ORDER BY distance_km
                """) { r in
                let id = r.text(0)
                walks.append(Walk(
                    id: id, title: r.text(1), distanceKm: r.double(2) ?? 0, durationMin: r.int(3),
                    difficulty: r.text(4), surface: r.string(5), circular: (r.int(6) ?? 0) != 0, start: r.text(7),
                    summary: r.text(8), description: r.text(9), toilets: r.string(10), refreshments: r.string(11),
                    parking: r.string(12), publicTransport: r.string(13), dogs: r.string(14),
                    accessibility: r.string(15), tideWarning: r.string(16), sources: Store.list(r.string(17), "\n"),
                    points: points[id] ?? [], route: Store.route(r.data(18))))
            }
            db.query("SELECT rowid, topic, text FROM facts ORDER BY rowid") { r in
                facts.append(Fact(id: r.int(0) ?? 0, topic: r.text(1), text: r.text(2)))
            }
            self.tides = TideTable(db: db, meta: meta)
        } else {
            self.tides = nil
        }
        self.places = places
        self.events = events
        self.walks = walks
        self.facts = facts
        self.meta = meta
    }

    private static func list(_ s: String?, _ sep: Character) -> [String] {
        (s ?? "").split(separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Route blob = little-endian Float32 lat, lon pairs.
    private static func route(_ d: Data?) -> [CLLocationCoordinate2D] {
        guard let d, d.count >= 8 else { return [] }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(d.count / 8)
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let n = d.count / 8
            for i in 0..<n {
                let lat = raw.loadUnaligned(fromByteOffset: i * 8, as: Float32.self)
                let lon = raw.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float32.self)
                out.append(.init(latitude: Double(lat), longitude: Double(lon)))
            }
        }
        return out
    }

    func place(_ id: String) -> Place? { places.first { $0.id == id } }
    func event(_ id: String) -> EventItem? { events.first { $0.id == id } }
    func walk(_ id: String) -> Walk? { walks.first { $0.id == id } }

    var sightseeing: [Place] { places.filter { !["pub", "brewery", "vineyard", "cafe", "restaurant", "food", "shop", "practical", "ev"].contains($0.category) } }
    var photoSpots: [Place] { places.filter { $0.isPhoto } }
}

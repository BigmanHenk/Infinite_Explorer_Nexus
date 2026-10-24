import CoreLocation
import Foundation

/// Facts about a pub / bar / taproom (tools/research/drink_attributes.json, CAMRA & venues).
struct DrinkInfo: Codable, Hashable {
    var craft: Bool?
    var real_ale: Bool?
    var micropub: Bool?
    var taproom: Bool?
    var cider: Bool?
    var food: String?
    var dogs: Bool?
    var gbg: Bool?
    var awards: [String]?
    var garden: Bool?
    var live_music: Bool?
    var notes: String?

    var badges: [String] {
        var b: [String] = []
        if gbg == true { b.append("Good Beer Guide") }
        if craft == true { b.append("Craft beer") }
        if real_ale == true { b.append("Real ale") }
        if micropub == true { b.append("Micropub") }
        if taproom == true { b.append("Taproom") }
        if cider == true { b.append("Real cider") }
        if let f = food, f != "none" { b.append(f == "full meals" ? "Food" : "Snacks") }
        if garden == true { b.append("Garden") }
        if dogs == true { b.append("Dogs welcome") }
        if live_music == true { b.append("Live music") }
        return b
    }
}

/// Builds a timed route through the best places that are open when you get there.
/// The PC planner has the same rules in JavaScript (tourPlan).
enum TourTheme: String, CaseIterable, Identifiable {
    case pubs = "Pub crawl"
    case craft = "Craft beer trail"
    case sights = "Sightseeing"
    case cafes = "Cafés & treats"
    case photo = "Photo spots"
    case mixed = "Mixed day out"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .pubs: return "mug.fill"
        case .craft: return "drop.fill"
        case .sights: return "building.columns.fill"
        case .cafes: return "cup.and.saucer.fill"
        case .photo: return "camera.fill"
        case .mixed: return "sparkles"
        }
    }

    func accepts(_ p: Place) -> Bool {
        switch self {
        case .pubs: return ["pub", "brewery"].contains(p.category)
        case .craft:
            guard ["pub", "brewery"].contains(p.category) else { return false }
            return p.drink?.craft == true || p.drink?.taproom == true || p.drink?.micropub == true
        case .sights: return ["sight", "history", "museum", "church", "viewpoint", "beach", "nature", "family"].contains(p.category)
        case .cafes: return ["cafe", "food"].contains(p.category)
        case .photo: return ["photo", "viewpoint"].contains(p.category)
        case .mixed: return ["sight", "history", "museum", "church", "viewpoint", "beach", "cafe", "pub"].contains(p.category)
        }
    }
}

struct TourStop: Identifiable {
    let place: Place
    let arrive: Int        // minutes from midnight
    let leave: Int
    let legMinutes: Int    // travel to this stop
    let legMetres: Double
    var id: String { place.id }
}

struct Tour {
    let stops: [TourStop]
    let start: CLLocationCoordinate2D
    let startMinute: Int
    let endMinute: Int
    let backMinutes: Int?          // walk/drive back to the start, when asked for
    var totalTravel: Int { stops.reduce(0) { $0 + $1.legMinutes } + (backMinutes ?? 0) }
    var totalMetres: Double { stops.reduce(0) { $0 + $1.legMetres } }
}

enum TourPlanner {
    static func dwell(_ p: Place) -> Int {
        switch p.category {
        case "pub": return 45
        case "brewery": return 60
        case "vineyard": return 75
        case "cafe": return 40
        case "food": return 25
        case "restaurant": return 90
        case "museum": return 90
        case "family": return 90
        case "history": return 40
        case "church": return 25
        case "beach", "nature": return 40
        case "viewpoint": return 15
        case "photo": return 30
        default: return 30
        }
    }

    static func score(_ p: Place, theme: TourTheme) -> Double {
        var s = 1.0
        if let d = p.drink {
            s += Double(min(d.awards?.count ?? 0, 3)) * 1.5
            if d.gbg == true { s += 2 }
            if d.craft == true { s += theme == .craft ? 2 : 0.5 }
            if d.real_ale == true { s += 0.7 }
            if d.micropub == true { s += 0.5 }
            if d.taproom == true { s += 0.8 }
        }
        if p.hygiene == "5" { s += 0.3 }
        if ["museum", "history", "sight"].contains(p.category) { s += 0.6 }
        if !p.hours.known { s -= 1 }
        return s
    }

    static func minutes(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, drive: Bool) -> (Int, Double) {
        let m = a.distance(to: b)
        let est = TravelEstimate(metres: m)
        return (drive ? est.carMin : est.walkMin, m)
    }

    /// Opening check for a visit; unknown hours are allowed (they score lower).
    static func openFor(_ p: Place, day: Date, from: Int, to: Int) -> Bool {
        p.hours.isOpen(on: day, from: from, to: min(to, 1440), whole: true) ?? true
    }

    static func plan(places: [Place], theme: TourTheme, start: CLLocationCoordinate2D, day: Date,
                     startMinute: Int, hours: Double, drive: Bool, returnToStart: Bool,
                     maxStops: Int = 8, exclude: Set<String> = []) -> Tour {
        let end = startMinute + Int(hours * 60)
        let maxLeg = drive ? 30 : 25
        var pool = places.filter { theme.accepts($0) && !exclude.contains($0.id) }
        // keep the pool to what is reachable at all
        pool = pool.filter { minutes(start, $0.coordinate, drive: drive).0 <= (drive ? 45 : 40) }
        var stops: [TourStop] = []
        var here = start
        var now = startMinute
        var lastCategory = ""
        while stops.count < maxStops {
            var best: (Double, Place, Int, Double)?
            for p in pool where !stops.contains(where: { $0.place.id == p.id }) {
                let (leg, metres) = minutes(here, p.coordinate, drive: drive)
                if leg > maxLeg { continue }
                let arrive = now + leg
                let leave = arrive + dwell(p)
                var finish = leave
                if returnToStart { finish += minutes(p.coordinate, start, drive: drive).0 }
                if finish > end { continue }
                if !openFor(p, day: day, from: arrive, to: leave) { continue }
                var v = score(p, theme: theme) - Double(leg) * (drive ? 0.05 : 0.14)
                if theme == .mixed && p.category == lastCategory { v -= 1 }
                if theme == .mixed && ["pub", "cafe"].contains(p.category) && stops.filter({ $0.place.category == p.category }).count >= 1 { v -= 2 }
                if best == nil || v > best!.0 { best = (v, p, leg, metres) }
            }
            guard let b = best else { break }
            let arrive = now + b.2
            stops.append(TourStop(place: b.1, arrive: arrive, leave: arrive + dwell(b.1), legMinutes: b.2, legMetres: b.3))
            here = b.1.coordinate
            now = arrive + dwell(b.1)
            lastCategory = b.1.category
        }
        stops = improveOrder(stops, start: start, day: day, startMinute: startMinute, end: end, drive: drive, returnToStart: returnToStart)
        var back: Int?
        if returnToStart, let last = stops.last { back = minutes(last.place.coordinate, start, drive: drive).0 }
        return Tour(stops: stops, start: start, startMinute: startMinute, endMinute: end, backMinutes: back)
    }

    /// Re-times a given order; nil when a stop would be closed or the time runs out.
    static func timed(_ order: [Place], start: CLLocationCoordinate2D, day: Date, startMinute: Int, end: Int,
                      drive: Bool, returnToStart: Bool) -> [TourStop]? {
        var out: [TourStop] = []
        var here = start
        var now = startMinute
        for p in order {
            let (leg, m) = minutes(here, p.coordinate, drive: drive)
            let arrive = now + leg
            let leave = arrive + dwell(p)
            if !openFor(p, day: day, from: arrive, to: leave) { return nil }
            out.append(TourStop(place: p, arrive: arrive, leave: leave, legMinutes: leg, legMetres: m))
            here = p.coordinate
            now = leave
        }
        if returnToStart { now += minutes(here, start, drive: drive).0 }
        return now <= end ? out : nil
    }

    /// 2-opt: reverse stretches of the route while that shortens the travel and still fits.
    static func improveOrder(_ stops: [TourStop], start: CLLocationCoordinate2D, day: Date, startMinute: Int, end: Int,
                             drive: Bool, returnToStart: Bool) -> [TourStop] {
        guard stops.count >= 3 else { return stops }
        var best = stops
        var bestTravel = best.reduce(0) { $0 + $1.legMinutes }
        var improved = true
        var rounds = 0
        while improved && rounds < 20 {
            improved = false
            rounds += 1
            for i in 0..<(best.count - 1) {
                for j in (i + 1)..<best.count {
                    var order = best.map(\.place)
                    order[i...j].reverse()
                    if let t = timed(order, start: start, day: day, startMinute: startMinute, end: end, drive: drive, returnToStart: returnToStart) {
                        let travel = t.reduce(0) { $0 + $1.legMinutes }
                        if travel < bestTravel {
                            best = t
                            bestTravel = travel
                            improved = true
                        }
                    }
                }
            }
        }
        return best
    }

    /// Google Maps multi-stop route (up to 9 waypoints).
    static func googleURL(_ tour: Tour, drive: Bool, returnToStart: Bool) -> URL? {
        guard let last = tour.stops.last else { return nil }
        let dest = returnToStart ? tour.start : last.place.coordinate
        var mids = tour.stops.map(\.place.coordinate)
        if !returnToStart { mids.removeLast() }
        let way = mids.prefix(9).map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
        var s = "https://www.google.com/maps/dir/?api=1&origin=\(tour.start.latitude),\(tour.start.longitude)"
        s += "&destination=\(dest.latitude),\(dest.longitude)&travelmode=\(drive ? "driving" : "walking")"
        if !way.isEmpty, let w = way.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { s += "&waypoints=\(w)" }
        return URL(string: s)
    }

    static func hm(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
}

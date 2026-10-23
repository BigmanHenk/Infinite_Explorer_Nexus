import CoreLocation
import Foundation
import SwiftUI

// Everything here comes from the bundled explorer.sqlite (tools/build/s04_database.py).

struct Place: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let town: String
    let lat: Double
    let lon: Double
    let summary: String
    let description: String
    let address: String?
    let postcode: String?
    let phone: String?
    let website: String?
    let openingHours: String?
    let price: String?
    let dogs: String?
    let accessibility: String?
    let tips: String?
    let durationMin: Int?
    let tags: [String]
    let sources: [String]
    let verified: String?
    // photography spots and hides
    let subjects: [String]
    let bestTime: String?
    let tide: String?
    let wildlife: String?
    let facilities: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var isPhoto: Bool { category == "photo" || category == "hide" }
}

struct Recurrence: Codable, Hashable {
    var freq: String                // weekly | monthly
    var weekdays: [String]?         // Mon ... Sun
    var nth: [Int]?                 // monthly: 1 = first, -1 = last
    var months: [Int]?              // 1 ... 12
    var from: String?
    var until: String?
}

struct EventItem: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let venue: String
    let town: String
    let lat: Double?
    let lon: Double?
    let startDate: String?
    let endDate: String?
    let startTime: String?
    let endTime: String?
    let recurrence: Recurrence?
    let price: String?
    let website: String?
    let booking: String?
    let description: String
    let confidence: String
    let sources: [String]
    let verified: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
    var isExpected: Bool { confidence == "expected" }
    var timeText: String? {
        switch (startTime, endTime) {
        case let (s?, e?): return "\(s)–\(e)"
        case let (s?, nil): return "from \(s)"
        default: return nil
        }
    }
}

struct WalkPoint: Hashable {
    let name: String
    let lat: Double
    let lon: Double
    let note: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct Walk: Identifiable, Hashable {
    let id: String
    let title: String
    let distanceKm: Double
    let durationMin: Int?
    let difficulty: String
    let surface: String?
    let circular: Bool
    let start: String
    let summary: String
    let description: String
    let toilets: String?
    let refreshments: String?
    let parking: String?
    let publicTransport: String?
    let dogs: String?
    let accessibility: String?
    let tideWarning: String?
    let sources: [String]
    let points: [WalkPoint]
    /// The path drawn on the map: routed along OpenStreetMap footpaths between the points.
    let route: [CLLocationCoordinate2D]

    static func == (a: Walk, b: Walk) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Fact: Identifiable, Hashable {
    let id: Int
    let topic: String
    let text: String
}

/// Category look-up: label, SF Symbol and colour, used by lists, chips and map pins.
enum Cat {
    static let order = ["sight", "history", "museum", "church", "beach", "nature", "viewpoint", "family",
                        "photo", "hide", "pub", "brewery", "vineyard", "cafe", "restaurant", "food", "shop", "market", "daytrip", "practical"]

    static func label(_ c: String) -> String {
        switch c {
        case "sight": return "Sights"
        case "history": return "History"
        case "museum": return "Museums"
        case "church": return "Churches"
        case "beach": return "Beaches"
        case "nature": return "Nature"
        case "viewpoint": return "Viewpoints"
        case "family": return "Family"
        case "photo": return "Photo spots"
        case "hide": return "Wildlife hides"
        case "pub": return "Pubs"
        case "brewery": return "Breweries & distilleries"
        case "vineyard": return "Vineyards & wine"
        case "cafe": return "Cafés"
        case "restaurant": return "Restaurants"
        case "food": return "Food"
        case "shop": return "Shops"
        case "market": return "Markets"
        case "daytrip": return "Day trips"
        case "practical": return "Practical"
        default: return c.capitalized
        }
    }

    static func symbol(_ c: String) -> String {
        switch c {
        case "sight": return "star.fill"
        case "history": return "building.columns.fill"
        case "museum": return "building.2.fill"
        case "church": return "bell.fill"
        case "beach": return "beach.umbrella.fill"
        case "nature": return "leaf.fill"
        case "viewpoint": return "binoculars.fill"
        case "family": return "figure.2.and.child.holdinghands"
        case "photo": return "camera.fill"
        case "hide": return "bird.fill"
        case "pub": return "mug.fill"
        case "brewery": return "drop.fill"
        case "vineyard": return "wineglass.fill"
        case "cafe": return "cup.and.saucer.fill"
        case "restaurant": return "fork.knife"
        case "food": return "takeoutbag.and.cup.and.straw.fill"
        case "shop": return "bag.fill"
        case "market": return "basket.fill"
        case "daytrip": return "car.fill"
        case "practical": return "info.circle.fill"
        default: return "mappin"
        }
    }

    static func color(_ c: String) -> Color {
        switch c {
        case "sight", "viewpoint": return Color(hex: 0xE0A030)
        case "history", "church": return Color(hex: 0x9C6B4A)
        case "museum": return Color(hex: 0x8E5BC2)
        case "beach": return Color(hex: 0x2E9BD6)
        case "nature", "hide": return Color(hex: 0x3E9B4F)
        case "family": return Color(hex: 0xE5598F)
        case "photo": return Color(hex: 0xD9483B)
        case "pub", "cafe", "restaurant", "food": return Color(hex: 0xD9762B)
        case "brewery": return Color(hex: 0xB8862E)
        case "vineyard": return Color(hex: 0x8E2F55)
        case "shop", "market": return Color(hex: 0x4A7FC1)
        case "daytrip": return Color(hex: 0x5E6B7A)
        default: return Color(hex: 0x6E7781)
        }
    }

    static func eventSymbol(_ c: String) -> String {
        switch c {
        case "festival": return "party.popper.fill"
        case "market": return "basket.fill"
        case "music": return "music.note"
        case "theatre": return "theatermasks.fill"
        case "film": return "film.fill"
        case "family": return "figure.2.and.child.holdinghands"
        case "sport": return "figure.run"
        case "heritage": return "building.columns.fill"
        case "food": return "fork.knife"
        case "seasonal": return "snowflake"
        case "nature": return "leaf.fill"
        case "art": return "paintpalette.fill"
        case "talk": return "person.wave.2.fill"
        default: return "calendar"
        }
    }
}

/// Day keys ("2026-10-23") in the local (Europe/London) calendar.
enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        c.firstWeekday = 2   // Monday
        return c
    }()
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }
    static func date(_ key: String) -> Date? { keyFormatter.date(from: key) }
    static func start(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ days: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: days, to: d) ?? d }
    static func weekStart(_ d: Date) -> Date {
        cal.dateInterval(of: .weekOfYear, for: d)?.start ?? start(d)
    }

    static func format(_ d: Date, _ style: String) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = style
        return f.string(from: d)
    }
    static func time(_ d: Date) -> String { format(d, "HH:mm") }
    static func weekdayShort(_ d: Date) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][cal.component(.weekday, from: d) - 1]
    }
}

extension CLLocationCoordinate2D {
    func distance(to o: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: o.latitude, longitude: o.longitude))
    }
}

func distanceText(_ m: CLLocationDistance) -> String {
    if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
    let miles = m / 1609.344
    return String(format: "%.1f km · %.1f mi", m / 1000, miles)
}

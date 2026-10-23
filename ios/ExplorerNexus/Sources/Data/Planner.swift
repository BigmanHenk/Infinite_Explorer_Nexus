import Combine
import CoreLocation
import Foundation

/// One thing planned on one day.
struct PlanItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case place, event, walk, note }
    enum Slot: String, Codable, CaseIterable {
        case morning, afternoon, evening
        var label: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .morning: return "sunrise"
            case .afternoon: return "sun.max"
            case .evening: return "sunset"
            }
        }
    }

    var id = UUID()
    var day: String              // yyyy-MM-dd (UK)
    var kind: Kind
    var refID: String?
    var title: String
    var slot: Slot
    var time: String?            // "HH:mm", optional
    var note: String = ""
    var done = false
}

/// The week planner: items saved as JSON in Documents (survives app updates; included in
/// the phone's backup).
@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var items: [PlanItem] = [] { didSet { save() } }
    @Published var weekStart: Date = Day.weekStart(Date())

    private let url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("planner.json")

    init() {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([PlanItem].self, from: d) {
            items = v
        }
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(items) else { return }
        try? d.write(to: url, options: .atomic)
    }

    var weekDays: [Date] { (0..<7).map { Day.add($0, to: weekStart) } }

    func items(on day: Date) -> [PlanItem] {
        let key = Day.key(day)
        return items.filter { $0.day == key }.sorted { a, b in
            let sa = PlanItem.Slot.allCases.firstIndex(of: a.slot) ?? 0
            let sb = PlanItem.Slot.allCases.firstIndex(of: b.slot) ?? 0
            if sa != sb { return sa < sb }
            return (a.time ?? "99") < (b.time ?? "99")
        }
    }

    func contains(kind: PlanItem.Kind, refID: String, on day: Date? = nil) -> Bool {
        items.contains { $0.kind == kind && $0.refID == refID && (day == nil || $0.day == Day.key(day!)) }
    }

    func add(_ item: PlanItem) { items.append(item) }

    func update(_ item: PlanItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
    }

    func remove(_ item: PlanItem) { items.removeAll { $0.id == item.id } }

    func toggleDone(_ item: PlanItem) {
        var v = item
        v.done.toggle()
        update(v)
    }

    func clear(day: Date) {
        let key = Day.key(day)
        items.removeAll { $0.day == key }
    }

    func clearWeek() {
        let keys = Set(weekDays.map(Day.key))
        items.removeAll { keys.contains($0.day) }
    }

    func moveWeek(_ by: Int) { weekStart = Day.add(7 * by, to: weekStart) }

    /// Fills the empty days of the shown week: dated events first, then - led by the Met
    /// Office forecast when there is one - a walk or beach on dry days, museums and indoor
    /// places on wet days, nothing exposed on very windy days, and a sunset spot on evenings
    /// that are not overcast.
    func suggestWeek(store: Store, weather: WeatherStore, inRange: (CLLocationCoordinate2D?) -> Bool = { _ in true }) {
        var usedPlaces = Set(items.compactMap { $0.kind == .place ? $0.refID : nil })
        var usedWalks = Set(items.compactMap { $0.kind == .walk ? $0.refID : nil })
        let outdoor = store.sightseeing.filter { !["daytrip", "photo", "hide", "market"].contains($0.category) && !isIndoor($0) && inRange($0.coordinate) }
            .sorted { rank($0) > rank($1) }
        let indoor = store.places.filter { isIndoor($0) && inRange($0.coordinate) }.sorted { rank($0) > rank($1) }
        let sunsetSpots = store.photoSpots.filter { p in p.subjects.contains { $0.contains("sunset") } && inRange(p.coordinate) }
        let walks = store.walks.filter { inRange($0.points.first?.coordinate) }
        let today = Day.start(Date())
        for (i, day) in weekDays.enumerated() where day >= today && items(on: day).isEmpty {
            let key = Day.key(day)
            let w = weather.forecast(for: day)
            let wet = w?.isWet ?? false
            let windy = w?.isWindy ?? false
            // 1. one-off events that day (not exhibitions or daily cinemas)
            let occ = EventCalendar.on(day, events: store.events).filter { !$0.ongoing && inRange($0.event.coordinate) }
            for o in occ.prefix(2) {
                add(PlanItem(day: key, kind: .event, refID: o.event.id, title: o.event.title,
                             slot: slotFor(time: o.event.startTime), time: o.event.startTime))
            }
            if wet {
                // 2a. wet: two indoor places
                for p in indoor.filter({ !usedPlaces.contains($0.id) }).prefix(occ.isEmpty ? 2 : 1) {
                    usedPlaces.insert(p.id)
                    add(PlanItem(day: key, kind: .place, refID: p.id, title: p.name,
                                 slot: items(on: day).contains { $0.slot == .morning } ? .afternoon : .morning,
                                 time: nil, note: w.map { "Forecast: \($0.text.lowercased()), \(Int($0.rainMM.rounded())) mm" } ?? ""))
                }
                continue
            }
            // 2b. dry: a walk on alternate days (sheltered ones when it is windy), else a sight
            let walkDay = i % 2 == 0 || (w?.isFine ?? false)
            if walkDay, let wk = walks.first(where: { !usedWalks.contains($0.id) && (!windy || !isExposed($0)) }) {
                usedWalks.insert(wk.id)
                var notes: [String] = []
                if let w { notes.append("\(w.text), \(Int(w.tMax.rounded()))°C") }
                if wk.tideWarning != nil, let lw = store.tides?.extremes(on: day).first(where: { !$0.high }) {
                    notes.append("low water \(Day.time(lw.time)) - go on a falling tide")
                }
                add(PlanItem(day: key, kind: .walk, refID: wk.id, title: wk.title, slot: .morning, time: nil,
                             note: notes.joined(separator: "; ")))
            }
            if occ.isEmpty || !walkDay {
                let pool = windy ? indoor + outdoor : outdoor
                if let p = pool.first(where: { !usedPlaces.contains($0.id) }) {
                    usedPlaces.insert(p.id)
                    add(PlanItem(day: key, kind: .place, refID: p.id, title: p.name, slot: .afternoon, time: nil))
                }
            }
            // 3. sunset spot: evening free and (if forecast) not overcast
            let clearEvening = w.map { ($0.eveningCloud ?? 50) < 75 } ?? (i % 3 == 0)
            if clearEvening, !occ.contains(where: { slotFor(time: $0.event.startTime) == .evening }),
               let s = sunsetSpots.first(where: { !usedPlaces.contains($0.id) }) {
                usedPlaces.insert(s.id)
                let set = Sun.times(day).sunset
                add(PlanItem(day: key, kind: .place, refID: s.id, title: s.name, slot: .evening,
                             time: set.map { Day.time($0.addingTimeInterval(-45 * 60)) },
                             note: set.map { "Sunset \(Day.time($0))" } ?? ""))
            }
        }
    }

    private func isIndoor(_ p: Place) -> Bool {
        p.category == "museum" || p.tags.contains("rainy-day")
    }

    private func isExposed(_ w: Walk) -> Bool {
        let t = (w.title + " " + w.summary).lowercased()
        return w.tideWarning != nil || t.contains("cliff") || t.contains("sea wall") || t.contains("marsh")
    }

    private func rank(_ p: Place) -> Int {
        var r = 0
        if p.town.contains("Birchington") || p.town.contains("Westgate") { r += 3 }
        if ["sight", "museum", "history"].contains(p.category) { r += 2 }
        if p.category == "beach" || p.category == "nature" { r += 1 }
        return r
    }

    private func slotFor(time: String?) -> PlanItem.Slot {
        guard let t = time, let h = Int(t.prefix(2)) else { return .afternoon }
        if h < 12 { return .morning }
        if h < 17 { return .afternoon }
        return .evening
    }

    /// The week as plain text for Messages, Notes or e-mail.
    func weekText(store: Store, weather: WeatherStore? = nil) -> String {
        var s = "My week in Birchington & Thanet\n"
        for day in weekDays {
            let list = items(on: day)
            s += "\n\(Day.format(day, "EEEE d MMMM"))\n"
            if let w = weather?.forecast(for: day) {
                s += "  Weather: \(w.text), \(Int(w.tMin.rounded()))-\(Int(w.tMax.rounded()))°C\n"
            }
            if let t = store.tides?.extremes(on: day), !t.isEmpty {
                s += "  Tides: " + t.map { "\($0.high ? "HW" : "LW") \(Day.time($0.time))" }.joined(separator: ", ") + "\n"
            }
            if list.isEmpty { s += "  (free)\n" }
            for it in list {
                s += "  • \(it.time ?? it.slot.label): \(it.title)"
                if !it.note.isEmpty { s += " — \(it.note)" }
                s += "\n"
            }
        }
        return s
    }
}

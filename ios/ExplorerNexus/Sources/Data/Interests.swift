import Combine
import CoreLocation
import Foundation

/// The things you can tick for "Suggest". The PC planner has the same list and rules.
enum Interest: String, CaseIterable, Identifiable, Codable {
    case museums, history, sights, beaches, walks, wildlife, photo, family, dayTrips
    case cafes, restaurants, pubs, craftBeer, vineyards, shopping, markets, events

    var id: String { rawValue }
    var label: String {
        switch self {
        case .museums: return "Museums & galleries"
        case .history: return "History & churches"
        case .sights: return "Sights & attractions"
        case .beaches: return "Beaches & rock pools"
        case .walks: return "Walks"
        case .wildlife: return "Wildlife, nature & hides"
        case .photo: return "Photo spots & views"
        case .family: return "Family days out"
        case .dayTrips: return "Day trips"
        case .cafes: return "Cafés & treats"
        case .restaurants: return "Restaurants"
        case .pubs: return "Pubs"
        case .craftBeer: return "Breweries & craft beer"
        case .vineyards: return "Vineyards & tastings"
        case .shopping: return "Shopping"
        case .markets: return "Markets"
        case .events: return "Events, shows & festivals"
        }
    }
    var symbol: String {
        switch self {
        case .museums: return "building.2.fill"
        case .history: return "building.columns.fill"
        case .sights: return "star.fill"
        case .beaches: return "beach.umbrella.fill"
        case .walks: return "figure.walk"
        case .wildlife: return "bird.fill"
        case .photo: return "camera.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .dayTrips: return "car.fill"
        case .cafes: return "cup.and.saucer.fill"
        case .restaurants: return "fork.knife"
        case .pubs: return "mug.fill"
        case .craftBeer: return "drop.fill"
        case .vineyards: return "wineglass.fill"
        case .shopping: return "bag.fill"
        case .markets: return "basket.fill"
        case .events: return "party.popper.fill"
        }
    }
    /// Needs dry weather.
    var outdoor: Bool { [.beaches, .walks, .wildlife, .photo].contains(self) }
    /// Parts of the day it suits.
    var slots: [PlanItem.Slot] {
        switch self {
        case .pubs, .restaurants: return [.evening]
        case .craftBeer: return [.afternoon, .evening]
        case .photo: return [.evening, .morning]
        case .cafes: return [.afternoon, .morning]
        case .wildlife: return [.morning, .afternoon]
        case .vineyards, .shopping, .markets: return [.afternoon, .morning]
        case .dayTrips: return [.morning]
        default: return [.morning, .afternoon]
        }
    }

    func matches(_ p: Place) -> Bool {
        switch self {
        case .museums: return p.category == "museum"
        case .history: return ["history", "church"].contains(p.category)
        case .sights: return p.category == "sight"
        case .beaches: return p.category == "beach"
        case .wildlife: return ["hide", "nature"].contains(p.category)
        case .photo: return ["photo", "viewpoint"].contains(p.category)
        case .family: return p.category == "family" || p.tags.contains("kids")
        case .dayTrips: return p.category == "daytrip"
        case .cafes: return ["cafe", "food"].contains(p.category)
        case .restaurants: return p.category == "restaurant"
        case .pubs: return p.category == "pub"
        case .craftBeer: return p.category == "brewery" || (p.category == "pub" && (p.drink?.craft == true || p.drink?.micropub == true))
        case .vineyards: return p.category == "vineyard"
        case .shopping: return p.category == "shop"
        case .markets: return p.category == "market"
        case .walks, .events: return false
        }
    }
}

/// The ticked interests, kept between launches.
@MainActor
final class InterestStore: ObservableObject {
    @Published var chosen: Set<Interest> {
        didSet { UserDefaults.standard.set(chosen.map(\.rawValue), forKey: "suggest_interests") }
    }
    @Published var perDay: Int {
        didSet { UserDefaults.standard.set(perDay, forKey: "suggest_per_day") }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "suggest_interests")
        chosen = Set((saved ?? ["museums", "history", "beaches", "walks", "photo", "cafes", "pubs", "events"]).compactMap(Interest.init))
        let n = UserDefaults.standard.integer(forKey: "suggest_per_day")
        perDay = n == 0 ? 3 : n
    }
}

extension PlannerStore {
    /// Fills the empty days of the shown week from the ticked interests, fairly: every slot goes
    /// to the least-used interest that suits that part of the day and the forecast; places must
    /// be open then, inside the radius, and nearer places win.
    func suggestFair(store: Store, weather: WeatherStore, interests: Set<Interest>, perDay: Int,
                     origin: CLLocationCoordinate2D, inRange: (CLLocationCoordinate2D?) -> Bool) {
        guard !interests.isEmpty else { return }
        var used = Set(items.compactMap(\.refID))
        var count: [Interest: Int] = [:]
        let order = Interest.allCases.filter { interests.contains($0) }
        var rotate = 0
        let today = Day.start(Date())
        // candidates per interest, nearest/best first
        var pools: [Interest: [Place]] = [:]
        for i in order where i != .walks && i != .events {
            pools[i] = store.places.filter { i.matches($0) && inRange($0.coordinate) }
                .sorted { quality($0, origin) > quality($1, origin) }
        }
        let walks = store.walks.filter { inRange($0.points.first?.coordinate) }
            .sorted { ($0.points.first?.coordinate.distance(to: origin) ?? 0) < ($1.points.first?.coordinate.distance(to: origin) ?? 0) }
        let slotWindow: [PlanItem.Slot: (Int, Int)] = [.morning: (600, 720), .afternoon: (840, 960), .evening: (1080, 1260)]

        for day in weekDays where day >= today && items(on: day).isEmpty {
            let key = Day.key(day)
            let w = weather.forecast(for: day)
            let wet = w?.isWet ?? false
            let windy = w?.isWindy ?? false
            var filled: Set<PlanItem.Slot> = []
            var added = 0
            // events first (they have fixed times)
            if interests.contains(.events) {
                let occ = EventCalendar.on(day, events: store.events).filter { !$0.ongoing && inRange($0.event.coordinate) }
                if let o = occ.first(where: { !used.contains($0.event.id) }) {
                    let slot = slotFor(o.event.startTime)
                    add(PlanItem(day: key, kind: .event, refID: o.event.id, title: o.event.title, slot: slot, time: o.event.startTime))
                    used.insert(o.event.id)
                    filled.insert(slot)
                    count[.events, default: 0] += 1
                    added += 1
                }
            }
            for slot in PlanItem.Slot.allCases where !filled.contains(slot) && added < perDay {
                let suitable = order.filter { i in
                    i != .events && i.slots.contains(slot) && !(wet && i.outdoor) && !(windy && (i == .beaches || i == .walks))
                        && !(i == .photo && slot == .evening && (w?.eveningCloud ?? 0) > 80)
                }
                // least used first, then rotate so ties take turns
                let ranked = suitable.sorted {
                    let a = count[$0, default: 0], b = count[$1, default: 0]
                    if a != b { return a < b }
                    let ia = (order.firstIndex(of: $0)! - rotate + order.count) % order.count
                    let ib = (order.firstIndex(of: $1)! - rotate + order.count) % order.count
                    return ia < ib
                }
                rotate += 1
                let win = slotWindow[slot]!
                var placed = false
                for i in ranked {
                    if i == .walks {
                        if let wk = walks.first(where: { !used.contains($0.id) }) {
                            var note = w.map { "\($0.text), \(Int($0.tMax.rounded()))°C" } ?? ""
                            if wk.tideWarning != nil, let lw = store.tides?.extremes(on: day).first(where: { !$0.high }) {
                                note += (note.isEmpty ? "" : "; ") + "low water \(Day.time(lw.time))"
                            }
                            add(PlanItem(day: key, kind: .walk, refID: wk.id, title: wk.title, slot: slot, time: nil, note: note))
                            used.insert(wk.id)
                            placed = true
                        }
                    } else if let p = pools[i]?.first(where: { p in
                        !used.contains(p.id) && (p.hours.isOpen(on: day, from: win.0, to: win.1, whole: false) ?? true)
                    }) {
                        var note = ""
                        if i == .photo, slot == .evening, let set = Sun.times(day).sunset { note = "Sunset \(Day.time(set))" }
                        if wet && !i.outdoor { note = "Wet day - indoor" }
                        add(PlanItem(day: key, kind: .place, refID: p.id, title: p.name, slot: slot,
                                     time: i == .photo && slot == .evening ? Sun.times(day).sunset.map { Day.time($0.addingTimeInterval(-2700)) } : nil,
                                     note: note))
                        used.insert(p.id)
                        placed = true
                    }
                    if placed {
                        count[i, default: 0] += 1
                        added += 1
                        break
                    }
                }
            }
        }
    }

    private func quality(_ p: Place, _ origin: CLLocationCoordinate2D) -> Double {
        var q = 0.0
        if !p.tags.contains("osm") { q += 2 }          // researched entries first
        if p.drink?.gbg == true { q += 1.5 }
        q += Double(min(p.drink?.awards?.count ?? 0, 2))
        if p.hygiene == "5" { q += 0.3 }
        q -= p.coordinate.distance(to: origin) / 1000 * 0.25   // 4 km costs a point
        return q
    }

    private func slotFor(_ time: String?) -> PlanItem.Slot {
        guard let t = time, let h = Int(t.prefix(2)) else { return .afternoon }
        return h < 12 ? .morning : (h < 17 ? .afternoon : .evening)
    }
}

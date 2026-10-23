import Foundation

/// One event on one day. Long runs (an exhibition for three months) are "ongoing" so a
/// day list can keep them apart from things that only happen that day.
struct Occurrence: Identifiable, Hashable {
    let event: EventItem
    let day: String
    let ongoing: Bool
    var id: String { event.id + "@" + day }
}

enum EventCalendar {
    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Does the event happen on this local day?
    static func occurs(_ e: EventItem, on date: Date) -> Occurrence? {
        let key = Day.key(date)
        if let r = e.recurrence {
            if let f = r.from, key < f { return nil }
            if let u = r.until, key > u { return nil }
            let comps = Day.cal.dateComponents([.weekday, .month, .day], from: date)
            let wd = weekdayNames[(comps.weekday ?? 1) - 1]
            if let m = r.months, !m.isEmpty, !m.contains(comps.month ?? 0) { return nil }
            if let w = r.weekdays, !w.isEmpty, !w.contains(wd) { return nil }
            if r.freq == "monthly" {
                let nth = r.nth ?? [1]
                let dom = comps.day ?? 1
                let index = (dom - 1) / 7 + 1
                let daysInMonth = Day.cal.range(of: .day, in: .month, for: date)?.count ?? 31
                let isLast = dom + 7 > daysInMonth
                guard nth.contains(index) || (isLast && nth.contains(-1)) else { return nil }
            }
            // a cinema open every day is "ongoing"; a weekly market is not
            let daily = (r.weekdays?.count ?? 0) >= 6
            return Occurrence(event: e, day: key, ongoing: daily)
        }
        guard let s = e.startDate else { return nil }
        let end = e.endDate ?? s
        guard key >= s, key <= end else { return nil }
        let length = (Day.date(end).flatMap { en in Day.date(s).map { en.timeIntervalSince($0) / 86400 } }) ?? 0
        return Occurrence(event: e, day: key, ongoing: length >= 4)
    }

    static func on(_ date: Date, events: [EventItem]) -> [Occurrence] {
        events.compactMap { occurs($0, on: date) }.sorted { a, b in
            if a.ongoing != b.ongoing { return !a.ongoing }
            return (a.event.startTime ?? "99") < (b.event.startTime ?? "99")
        }
    }

    /// The next day (from `from`, up to a year ahead) the event happens.
    static func next(_ e: EventItem, from: Date = Date()) -> Date? {
        var d = Day.start(from)
        if e.recurrence == nil, let s = e.startDate, let sd = Day.date(s), sd > d { d = sd }
        for _ in 0..<370 {
            if occurs(e, on: d) != nil { return d }
            d = Day.add(1, to: d)
        }
        return nil
    }

    static func dateText(_ e: EventItem) -> String {
        if let r = e.recurrence {
            let days = (r.weekdays ?? []).joined(separator: ", ")
            if r.freq == "monthly" {
                let nth = (r.nth ?? [1]).map { $0 == -1 ? "last" : ["", "1st", "2nd", "3rd", "4th", "5th"][min(max($0, 0), 5)] }
                return "\(nth.joined(separator: " & ")) \(days) of the month"
            }
            return (r.weekdays?.count ?? 0) >= 7 ? "Daily" : "Every \(days)"
        }
        guard let s = e.startDate, let sd = Day.date(s) else { return "" }
        if let en = e.endDate, en != s, let ed = Day.date(en) {
            return "\(Day.format(sd, "EEE d MMM")) – \(Day.format(ed, "EEE d MMM yyyy"))"
        }
        return Day.format(sd, "EEEE d MMMM yyyy")
    }
}

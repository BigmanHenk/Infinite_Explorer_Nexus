import Foundation

/// A small evaluator for OpenStreetMap `opening_hours` strings (the subset the content build
/// writes): "Apr-Oct Tu-Su 10:00-17:00; Nov-Mar Sa,Su 10:00-16:00; Mo off", "24/7", "unknown".
/// Rules are applied in order; a later rule replaces the hours of the days it covers.
/// The PC planner has the same rules in JavaScript.
struct OpeningHours {
    private struct Rule {
        var months: [(Int, Int, Int, Int)]?   // (fromMonth, fromDay, toMonth, toDay), 1-based
        var days: Set<Int>?                   // 0 = Monday ... 6 = Sunday
        var times: [(Int, Int)]               // minutes; empty = closed
    }

    let raw: String
    private let rules: [Rule]
    let known: Bool

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dayNames = ["mo", "tu", "we", "th", "fr", "sa", "su"]

    init(_ s: String?) {
        raw = s ?? ""
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.lowercased() == "unknown" {
            rules = []
            known = false
            return
        }
        known = true
        if t == "24/7" {
            rules = [Rule(months: nil, days: nil, times: [(0, 1440)])]
            return
        }
        rules = t.split(separator: ";").compactMap { OpeningHours.parse(String($0)) }
    }

    private static func parse(_ text: String) -> Rule? {
        var tokens = text.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var rule = Rule(months: nil, days: nil, times: [])
        // months: "Apr-Oct", "Jul,Aug", "Feb 14-Nov 01"
        if let first = tokens.first, monthNames.contains(where: { first.lowercased().hasPrefix($0) }) {
            var sel = tokens.removeFirst()
            // "Feb 14-Nov 01" arrives as ["Feb", "14-Nov", "01"]
            while let n = tokens.first, n.first?.isNumber == true, !n.contains(":") {
                sel += " " + tokens.removeFirst()
            }
            rule.months = parseMonths(sel)
        }
        if tokens.first == "24/7" {
            rule.times = [(0, 1440)]
            return rule
        }
        if let first = tokens.first, dayNames.contains(where: { first.lowercased().hasPrefix($0) }) || first.hasPrefix("PH") {
            rule.days = parseDays(tokens.removeFirst())
        }
        guard let last = tokens.first else { return rule.months != nil || rule.days != nil ? Rule(months: rule.months, days: rule.days, times: [(0, 1440)]) : nil }
        if last.lowercased() == "off" || last.lowercased() == "closed" { return rule }
        for part in last.split(separator: ",") {
            let ends = part.split(separator: "-")
            guard ends.count == 2, let a = minutes(String(ends[0])), var b = minutes(String(ends[1])) else { continue }
            if b <= a { b += 1440 }
            rule.times.append((a, b))
        }
        return rule
    }

    private static func minutes(_ s: String) -> Int? {
        let p = s.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    private static func month(_ s: Substring) -> Int? {
        monthNames.firstIndex(where: { s.lowercased().hasPrefix($0) }).map { $0 + 1 }
    }

    private static func parseMonths(_ sel: String) -> [(Int, Int, Int, Int)] {
        var out: [(Int, Int, Int, Int)] = []
        for part in sel.split(separator: ",") {
            let ends = part.split(separator: "-")
            func md(_ x: Substring, start: Bool) -> (Int, Int)? {
                let bits = x.split(separator: " ")
                guard let m = month(bits[0]) else { return nil }
                if bits.count > 1, let d = Int(bits[1]) { return (m, d) }
                return (m, start ? 1 : 31)
            }
            if ends.count == 2, let a = md(ends[0], start: true), let b = md(ends[1], start: false) {
                out.append((a.0, a.1, b.0, b.1))
            } else if let a = md(ends[0], start: true) {
                out.append((a.0, 1, a.0, 31))
            }
        }
        return out
    }

    private static func parseDays(_ sel: String) -> Set<Int> {
        var out = Set<Int>()
        for part in sel.split(separator: ",") {
            let ends = part.split(separator: "-").map { String($0).lowercased() }
            guard let a = dayNames.firstIndex(of: String(ends[0].prefix(2))) else { continue }
            if ends.count == 2, let b = dayNames.firstIndex(of: String(ends[1].prefix(2))) {
                var i = a
                while true { out.insert(i); if i == b { break }; i = (i + 1) % 7 }
            } else {
                out.insert(a)
            }
        }
        return out
    }

    /// Opening intervals (minutes from midnight) on a day; nil when the hours are unknown.
    func intervals(on date: Date) -> [(Int, Int)]? {
        guard known else { return nil }
        let c = Day.cal.dateComponents([.month, .day, .weekday], from: date)
        let m = c.month ?? 1, d = c.day ?? 1
        let wd = ((c.weekday ?? 1) + 5) % 7      // Monday = 0
        var result: [(Int, Int)] = []
        var matched = false
        for r in rules {
            if let months = r.months {
                let v = m * 100 + d
                let hit = months.contains { a in
                    let from = a.0 * 100 + a.1, to = a.2 * 100 + a.3
                    return from <= to ? (v >= from && v <= to) : (v >= from || v <= to)
                }
                if !hit { continue }
            }
            matched = true      // this date is inside a season the venue published
            if let days = r.days, !days.contains(wd) { continue }
            result = r.times
        }
        // only seasonal rules and none covers this date: the venue has not published it
        if !matched && !rules.isEmpty && rules.allSatisfy({ $0.months != nil }) { return nil }
        return result
    }

    /// Open at some point between `from` and `to` (minutes), or for all of it.
    func isOpen(on date: Date, from: Int, to: Int, whole: Bool) -> Bool? {
        guard let iv = intervals(on: date) else { return nil }
        if whole { return iv.contains { $0.0 <= from && $0.1 >= to } }
        return iv.contains { $0.0 < to && $0.1 > from }
    }

    func openNow(_ now: Date = Date()) -> Bool? {
        let c = Day.cal.dateComponents([.hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return isOpen(on: now, from: m, to: m + 1, whole: false)
    }

    /// "10:00–17:00" for a day, "Closed", or nil when unknown.
    func text(on date: Date) -> String? {
        guard let iv = intervals(on: date) else { return nil }
        if iv.isEmpty { return "Closed" }
        if iv.count == 1 && iv[0].0 == 0 && iv[0].1 >= 1440 { return "Open all day" }
        return iv.map { String(format: "%02d:%02d–%02d:%02d", $0.0 / 60, $0.0 % 60, ($0.1 / 60) % 24, $0.1 % 60) }.joined(separator: ", ")
    }
}

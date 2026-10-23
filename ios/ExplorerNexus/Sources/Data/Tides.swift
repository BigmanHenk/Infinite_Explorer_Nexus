import Foundation

struct TideExtreme: Identifiable, Hashable {
    let time: Date
    let height: Double     // metres above chart datum
    let high: Bool
    var id: Date { time }
}

/// Tide predictions for Margate/Birchington, precomputed on the PC (tools/build/s03_tides.py,
/// harmonic constants fitted to the Environment Agency's Dover and Sheerness gauges) for
/// many years ahead, so nothing is computed or fetched on the phone.
/// Table tide_days: day (UTC, yyyy-MM-dd), heights (Int16 cm, every 10 min from 00:00 UTC),
/// extremes ("minute:cm:H|minute:cm:L|...", minutes after 00:00 UTC).
final class TideTable {
    private let db: SQLiteDB
    let station: String
    let datumNote: String
    let accuracyNote: String
    let firstDay: String
    let lastDay: String
    private var cache: [String: (heights: [Int16], extremes: [TideExtreme])] = [:]
    private let lock = NSLock()

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private static let utcKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init?(db: SQLiteDB, meta: [String: String]) {
        guard let first = meta["tide_first_day"], let last = meta["tide_last_day"] else { return nil }
        self.db = db
        station = meta["tide_station"] ?? "Margate"
        datumNote = meta["tide_datum"] ?? "Heights in metres above chart datum."
        accuracyNote = meta["tide_accuracy"] ?? ""
        firstDay = first
        lastDay = last
    }

    private func day(_ key: String) -> (heights: [Int16], extremes: [TideExtreme])? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cache[key] { return c }
        guard let start = Self.utcKey.date(from: key) else { return nil }
        var result: (heights: [Int16], extremes: [TideExtreme])?
        db.query("SELECT heights, extremes FROM tide_days WHERE day = ?", [key]) { r in
            var h: [Int16] = []
            if let d = r.data(0) {
                h = d.withUnsafeBytes { raw in
                    (0..<(d.count / 2)).map { raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self) }
                }
            }
            var ex: [TideExtreme] = []
            for part in r.text(1).split(separator: "|") {
                let f = part.split(separator: ":")
                guard f.count == 3, let m = Double(f[0]), let cm = Double(f[1]) else { continue }
                ex.append(TideExtreme(time: start.addingTimeInterval(m * 60), height: cm / 100, high: f[2] == "H"))
            }
            result = (h, ex)
        }
        if let result { cache[key] = result }
        return result
    }

    /// Height (m above chart datum) at any moment, linear between the 10-minute samples.
    func height(at t: Date) -> Double? {
        let key = Self.utcKey.string(from: t)
        guard let start = Self.utcKey.date(from: key), let d = day(key), !d.heights.isEmpty else { return nil }
        let x = t.timeIntervalSince(start) / 600
        let i = Int(x)
        let frac = x - Double(i)
        let a = Double(d.heights[min(i, d.heights.count - 1)])
        let b: Double
        if i + 1 < d.heights.count {
            b = Double(d.heights[i + 1])
        } else if let next = self.day(Self.utcKey.string(from: start.addingTimeInterval(86400))), let f = next.heights.first {
            b = Double(f)
        } else {
            b = a
        }
        return (a + (b - a) * frac) / 100
    }

    /// High and low waters on a local (UK) day.
    func extremes(on localDay: Date) -> [TideExtreme] {
        let start = Day.start(localDay)
        let end = Day.add(1, to: start)
        var out: [TideExtreme] = []
        for off in -1...1 {
            let key = Self.utcKey.string(from: start.addingTimeInterval(Double(off) * 86400 + 43200))
            out += day(key)?.extremes ?? []
        }
        var seen = Set<Date>()
        return out.filter { $0.time >= start && $0.time < end && seen.insert($0.time).inserted }.sorted { $0.time < $1.time }
    }

    /// The next few high/low waters after a moment.
    func upcoming(from t: Date, count: Int = 4) -> [TideExtreme] {
        var out: [TideExtreme] = []
        var d = Day.start(t)
        for _ in 0..<4 {
            out += extremes(on: d).filter { $0.time > t }
            if out.count >= count { break }
            d = Day.add(1, to: d)
        }
        return Array(out.prefix(count))
    }

    /// (time, height) every 10 minutes over a local day, for the chart.
    func curve(on localDay: Date, step: TimeInterval = 600) -> [(Date, Double)] {
        let start = Day.start(localDay)
        let end = Day.add(1, to: start)
        var out: [(Date, Double)] = []
        var t = start
        while t <= end {
            if let h = height(at: t) { out.append((t, h)) }
            t = t.addingTimeInterval(step)
        }
        return out
    }

    func rising(at t: Date) -> Bool? {
        guard let a = height(at: t), let b = height(at: t.addingTimeInterval(600)) else { return nil }
        return b > a
    }

    /// Spring/neap feel from the day's range.
    func rangeText(on localDay: Date) -> String? {
        let ex = extremes(on: localDay)
        guard let hi = ex.filter({ $0.high }).map(\.height).max(),
              let lo = ex.filter({ !$0.high }).map(\.height).min() else { return nil }
        let r = hi - lo
        let kind = r > 4.0 ? "spring tides" : (r < 2.8 ? "neap tides" : "mid-range tides")
        return String(format: "Range %.1f m · %@", r, kind)
    }

    func covers(_ d: Date) -> Bool {
        let k = Self.utcKey.string(from: d)
        return k >= firstDay && k <= lastDay
    }
}

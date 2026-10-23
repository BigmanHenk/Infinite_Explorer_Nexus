import Foundation

/// 7-day forecast for Birchington from the Met Office UK models (UKV + global), served
/// free and without a key by Open-Meteo (CC BY 4.0). Fetched when there is signal and kept
/// in Documents, so the last forecast is still there offline.
struct WeatherDay: Codable, Hashable {
    let day: String          // yyyy-MM-dd
    let code: Int            // WMO weather code
    let tMax: Double
    let tMin: Double
    let rainMM: Double
    let rainHours: Double
    let windMph: Double
    let gustMph: Double
    let sunHours: Double
    /// Cloud cover (%) around sunset, for sunset photo suggestions.
    var eveningCloud: Double?

    var isWet: Bool { rainMM >= 4 || rainHours >= 4 }
    var isWindy: Bool { gustMph >= 38 }
    var isFine: Bool { !isWet && rainMM < 1.5 && gustMph < 32 }

    var symbol: String { WeatherDay.symbol(code) }
    var text: String { WeatherDay.text(code) }

    static func symbol(_ c: Int) -> String {
        switch c {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ c: Int) -> String {
        switch c {
        case 0: return "Sunny"
        case 1: return "Mostly sunny"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61, 80: return "Light rain"
        case 63, 81: return "Rain"
        case 65, 82: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorms"
        default: return "Mixed"
        }
    }

    /// One line for the planner.
    var advice: String {
        if isWet { return "Wet - an indoor day (museums, cinema, cafés)" }
        if isWindy { return "Very windy - avoid exposed cliff-top paths and the sea wall at high tide" }
        if isFine { return sunHours >= 6 ? "Fine and sunny - a good day for a walk or the beach" : "Dry - fine for walking" }
        return "Showers possible - take a coat"
    }
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var days: [WeatherDay] = []
    @Published private(set) var fetched: Date?
    @Published private(set) var model = ""
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("weather.json")

    private struct Saved: Codable { let days: [WeatherDay]; let fetched: Date; let model: String }

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            days = s.days; fetched = s.fetched; model = s.model
        }
    }

    func forecast(for day: Date) -> WeatherDay? {
        let k = Day.key(day)
        return days.first { $0.day == k }
    }

    var ageText: String? {
        guard let fetched else { return nil }
        let h = Int(Date().timeIntervalSince(fetched) / 3600)
        if h < 1 { return "updated just now" }
        if h < 48 { return "updated \(h) h ago" }
        return "updated \(h / 24) days ago - connect to refresh"
    }

    /// Refresh when older than an hour (or forced).
    func refresh(force: Bool = false) async {
        if !force, let f = fetched, Date().timeIntervalSince(f) < 3600 { return }
        loading = true
        defer { loading = false }
        // Met Office first; Open-Meteo's best-match blend if that model is unavailable.
        for (models, label) in [("ukmo_seamless", "Met Office UKV / global"), ("best_match", "Open-Meteo best match")] {
            if let d = await fetch(models: models) {
                days = d
                fetched = Date()
                model = label
                error = nil
                if let data = try? JSONEncoder().encode(Saved(days: d, fetched: fetched!, model: label)) {
                    try? data.write(to: url, options: .atomic)
                }
                return
            }
        }
        error = "No connection - showing the last forecast."
    }

    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_sum: [Double?]
            let precipitation_hours: [Double?]
            let wind_speed_10m_max: [Double?]
            let wind_gusts_10m_max: [Double?]
            let sunshine_duration: [Double?]
        }
        struct Hourly: Decodable {
            let time: [String]
            let cloud_cover: [Double?]
        }
        let daily: Daily
        let hourly: Hourly?
    }

    private func fetch(models: String) async -> [WeatherDay]? {
        let lat = Sun.birchington.latitude, lon = Sun.birchington.longitude
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_hours,"
            + "wind_speed_10m_max,wind_gusts_10m_max,sunshine_duration&hourly=cloud_cover"
            + "&models=\(models)&timezone=Europe%2FLondon&forecast_days=7&wind_speed_unit=mph"
        guard let u = URL(string: s) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let d = r.daily
        var out: [WeatherDay] = []
        for i in d.time.indices {
            guard let code = d.weather_code[safe: i] ?? nil, let tx = d.temperature_2m_max[safe: i] ?? nil,
                  let tn = d.temperature_2m_min[safe: i] ?? nil else { continue }
            var w = WeatherDay(day: d.time[i], code: code, tMax: tx, tMin: tn,
                               rainMM: (d.precipitation_sum[safe: i] ?? nil) ?? 0,
                               rainHours: (d.precipitation_hours[safe: i] ?? nil) ?? 0,
                               windMph: (d.wind_speed_10m_max[safe: i] ?? nil) ?? 0,
                               gustMph: (d.wind_gusts_10m_max[safe: i] ?? nil) ?? 0,
                               sunHours: ((d.sunshine_duration[safe: i] ?? nil) ?? 0) / 3600)
            if let h = r.hourly, let date = Day.date(d.time[i]), let set = Sun.times(date).sunset {
                let hour = Day.format(set, "yyyy-MM-dd'T'HH:00")
                if let j = h.time.firstIndex(of: hour) { w.eveningCloud = h.cloud_cover[safe: j] ?? nil }
            }
            out.append(w)
        }
        return out.isEmpty ? nil : out
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

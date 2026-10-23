import CoreLocation
import Foundation

/// Sun position and the photographer's times (sunrise/sunset, golden and blue hours),
/// computed on the phone with the NOAA solar equations - no data needed.
enum Sun {
    static let birchington = CLLocationCoordinate2D(latitude: 51.3770, longitude: 1.3050)

    /// Altitude and azimuth (degrees; azimuth from north, clockwise).
    static func position(_ t: Date, _ c: CLLocationCoordinate2D = birchington) -> (altitude: Double, azimuth: Double) {
        let jd = t.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (jd - 2451545.0) / 36525
        let l0 = (280.46646 + n * (36000.76983 + n * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + n * (35999.05029 - 0.0001537 * n)
        let e = 0.016708634 - n * (0.000042037 + 0.0000001267 * n)
        let mr = m * .pi / 180
        let eqc = sin(mr) * (1.914602 - n * (0.004817 + 0.000014 * n)) + sin(2 * mr) * (0.019993 - 0.000101 * n) + sin(3 * mr) * 0.000289
        let trueLong = l0 + eqc
        let omega = 125.04 - 1934.136 * n
        let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * .pi / 180)
        let eps0 = 23 + (26 + (21.448 - n * (46.815 + n * (0.00059 - n * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * .pi / 180)
        let decl = asin(sin(eps * .pi / 180) * sin(lambda * .pi / 180))
        let y = pow(tan(eps * .pi / 360), 2)
        let l0r = l0 * .pi / 180
        let eqTime = 4 * (y * sin(2 * l0r) - 2 * e * sin(mr) + 4 * e * y * sin(mr) * cos(2 * l0r)
                          - 0.5 * y * y * sin(4 * l0r) - 1.25 * e * e * sin(2 * mr)) * 180 / .pi
        let minutesUTC = (jd + 0.5 - floor(jd + 0.5)) * 1440
        var tst = (minutesUTC + eqTime + 4 * c.longitude).truncatingRemainder(dividingBy: 1440)
        if tst < 0 { tst += 1440 }
        var ha = tst / 4 - 180
        if ha < -180 { ha += 360 }
        let lat = c.latitude * .pi / 180
        let har = ha * .pi / 180
        let cosZen = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(har)
        let zen = acos(max(-1, min(1, cosZen)))
        var alt = 90 - zen * 180 / .pi
        // atmospheric refraction (approximate)
        if alt > -0.575 {
            let te = tan(alt * .pi / 180)
            if alt > 5 { alt += (58.1 / te - 0.07 / pow(te, 3) + 0.000086 / pow(te, 5)) / 3600 }
            else { alt += (1735 + alt * (-518.2 + alt * (103.4 + alt * (-12.79 + alt * 0.711)))) / 3600 }
        } else {
            alt += (-20.774 / tan(alt * .pi / 180)) / 3600
        }
        var az = atan2(sin(har), cos(har) * sin(lat) - tan(decl) * cos(lat)) * 180 / .pi + 180
        az = az.truncatingRemainder(dividingBy: 360)
        return (alt, az)
    }

    struct DayTimes {
        let sunrise: Date?
        let sunset: Date?
        let solarNoon: Date
        let morningGolden: (Date, Date)?    // sun -4° .. +6°
        let eveningGolden: (Date, Date)?
        let morningBlue: (Date, Date)?      // sun -6° .. -4°
        let eveningBlue: (Date, Date)?
        let sunriseAzimuth: Double?
        let sunsetAzimuth: Double?
        var daylight: TimeInterval? {
            guard let r = sunrise, let s = sunset else { return nil }
            return s.timeIntervalSince(r)
        }
    }

    /// Times when the sun crosses `altitude`, found by stepping then bisecting.
    private static func crossings(_ day: Date, _ altitude: Double, _ c: CLLocationCoordinate2D) -> (rise: Date?, set: Date?) {
        let start = Day.start(day)
        var rise: Date?
        var set: Date?
        var prevT = start
        var prev = position(start, c).altitude - altitude
        var t = start
        for _ in 0..<(24 * 6) {
            t = t.addingTimeInterval(600)
            let v = position(t, c).altitude - altitude
            if (prev < 0) != (v < 0) {
                var a = prevT, b = t, fa = prev
                for _ in 0..<20 {
                    let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
                    let fm = position(mid, c).altitude - altitude
                    if (fa < 0) == (fm < 0) { a = mid; fa = fm } else { b = mid }
                }
                if prev < 0 { if rise == nil { rise = a } } else { set = a }
            }
            prevT = t
            prev = v
        }
        return (rise, set)
    }

    static func times(_ day: Date, _ c: CLLocationCoordinate2D = birchington) -> DayTimes {
        let horizon = crossings(day, -0.833, c)
        let g6 = crossings(day, 6, c)
        let g4 = crossings(day, -4, c)
        let b6 = crossings(day, -6, c)
        var noon = Day.start(day)
        var best = -90.0
        var t = Day.start(day)
        for _ in 0..<(24 * 12) {
            t = t.addingTimeInterval(300)
            let a = position(t, c).altitude
            if a > best { best = a; noon = t }
        }
        func pair(_ a: Date?, _ b: Date?) -> (Date, Date)? {
            guard let a, let b else { return nil }
            return a < b ? (a, b) : (b, a)
        }
        return DayTimes(
            sunrise: horizon.rise, sunset: horizon.set, solarNoon: noon,
            morningGolden: pair(g4.rise, g6.rise), eveningGolden: pair(g6.set, g4.set),
            morningBlue: pair(b6.rise, g4.rise), eveningBlue: pair(g4.set, b6.set),
            sunriseAzimuth: horizon.rise.map { position($0, c).azimuth },
            sunsetAzimuth: horizon.set.map { position($0, c).azimuth })
    }

    static func compass(_ az: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return names[Int((az / 22.5).rounded()) % 16]
    }

    /// Moon phase 0 (new) ... 0.5 (full) ... 1, from the mean synodic month.
    static func moonPhase(_ t: Date) -> Double {
        let ref = Date(timeIntervalSince1970: 947182440)   // new moon 2000-01-06 18:14 UTC
        let days = t.timeIntervalSince(ref) / 86400
        let p = days / 29.530588853
        return p - floor(p)
    }

    static func moonText(_ t: Date) -> (name: String, symbol: String) {
        let p = moonPhase(t)
        switch p {
        case ..<0.03, 0.97...: return ("New moon", "moonphase.new.moon")
        case ..<0.22: return ("Waxing crescent", "moonphase.waxing.crescent")
        case ..<0.28: return ("First quarter", "moonphase.first.quarter")
        case ..<0.47: return ("Waxing gibbous", "moonphase.waxing.gibbous")
        case ..<0.53: return ("Full moon", "moonphase.full.moon")
        case ..<0.72: return ("Waning gibbous", "moonphase.waning.gibbous")
        case ..<0.78: return ("Last quarter", "moonphase.last.quarter")
        default: return ("Waning crescent", "moonphase.waning.crescent")
        }
    }
}

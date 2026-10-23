import CoreLocation
import SwiftUI
import UIKit

/// Rough door-to-door times from the base, worked out on the phone (no signal needed):
/// straight-line distance x a detour factor at typical speeds. Exact routes: Apple Maps.
struct TravelEstimate {
    let metres: CLLocationDistance

    // detour factor, km/h, fixed minutes (getting going / parking)
    var walkMin: Int { minutes(1.30, 4.8, 0) }
    var bikeMin: Int { minutes(1.30, 14, 1) }
    var carMin: Int { minutes(1.40, 38, 3) }

    private func minutes(_ detour: Double, _ kmh: Double, _ fixed: Double) -> Int {
        max(1, Int((metres / 1000 * detour / kmh * 60 + fixed).rounded()))
    }

    static func text(_ m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }
}

/// "How far, how long" from my base, with buttons for exact directions.
struct TravelCard: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    let to: CLLocationCoordinate2D
    let name: String

    var body: some View {
        let origin = base.origin(location)
        let est = TravelEstimate(metres: origin.distance(to: to))
        Card {
            HStack {
                Label("Getting there", systemImage: "point.topleft.down.to.point.bottomright.curvepath").cardTitle(theme)
                Spacer()
                BaseChip()
            }
            Text("\(distanceText(est.metres)) from \(base.mode == .gps && location.location != nil ? "where you are" : base.name)")
                .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
            HStack(spacing: 8) {
                mode("figure.walk", TravelEstimate.text(est.walkMin), est.metres < 12_000)
                mode("bicycle", TravelEstimate.text(est.bikeMin), est.metres < 40_000)
                mode("car.fill", TravelEstimate.text(est.carMin), true)
            }
            Menu {
                Button { open("w") } label: { Label("Walking", systemImage: "figure.walk") }
                Button { open("d") } label: { Label("Driving", systemImage: "car") }
                Button { open("r") } label: { Label("Bus & train", systemImage: "tram") }
                Button { open("c") } label: { Label("Cycling", systemImage: "bicycle") }
            } label: {
                Label("Exact directions in Apple Maps (needs signal)", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Times are estimates for the usual roads and paths.")
                .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
        }
    }

    private func mode(_ symbol: String, _ text: String, _ sensible: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.title3).foregroundStyle(theme.t.primary)
            Text(text).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(theme.t.onBackground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(theme.t.surfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .opacity(sensible ? 1 : 0.45)
    }

    /// dirflg w walk, d drive, r transit, c cycle; from the fixed base, or the phone's position.
    private func open(_ flag: String) {
        var s = "http://maps.apple.com/?daddr=\(to.latitude),\(to.longitude)&dirflg=\(flag)"
        if base.mode == .fixed || location.location == nil {
            s += "&saddr=\(base.lat),\(base.lon)"
        }
        if let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { s += "&q=\(q)" }
        if let u = URL(string: s) { UIApplication.shared.open(u) }
    }
}

/// Where to read more: the official site first, then the pages the entry was researched
/// from, then a web search.
struct MoreInfoLinks: View {
    @EnvironmentObject var theme: ThemeStore
    let name: String
    let town: String
    var website: String?
    var sources: [String] = []

    private var others: [URL] {
        sources.compactMap(URL.init(string:)).filter { $0.absoluteString != website && !($0.host ?? "").contains("openstreetmap") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let w = website, let u = URL(string: w) {
                Link(destination: u) {
                    Label("Official website", systemImage: "safari.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(theme.t.onPrimary).background(theme.t.primary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if !others.isEmpty {
                Text("MORE INFORMATION").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(theme.t.primary)
                ForEach(others.prefix(4), id: \.self) { u in
                    Link(destination: u) {
                        Label(host(u), systemImage: "link").font(.subheadline).lineLimit(1)
                    }
                }
            }
            if let u = URL(string: "https://www.google.com/search?q=" + ("\(name) \(town)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                Link(destination: u) { Label("Search the web for \(name)", systemImage: "magnifyingglass").font(.subheadline).lineLimit(1) }
            }
        }
        .tint(theme.t.primary)
    }

    private func host(_ u: URL) -> String {
        let h = (u.host ?? u.absoluteString).replacingOccurrences(of: "www.", with: "")
        let path = u.path.split(separator: "/").last.map { " · " + $0.replacingOccurrences(of: "-", with: " ").prefix(40) } ?? ""
        return h + path
    }
}

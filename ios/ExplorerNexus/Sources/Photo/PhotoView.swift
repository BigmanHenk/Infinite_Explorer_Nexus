import SwiftUI

/// For the photographer: today's light (golden/blue hours, sun directions, moon), the tide
/// now, and the photo spots and wildlife hides, filtered by subject.
struct PhotoView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var weather: WeatherStore
    @State private var day = Day.start(Date())
    @State private var subject: String? = nil
    @State private var hidesOnly = false

    private var subjects: [String] {
        var count: [String: Int] = [:]
        for p in store.photoSpots { for s in p.subjects { count[s, default: 0] += 1 } }
        return count.filter { $0.value >= 2 }.keys.sorted()
    }

    private var spots: [Place] {
        store.photoSpots.filter { p in
            (!hidesOnly || p.category == "hide") && (subject == nil || p.subjects.contains(subject!))
        }
    }

    var body: some View {
        List {
            Section { lightCard.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "Hides", symbol: "bird", on: hidesOnly) { hidesOnly.toggle() }
                        ForEach(subjects, id: \.self) { s in
                            Chip(text: s.capitalized, on: subject == s) { subject = subject == s ? nil : s }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                ForEach(spots) { p in
                    NavigationLink(value: p) {
                        VStack(alignment: .leading, spacing: 3) {
                            PlaceRow(place: p)
                            if let b = p.bestTime { Text(b).font(.caption2).lineLimit(2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7)) }
                        }
                    }
                    .listRowBackground(theme.t.surface)
                }
            } header: { SectionHead("\(spots.count) spots") }
        }
        .themedList()
        .navigationTitle("Photo spots & hides")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lightCard: some View {
        let t = Sun.times(day)
        let moon = Sun.moonText(day.addingTimeInterval(22 * 3600))
        return Card {
            HStack {
                Button { day = Day.add(-1, to: day) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(Day.format(day, "EEEE d MMMM")).font(.headline).foregroundStyle(theme.t.onBackground)
                Spacer()
                Button { day = Day.add(1, to: day) } label: { Image(systemName: "chevron.right") }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Blue hour", "moon.haze", t.morningBlue, t.eveningBlue)
                row("Golden hour", "camera.aperture", t.morningGolden, t.eveningGolden)
                GridRow {
                    Label("Sun", systemImage: "sun.horizon").foregroundStyle(theme.t.primary)
                    Text(t.sunrise.map { "↑ \(Day.time($0))" + (t.sunriseAzimuth.map { " \(Sun.compass($0)) \(Int($0))°" } ?? "") } ?? "–")
                    Text(t.sunset.map { "↓ \(Day.time($0))" + (t.sunsetAzimuth.map { " \(Sun.compass($0)) \(Int($0))°" } ?? "") } ?? "–")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(theme.t.onBackground)
            HStack(spacing: 6) {
                Image(systemName: moon.symbol)
                Text("\(moon.name) tonight")
                if let w = weather.forecast(for: day), let c = w.eveningCloud {
                    Text("· sunset cloud \(Int(c))%")
                }
            }
            .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
            if let tides = store.tides {
                let ex = tides.extremes(on: day)
                if !ex.isEmpty { TideRow(extremes: ex) }
            }
            Text("Thanet's north coast faces north: in summer the sun sets over the sea to the north-west (Minnis Bay, Reculver); in winter it rises and sets further south, so try Pegwell Bay and Ramsgate.")
                .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ symbol: String, _ a: (Date, Date)?, _ b: (Date, Date)?) -> some View {
        GridRow {
            Label(title, systemImage: symbol).foregroundStyle(theme.t.primary)
            Text(a.map { "\(Day.time($0.0))–\(Day.time($0.1))" } ?? "–")
            Text(b.map { "\(Day.time($0.0))–\(Day.time($0.1))" } ?? "–")
        }
    }
}

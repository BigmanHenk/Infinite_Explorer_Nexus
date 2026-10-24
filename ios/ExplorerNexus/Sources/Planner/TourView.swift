import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Tour builder: theme, day, start time and hours available -> a timed route through the best
/// places that are open when you get there, shortest order first.
struct TourView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var planner: PlannerStore
    @EnvironmentObject var weather: WeatherStore
    @State private var tourTheme: TourTheme = .pubs
    @State private var day = Day.start(Date())
    @State private var startMinute = 19 * 60
    @State private var hours = 3.0
    @State private var drive = false
    @State private var back = true
    @State private var excluded: Set<String> = []
    @State private var tour: Tour?
    @State private var added = false
    @State private var fullMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                options
                Button { build() } label: {
                    Label(tour == nil ? "Build my tour" : "Build again", systemImage: "wand.and.stars")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(theme.t.onPrimary).background(theme.t.primary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                if let t = tour { result(t) }
                Text("Places are ranked on facts from CAMRA, the Good Beer Guide, awards, what they serve and the food hygiene rating - not on review scores. Check opening times on the day.")
                    .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationTitle("Tour builder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if tour == nil { applyThemeDefaults() } }
        .fullScreenCover(isPresented: $fullMap) {
            if let t = tour {
                FullScreenMap(title: tourTheme.rawValue, places: t.stops.map(\.place), walk: walk(t),
                              focus: MapFocus.fit([t.start] + t.stops.map(\.place.coordinate)))
            }
        }
    }

    private var options: some View {
        Card {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TourTheme.allCases) { t in
                        Chip(text: t.rawValue, symbol: t.symbol, on: tourTheme == t) {
                            tourTheme = t
                            applyThemeDefaults()
                        }
                    }
                }
            }
            HStack { BaseChip(); Spacer() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<14, id: \.self) { i in
                        let d = Day.add(i, to: Day.start(Date()))
                        let sel = Day.key(d) == Day.key(day)
                        Button { day = d } label: {
                            VStack(spacing: 1) {
                                Text(i == 0 ? "Today" : Day.weekdayShort(d)).font(.caption2.weight(.semibold))
                                Text(Day.format(d, "d")).font(.subheadline.weight(.bold))
                            }
                            .frame(width: 46, height: 44)
                            .foregroundStyle(sel ? theme.t.onPrimary : theme.t.onSurfaceVariant)
                            .background(sel ? theme.t.primary : theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("Start \(TourPlanner.hm(startMinute))").font(.subheadline.weight(.semibold).monospacedDigit())
                Slider(value: Binding(get: { Double(startMinute) }, set: { startMinute = Int($0) }), in: 360...1320, step: 15)
            }
            HStack {
                Text(String(format: "%.1f h", hours)).font(.subheadline.weight(.semibold).monospacedDigit()).frame(width: 52, alignment: .leading)
                Slider(value: $hours, in: 1...10, step: 0.5)
            }
            Picker("", selection: $drive) {
                Text("On foot").tag(false)
                Text("By car").tag(true)
            }
            .pickerStyle(.segmented)
            Toggle("End back where I started", isOn: $back)
            if let w = weather.forecast(for: day) {
                Text("\(w.text), \(Int(w.tMax.rounded()))°C - \(w.advice)").font(.caption)
                    .foregroundStyle(w.isWet || w.isWindy ? .orange : theme.t.onSurfaceVariant.opacity(0.8))
            }
        }
    }

    @ViewBuilder private func result(_ t: Tour) -> some View {
        if t.stops.isEmpty {
            Card {
                Text("Nothing fits - try a longer time, another day, a wider radius or by car.")
                    .font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant)
            }
        } else {
            OfflineMapView(places: t.stops.map(\.place), walk: walk(t), showWaypoints: true,
                           routeColor: UIColor(theme.t.primary), accent: UIColor(theme.t.primary),
                           focus: MapFocus.fit([t.start] + t.stops.map(\.place.coordinate)))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) { ExpandMapButton { fullMap = true } }
            Card {
                HStack {
                    Label("\(t.stops.count) stops", systemImage: tourTheme.symbol).cardTitle(theme)
                    Spacer()
                    Text("\(TourPlanner.hm(t.startMinute))–\(TourPlanner.hm((t.stops.last?.leave ?? t.startMinute) + (t.backMinutes ?? 0)))")
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(theme.t.primary)
                }
                Text("\(distanceText(t.totalMetres)) · \(t.totalTravel) min \(drive ? "driving" : "walking") in total")
                    .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                ForEach(Array(t.stops.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 6) {
                        Image(systemName: drive ? "car" : "figure.walk").font(.caption2)
                        Text("\(s.legMinutes) min · \(distanceText(s.legMetres))").font(.caption2)
                    }
                    .foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
                    .padding(.leading, 30)
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(theme.t.onPrimary)
                            .frame(width: 22, height: 22).background(theme.t.primary, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            NavigationLink(value: s.place) {
                                Text(s.place.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            Text("\(TourPlanner.hm(s.arrive))–\(TourPlanner.hm(s.leave)) · \(s.place.town)")
                                .font(.caption.monospacedDigit()).foregroundStyle(theme.t.primary)
                            if let b = s.place.drink?.badges, !b.isEmpty {
                                Text(b.prefix(4).joined(separator: " · ")).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                            }
                            if !s.place.hours.known {
                                Text("Opening hours not known - check first").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button { excluded.insert(s.place.id); build() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                        }
                        .help("Swap for another place")
                    }
                }
                if let b = t.backMinutes {
                    Text("Back to the start: \(b) min").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6)).padding(.leading, 30)
                }
                HStack(spacing: 10) {
                    Button {
                        let key = Day.key(day)
                        for s in t.stops {
                            planner.add(PlanItem(day: key, kind: .place, refID: s.place.id, title: s.place.name,
                                                 slot: s.arrive < 720 ? .morning : (s.arrive < 1020 ? .afternoon : .evening),
                                                 time: TourPlanner.hm(s.arrive), note: tourTheme.rawValue))
                        }
                        planner.weekStart = Day.weekStart(day)
                        added = true
                    } label: { Label(added ? "Added" : "Add to my week", systemImage: added ? "checkmark" : "calendar.badge.plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(added)
                    if let u = TourPlanner.googleURL(t, drive: drive, returnToStart: back) {
                        Link(destination: u) { Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                            .buttonStyle(.bordered)
                    }
                }
                Text("Tap ⟳ next to a stop to swap it for another place.").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
            }
        }
    }

    /// The tour drawn as a route (straight legs between the stops).
    private func walk(_ t: Tour) -> Walk {
        var route = [t.start] + t.stops.map(\.place.coordinate)
        if back { route.append(t.start) }
        let pts = t.stops.map { WalkPoint(name: $0.place.name, lat: $0.place.lat, lon: $0.place.lon, note: nil) }
        return Walk(id: "tour", title: tourTheme.rawValue, distanceKm: t.totalMetres / 1000, durationMin: nil, difficulty: "easy",
                    surface: nil, circular: back, start: base.name, summary: "", description: "", toilets: nil, refreshments: nil,
                    parking: nil, publicTransport: nil, dogs: nil, accessibility: nil, tideWarning: nil, sources: [],
                    points: pts, route: route)
    }

    private func applyThemeDefaults() {
        switch tourTheme {
        case .pubs, .craft: startMinute = 18 * 60 + 30; hours = 3.5
        case .sights, .mixed: startMinute = 10 * 60; hours = 6
        case .cafes: startMinute = 14 * 60; hours = 2
        case .photo: startMinute = 15 * 60; hours = 3
        }
        excluded = []
        tour = nil
    }

    private func build() {
        let inRange = store.places.filter { base.within($0.coordinate, location) }
        tour = TourPlanner.plan(places: inRange, theme: tourTheme, start: base.origin(location), day: day,
                                startMinute: startMinute, hours: hours, drive: drive, returnToStart: back, exclude: excluded)
        added = false
    }
}

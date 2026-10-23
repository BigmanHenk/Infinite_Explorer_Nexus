import SwiftUI
import UIKit

/// Explore: every place in the database, filtered by category, searchable, nearest first
/// when the phone knows where it is.
struct PlacesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var base: BaseStore
    @State private var category: String? = nil
    @State private var search = ""
    @State private var sortNear = true
    @State private var tag: String? = nil

    private var categories: [String] {
        let present = Set(store.places.map(\.category))
        return Cat.order.filter { present.contains($0) }
    }

    private var filtered: [Place] {
        var list = store.places.filter { base.within($0.coordinate, location) }
        if let category { list = list.filter { $0.category == category } }
        if let tag { list = list.filter { $0.tags.contains(tag) } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) || $0.town.lowercased().contains(q)
                    || $0.summary.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        if sortNear {
            let o = base.origin(location)
            list.sort { $0.coordinate.distance(to: o) < $1.coordinate.distance(to: o) }
        }
        return list
    }

    var body: some View {
        List {
            Section {
                BaseChip()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "All", on: category == nil) { category = nil }
                        ForEach(categories, id: \.self) { c in
                            Chip(text: Cat.label(c), symbol: Cat.symbol(c), on: category == c) {
                                category = category == c ? nil : c
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("free", "Free"), ("rainy-day", "Rainy day"), ("kids", "Kids"), ("dogs", "Dogs"), ("wheelchair", "Step-free"), ("allstar", "Allstar EV")], id: \.0) { t in
                            Chip(text: t.1, on: tag == t.0) { tag = tag == t.0 ? nil : t.0 }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Section {
                ForEach(filtered) { p in
                    NavigationLink(value: p) { PlaceRow(place: p) }
                        .listRowBackground(theme.t.surface)
                }
                if filtered.isEmpty {
                    Text("Nothing matches.").foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                        .listRowBackground(theme.t.surface)
                }
            } header: {
                HStack {
                    SectionHead("\(filtered.count) places")
                    Spacer()
                    Button(sortNear ? "Nearest first" : "A–Z") { sortNear.toggle() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .themedList()
        .searchable(text: $search, prompt: "Search places")
        .navigationTitle("Explore")
        .explorerDestinations()
    }
}

struct PlaceRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var base: BaseStore
    let place: Place
    var body: some View {
        HStack(spacing: 12) {
            CatIcon(symbol: Cat.symbol(place.category), color: Cat.color(place.category))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                Text(place.summary).font(.caption).lineLimit(2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                HStack(spacing: 6) {
                    Text(place.town)
                    Text("· \(distanceText(base.distance(to: place.coordinate, location)))")
                }
                .font(.caption2).foregroundStyle(theme.t.primary.opacity(0.9))
            }
        }
        .padding(.vertical, 2)
    }
}

struct PlaceDetailView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var location: LocationModel
    let place: Place
    @State private var planning: PlanTarget?
    @State private var fullMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CatIcon(symbol: Cat.symbol(place.category), color: Cat.color(place.category), size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).font(.title2.weight(.bold)).foregroundStyle(theme.t.onBackground)
                        Text("\(Cat.label(place.category)) · \(place.town)").font(.subheadline).foregroundStyle(theme.t.primary)
                    }
                }
                Text(place.summary).font(.headline.weight(.regular)).foregroundStyle(theme.t.onSurfaceVariant)

                PhotoGallery(owner: place.id)

                OfflineMapView(places: [place], accent: UIColor(theme.t.primary),
                               focus: MapFocus(center: place.coordinate, meters: 900))
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) { ExpandMapButton { fullMap = true } }
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            router.showOnMap([CLLocationCoordinate2DBox(place.coordinate)])
                        } label: {
                            Label("Open map", systemImage: "map").font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(8)
                    }

                PlanButton { planning = PlanTarget(kind: .place, refID: place.id, title: place.name) }

                if place.isPhoto { photoCard }

                Card {
                    Text(place.description).font(.body).foregroundStyle(theme.t.onBackground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if let d = location.distance(to: place.coordinate) {
                            InfoRow(symbol: "location", title: "From you", value: distanceText(d))
                        }
                        InfoRow(symbol: "clock", title: "Opening", value: place.openingHours)
                        InfoRow(symbol: "sterlingsign.circle", title: "Price", value: place.price)
                        InfoRow(symbol: "hourglass", title: "Typical visit", value: place.durationMin.map { $0 >= 60 ? String(format: "%.1f hours", Double($0) / 60) : "\($0) min" })
                        InfoRow(symbol: "lightbulb", title: "Tip", value: place.tips)
                        InfoRow(symbol: "pawprint", title: "Dogs", value: place.dogs)
                        InfoRow(symbol: "figure.roll", title: "Access", value: place.accessibility)
                        InfoRow(symbol: "mappin.and.ellipse", title: "Address", value: [place.address, place.postcode].compactMap { $0 }.joined(separator: ", "))
                    }
                }
                Card {
                    LinksBlock(website: place.website, phone: place.phone,
                               directions: (place.lat, place.lon, place.name), sources: place.sources, verified: place.verified)
                }
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planning) { AddToPlanSheet(target: $0) }
        .fullScreenCover(isPresented: $fullMap) {
            FullScreenMap(title: place.name, places: [place], focus: MapFocus(center: place.coordinate, meters: 900))
        }
    }

    private var photoCard: some View {
        Card {
            Label(place.category == "hide" ? "Wildlife hide" : "Photography", systemImage: place.category == "hide" ? "bird" : "camera")
                .cardTitle(theme)
            if !place.subjects.isEmpty {
                Text(place.subjects.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(theme.t.primary)
            }
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(symbol: "sun.haze", title: "Best time & light", value: place.bestTime)
                InfoRow(symbol: "water.waves", title: "Tide", value: place.tide)
                InfoRow(symbol: "bird", title: "Wildlife", value: place.wildlife)
                InfoRow(symbol: "binoculars", title: "Hides & access", value: place.facilities)
            }
            let sun = Sun.times(Date(), place.coordinate)
            HStack(spacing: 14) {
                if let r = sun.sunrise, let az = sun.sunriseAzimuth { Label("\(Day.time(r)) \(Sun.compass(az))", systemImage: "sunrise") }
                if let s = sun.sunset, let az = sun.sunsetAzimuth { Label("\(Day.time(s)) \(Sun.compass(az))", systemImage: "sunset") }
            }
            .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
            if place.tide != nil, let tides = store.tides {
                let up = tides.upcoming(from: Date(), count: 3)
                if !up.isEmpty {
                    Text("Next: " + up.map { "\($0.high ? "high" : "low") \(Day.format($0.time, "EEE HH:mm"))" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
                }
            }
        }
    }
}

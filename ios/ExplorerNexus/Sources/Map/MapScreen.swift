import MapKit
import SwiftUI
import UIKit

/// The offline map tab: every place as a pin (filter by category), a walk route when one
/// was sent here, today's events, and your position.
struct MapScreen: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var location: LocationModel
    @State private var shown: Set<String> = MapScreen.sightseeing
    @State private var showEvents = false
    @State private var sheet: MapSheet?

    static let sightseeing: Set<String> = ["sight", "history", "museum", "church", "beach", "nature", "viewpoint", "family", "photo", "hide"]

    private var places: [Place] { store.places.filter { shown.contains($0.category) } }
    private var events: [EventItem] {
        showEvents ? EventCalendar.on(Date(), events: store.events).map(\.event).filter { $0.coordinate != nil } : []
    }

    var body: some View {
        ZStack(alignment: .top) {
            OfflineMapView(places: places, events: events, walk: router.mapWalk,
                           routeColor: UIColor(theme.t.primary), accent: UIColor(theme.t.primary),
                           focus: router.mapFocus) { ref in
                switch ref {
                case .place(let p): sheet = MapSheet(place: p)
                case .event(let e): sheet = MapSheet(event: e)
                case .waypoint: break
                }
            }
            .ignoresSafeArea(edges: .top)
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Menu {
                            Button("Sightseeing") { shown = MapScreen.sightseeing }
                            Button("Food & drink") { shown = ["pub", "brewery", "vineyard", "cafe", "restaurant", "food", "shop", "market"] }
                            Button("Everything") { shown = Set(Cat.order) }
                            Button("Nothing") { shown = [] }
                        } label: { ChipLabel(text: "Show", symbol: "slider.horizontal.3", on: true) }
                        Chip(text: "Today's events", symbol: "party.popper", on: showEvents) { showEvents.toggle() }
                        ForEach(Cat.order, id: \.self) { c in
                            Chip(text: Cat.label(c), symbol: Cat.symbol(c), on: shown.contains(c)) {
                                if shown.contains(c) { shown.remove(c) } else { shown.insert(c) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if let w = router.mapWalk {
                    HStack {
                        Label(w.title, systemImage: "figure.walk").font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button { router.mapWalk = nil } label: { Image(systemName: "xmark.circle.fill") }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 10) {
                Button {
                    if let l = location.location { router.focus(l.coordinate, meters: 800) } else { location.start() }
                } label: {
                    Image(systemName: "location.fill").font(.headline).frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Button { router.focus(Sun.birchington, meters: 4000) } label: {
                    Image(systemName: "house.fill").font(.headline).frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(14)
        }
        .overlay(alignment: .bottomLeading) {
            Text("© OpenStreetMap contributors").font(.system(size: 9)).padding(4)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.black)
                .padding(6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { s in
            NavigationStack {
                Group {
                    if let p = s.place { PlaceDetailView(place: p) }
                    else if let e = s.event { EventDetailView(event: e) }
                }
                .explorerDestinations()
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct MapSheet: Identifiable {
    var place: Place? = nil
    var event: EventItem? = nil
    var id: String { place?.id ?? event?.id ?? "" }
}

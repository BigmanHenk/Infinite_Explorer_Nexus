import CoreLocation
import SwiftUI
import UIKit

/// One map search hit: a place, event, walk, town or street (offline street index).
struct SearchHit: Identifiable, Hashable {
    enum Kind: Hashable { case place(Place), event(EventItem), walk(Walk), town, street }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let symbol: String

    static func == (a: SearchHit, b: SearchHit) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Street: Hashable {
    let name: String
    let town: String
    let lat: Double
    let lon: Double
}

extension Store {
    /// The offline street index (OpenStreetMap names), read once on first search.
    var streets: [Street] {
        if let s = Store.streetCache { return s }
        var out: [Street] = []
        if let path = Bundle.main.path(forResource: "explorer", ofType: "sqlite", inDirectory: "Content"),
           let db = SQLiteDB(path: path) {
            db.query("SELECT name, town, lat, lon FROM streets") { r in
                out.append(Street(name: r.text(0), town: r.text(1), lat: r.double(2) ?? 0, lon: r.double(3) ?? 0))
            }
        }
        Store.streetCache = out
        return out
    }
    private static var streetCache: [Street]?

    func search(_ text: String, limit: Int = 40) -> [SearchHit] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        var hits: [SearchHit] = []
        for p in places where p.name.lowercased().contains(q) || p.town.lowercased().contains(q) && q.count > 3 {
            hits.append(SearchHit(id: "p:" + p.id, kind: .place(p), title: p.name, subtitle: "\(Cat.label(p.category)) · \(p.town)",
                                  coordinate: p.coordinate, symbol: Cat.symbol(p.category)))
        }
        for w in walks where w.title.lowercased().contains(q) {
            if let s = w.points.first {
                hits.append(SearchHit(id: "w:" + w.id, kind: .walk(w), title: w.title, subtitle: String(format: "Walk · %.1f km", w.distanceKm),
                                      coordinate: s.coordinate, symbol: "figure.walk"))
            }
        }
        for e in events where e.title.lowercased().contains(q) || e.venue.lowercased().contains(q) {
            if let c = e.coordinate {
                hits.append(SearchHit(id: "e:" + e.id, kind: .event(e), title: e.title, subtitle: "\(EventCalendar.dateText(e)) · \(e.venue)",
                                      coordinate: c, symbol: Cat.eventSymbol(e.category)))
            }
        }
        for t in BaseStore.towns where t.name.lowercased().contains(q) {
            hits.append(SearchHit(id: "t:" + t.name, kind: .town, title: t.name, subtitle: "Town",
                                  coordinate: .init(latitude: t.lat, longitude: t.lon), symbol: "building.2"))
        }
        for s in streets where s.name.lowercased().contains(q) {
            hits.append(SearchHit(id: "s:\(s.name)|\(s.town)", kind: .street, title: s.name, subtitle: "Street · \(s.town)",
                                  coordinate: .init(latitude: s.lat, longitude: s.lon), symbol: "road.lanes"))
            if hits.count > limit * 2 { break }
        }
        // names that start with the search first
        return Array(hits.sorted { a, b in
            let sa = a.title.lowercased().hasPrefix(q), sb = b.title.lowercased().hasPrefix(q)
            return sa != sb ? sa : a.title.count < b.title.count
        }.prefix(limit))
    }
}

/// Search field + result list over the map.
struct MapSearchBar: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @Binding var text: String
    let onPick: (SearchHit) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                TextField("Search places, walks, streets…", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button { text = ""; focused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            let hits = focused || !text.isEmpty ? store.search(text) : []
            if !hits.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { h in
                            Button {
                                focused = false
                                onPick(h)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: h.symbol).foregroundStyle(theme.t.primary).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground).lineLimit(1)
                                        Text(h.subtitle).font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75)).lineLimit(1)
                                    }
                                    Spacer()
                                    let est = TravelEstimate(metres: base.distance(to: h.coordinate, location))
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(distanceText(est.metres)).font(.caption2.weight(.semibold))
                                        Text("🚶 \(TravelEstimate.text(est.walkMin))").font(.caption2)
                                    }
                                    .foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(theme.t.outline.opacity(0.4))
                        }
                    }
                }
                .frame(maxHeight: 320)
                .background(theme.t.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 4)
            }
        }
    }
}

/// The card at the bottom of the map for what was picked: travel times, details, set as base.
struct PickedCard: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    let hit: SearchHit
    let onDetails: () -> Void
    let onClose: () -> Void

    var body: some View {
        let est = TravelEstimate(metres: base.distance(to: hit.coordinate, location))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: hit.symbol).foregroundStyle(theme.t.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).font(.headline).foregroundStyle(theme.t.onBackground)
                    Text(hit.subtitle).font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75))
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
            }
            HStack(spacing: 14) {
                Text(distanceText(est.metres)).font(.caption.weight(.semibold))
                Label(TravelEstimate.text(est.walkMin), systemImage: "figure.walk")
                Label(TravelEstimate.text(est.bikeMin), systemImage: "bicycle")
                Label(TravelEstimate.text(est.carMin), systemImage: "car.fill")
            }
            .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
            Text("from \(base.mode == .gps && location.location != nil ? "where you are" : base.name)")
                .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
            HStack(spacing: 10) {
                switch hit.kind {
                case .place, .event, .walk:
                    Button("Details", action: onDetails).buttonStyle(.borderedProminent)
                default:
                    EmptyView()
                }
                Button("Make this my base") { base.set(hit.title, hit.coordinate) }.buttonStyle(.bordered)
                Button {
                    var s = "http://maps.apple.com/?daddr=\(hit.coordinate.latitude),\(hit.coordinate.longitude)&dirflg=w"
                    if base.mode == .fixed || location.location == nil { s += "&saddr=\(base.lat),\(base.lon)" }
                    if let u = URL(string: s) { UIApplication.shared.open(u) }
                } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond") }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(theme.t.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}

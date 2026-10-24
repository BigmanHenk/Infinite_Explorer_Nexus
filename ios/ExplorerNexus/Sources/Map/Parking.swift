import CoreLocation
import SwiftUI

/// A public car park (OpenStreetMap).
struct CarPark: Hashable {
    let name: String
    let lat: Double
    let lon: Double
    let fee: String?
    let capacity: Int?
    let disabled: Int?
    let maxstay: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

extension Store {
    var carParks: [CarPark] {
        if let c = Store.parkCache { return c }
        var out: [CarPark] = []
        if let path = Bundle.main.path(forResource: "explorer", ofType: "sqlite", inDirectory: "Content"),
           let db = SQLiteDB(path: path) {
            db.query("SELECT name, lat, lon, fee, capacity, disabled, maxstay FROM parking") { r in
                out.append(CarPark(name: r.text(0), lat: r.double(1) ?? 0, lon: r.double(2) ?? 0, fee: r.string(3),
                                   capacity: r.int(4), disabled: r.int(5), maxstay: r.string(6)))
            }
        }
        Store.parkCache = out
        return out
    }
    private static var parkCache: [CarPark]?

    /// The closest car parks to a destination (within ~1.5 km), nearest first.
    func parking(near c: CLLocationCoordinate2D, count: Int = 3) -> [(CarPark, CLLocationDistance)] {
        carParks.map { ($0, $0.coordinate.distance(to: c)) }
            .filter { $0.1 <= 1500 }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map { $0 }
    }
}

/// "Where to park": the nearest car parks, walking time to the destination, and a button that
/// sends the car park to Google Maps, Waze or Apple Maps for driving.
struct ParkingCard: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    let to: CLLocationCoordinate2D

    var body: some View {
        let parks = store.parking(near: to)
        if !parks.isEmpty {
            Card {
                Label("Parking nearby", systemImage: "parkingsign.circle.fill").cardTitle(theme)
                ForEach(Array(parks.enumerated()), id: \.offset) { _, item in
                    let (p, d) = item
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "p.square.fill").font(.title2).foregroundStyle(Color(hex: 0x2E6FD6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                            Text("🚶 \(TravelEstimate.text(TravelEstimate(metres: d).walkMin)) to here · \(distanceText(d))")
                                .font(.caption).foregroundStyle(theme.t.primary)
                            let info = [p.fee, p.capacity.map { "\($0) spaces" }, p.disabled.map { "\($0) disabled" },
                                        p.maxstay.map { "max \($0)" }].compactMap { $0 }
                            if !info.isEmpty {
                                Text(info.joined(separator: " · ")).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75))
                            }
                        }
                        Spacer()
                        NavigateMenu(to: p.coordinate, name: p.name) {
                            Label("Drive", systemImage: "car.fill").font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text("Car parks from OpenStreetMap; charges and opening times can change.")
                    .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
            }
        }
    }
}

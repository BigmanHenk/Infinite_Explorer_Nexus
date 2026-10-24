import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// "My base": the point distances are measured from (GPS, a town, or a spot picked on the map)
/// and the search radius that Explore, Map, What's on, Walks, Photo spots and Suggest keep to.
@MainActor
final class BaseStore: ObservableObject {
    enum Mode: String { case gps, fixed }

    @Published var mode: Mode { didSet { save() } }
    @Published var name: String { didSet { save() } }
    @Published var lat: Double { didSet { save() } }
    @Published var lon: Double { didSet { save() } }
    /// 0 = any distance.
    @Published var radiusKm: Double { didSet { save() } }
    /// Home, set once; one tap makes it the base.
    @Published var homeLat: Double? { didSet { save() } }
    @Published var homeLon: Double? { didSet { save() } }
    var home: CLLocationCoordinate2D? {
        guard let a = homeLat, let b = homeLon else { return nil }
        return .init(latitude: a, longitude: b)
    }
    var isHome: Bool { mode == .fixed && name == "Home" }

    struct Town: Hashable { let name: String; let lat: Double; let lon: Double }

    static let towns: [Town] = [
        Town(name: "Birchington-on-Sea", lat: 51.3770, lon: 1.3050), Town(name: "Minnis Bay", lat: 51.3810, lon: 1.2850), Town(name: "Westgate-on-Sea", lat: 51.3810, lon: 1.3380),
        Town(name: "Margate", lat: 51.3890, lon: 1.3830), Town(name: "Cliftonville", lat: 51.3920, lon: 1.4080), Town(name: "Broadstairs", lat: 51.3590, lon: 1.4390),
        Town(name: "Ramsgate", lat: 51.3340, lon: 1.4170), Town(name: "Minster", lat: 51.3300, lon: 1.3160), Town(name: "St Nicholas-at-Wade", lat: 51.3530, lon: 1.2510),
        Town(name: "Reculver", lat: 51.3790, lon: 1.1990), Town(name: "Herne Bay", lat: 51.3720, lon: 1.1270), Town(name: "Sandwich", lat: 51.2740, lon: 1.3400),
        Town(name: "Canterbury", lat: 51.2800, lon: 1.0790),
    ]
    static let radii: [Double] = [1, 2, 3, 5, 8, 10, 15, 20, 30, 50, 0]

    init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: "base_mode") ?? "") ?? .fixed
        name = d.string(forKey: "base_name") ?? "Birchington-on-Sea"
        lat = d.object(forKey: "base_lat") as? Double ?? Sun.birchington.latitude
        lon = d.object(forKey: "base_lon") as? Double ?? Sun.birchington.longitude
        radiusKm = d.object(forKey: "base_radius") as? Double ?? 0
        homeLat = d.object(forKey: "home_lat") as? Double
        homeLon = d.object(forKey: "home_lon") as? Double
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: "base_mode")
        d.set(name, forKey: "base_name")
        d.set(lat, forKey: "base_lat")
        d.set(lon, forKey: "base_lon")
        d.set(radiusKm, forKey: "base_radius")
        d.set(homeLat, forKey: "home_lat")
        d.set(homeLon, forKey: "home_lon")
    }

    func setHome(_ c: CLLocationCoordinate2D) {
        homeLat = c.latitude
        homeLon = c.longitude
    }

    func useHome() {
        if let h = home { set("Home", h) }
    }

    var fixed: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// Where distances are measured from right now.
    func origin(_ location: LocationModel) -> CLLocationCoordinate2D {
        if mode == .gps, let l = location.location { return l.coordinate }
        return fixed
    }

    func distance(to c: CLLocationCoordinate2D, _ location: LocationModel) -> CLLocationDistance {
        origin(location).distance(to: c)
    }

    func within(_ c: CLLocationCoordinate2D?, _ location: LocationModel) -> Bool {
        guard radiusKm > 0, let c else { return true }
        return distance(to: c, location) <= radiusKm * 1000
    }

    func set(_ name: String, _ c: CLLocationCoordinate2D) {
        mode = .fixed
        self.name = name
        lat = c.latitude
        lon = c.longitude
    }

    var radiusText: String {
        if radiusKm == 0 { return "any distance" }
        if radiusKm < 1.6 { return "\(Int(radiusKm)) km" }
        return String(format: "%.0f km (%.0f mi)", radiusKm, radiusKm / 1.609)
    }

    func label(_ location: LocationModel) -> String {
        var place = name == "Home" ? "🏠 Home" : name
        if mode == .gps { place = location.location == nil ? "My position (waiting…)" : "My position" }
        if radiusKm == 0 { return place }
        return "\(place) · \(Int(radiusKm)) km"
    }
}

/// The chip at the top of Explore, Map, What's on, Walks and Photo spots.
struct BaseChip: View {
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            ChipLabel(text: base.label(location), symbol: base.mode == .gps ? "location.fill" : "mappin.circle.fill",
                      on: base.radiusKm > 0)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { BaseSheet() }
    }
}

struct BaseSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationModel
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var pickingHome = false

    private var count: Int {
        store.places.filter { base.within($0.coordinate, location) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if base.home != nil {
                        Button { base.useHome() } label: {
                            HStack {
                                Label("Home", systemImage: "house.fill")
                                Spacer()
                                if base.isHome { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Menu {
                        if let l = location.location {
                            Button("Where I am now (GPS)") { base.setHome(l.coordinate); base.useHome() }
                        }
                        if base.mode == .fixed && !base.isHome {
                            Button("The current base (\(base.name))") { base.setHome(base.fixed); base.useHome() }
                        }
                        Button("Pick on the map…") { pickingHome = true }
                        if base.home != nil {
                            Button("Forget home", role: .destructive) { base.homeLat = nil; base.homeLon = nil }
                        }
                    } label: {
                        Label(base.home == nil ? "Set my home…" : "Change home…", systemImage: "house")
                    }
                } header: { SectionHead("Home") }
                .listRowBackground(theme.t.surface)

                Section {
                    Button {
                        base.mode = .gps
                        location.start()
                    } label: {
                        HStack {
                            Label("Follow my position (GPS)", systemImage: "location.fill")
                            Spacer()
                            if base.mode == .gps { Image(systemName: "checkmark") }
                        }
                    }
                    if base.mode == .gps && location.location == nil {
                        Text("Waiting for GPS - until then distances are from \(base.name).").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { picking = true } label: { Label("Pick a spot on the map (e.g. where you are staying)", systemImage: "hand.tap") }
                    if base.mode == .gps, let l = location.location {
                        Button { base.set("My spot", l.coordinate) } label: { Label("Fix my base here (stop following GPS)", systemImage: "pin") }
                    }
                } header: { SectionHead("Base") }
                .listRowBackground(theme.t.surface)

                Section {
                    ForEach(BaseStore.towns, id: \.self) { t in
                        Button { base.set(t.name, .init(latitude: t.lat, longitude: t.lon)) } label: {
                            HStack {
                                Text(t.name).foregroundStyle(theme.t.onBackground)
                                Spacer()
                                if base.mode == .fixed && base.name == t.name { Image(systemName: "checkmark").foregroundStyle(theme.t.primary) }
                            }
                        }
                    }
                    if base.mode == .fixed && !BaseStore.towns.contains(where: { $0.name == base.name }) {
                        HStack { Text(base.name); Spacer(); Image(systemName: "checkmark").foregroundStyle(theme.t.primary) }
                    }
                } header: { SectionHead("Or a town") }
                .listRowBackground(theme.t.surface)

                Section {
                    let idx = Binding<Double>(
                        get: { Double(BaseStore.radii.firstIndex(of: base.radiusKm) ?? (BaseStore.radii.count - 1)) },
                        set: { base.radiusKm = BaseStore.radii[min(max(Int($0.rounded()), 0), BaseStore.radii.count - 1)] })
                    HStack {
                        Text("Within").foregroundStyle(theme.t.onBackground)
                        Spacer()
                        Text(base.radiusText).font(.headline).foregroundStyle(theme.t.primary)
                    }
                    Slider(value: idx, in: 0...Double(BaseStore.radii.count - 1), step: 1)
                    Text("\(count) of \(store.places.count) places are inside this radius.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { SectionHead("Search radius") }
                .listRowBackground(theme.t.surface)
            }
            .themedList()
            .navigationTitle("My base & radius")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $picking) { PickSpotView() }
            .sheet(isPresented: $pickingHome) { PickSpotView(forHome: true) }
        }
        .presentationDetents([.large])
    }
}

/// Move the map under the cross, then "Use this spot".
struct PickSpotView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var base: BaseStore
    @Environment(\.dismiss) private var dismiss
    var forHome = false
    @State private var centre = Sun.birchington
    @State private var label = "My base"

    var body: some View {
        NavigationStack {
            ZStack {
                CentreTrackingMap(start: base.home ?? base.fixed, centre: $centre)
                    .ignoresSafeArea(edges: .bottom)
                Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(.red)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !forHome {
                        TextField("Name (e.g. our cottage)", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        if forHome {
                            base.setHome(centre)
                            base.useHome()
                        } else {
                            base.set(label.trimmingCharacters(in: .whitespaces).isEmpty ? "My base" : label, centre)
                        }
                        dismiss()
                    } label: {
                        Text(forHome ? "This is my home" : "Use this spot").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(theme.t.onPrimary).background(theme.t.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(theme.t.surface)
            }
            .navigationTitle(forHome ? "Move the map to your home" : "Move the map to your base")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Offline map that reports its centre while you move it.
struct CentreTrackingMap: UIViewRepresentable {
    let start: CLLocationCoordinate2D
    @Binding var centre: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.addOverlay(OfflineTileOverlay.shared, level: .aboveLabels)
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        map.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: OfflineTileOverlay.region), animated: false)
        map.setRegion(MKCoordinateRegion(center: start, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: CentreTrackingMap
        init(_ p: CentreTrackingMap) { parent = p }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let c = mapView.centerCoordinate
            DispatchQueue.main.async { self.parent.centre = c }
        }
    }
}

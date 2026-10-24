import CoreLocation
import SwiftUI

@main
struct ExplorerApp: App {
    @StateObject private var theme = ThemeStore()
    @StateObject private var planner = PlannerStore()
    @StateObject private var location = LocationModel()
    @StateObject private var weather = WeatherStore()
    @StateObject private var base = BaseStore()
    @StateObject private var interests = InterestStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(planner)
                .environmentObject(location)
                .environmentObject(weather)
                .environmentObject(base)
                .environmentObject(interests)
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(theme.t.primary)
        }
    }
}

enum Tab: Hashable { case today, places, map, walks, planner }

/// Lets any screen jump to another tab (e.g. "Show on map").
@MainActor
final class Router: ObservableObject {
    @Published var tab: Tab = .today
    @Published var mapFocus: MapFocus?
    @Published var mapWalk: Walk?

    private var nonce = 0

    func showOnMap(_ c: [CLLocationCoordinate2DBox], walk: Walk? = nil, meters: Double = 1200) {
        mapWalk = walk
        nonce += 1
        if c.count == 1 {
            mapFocus = MapFocus(center: c[0].c, meters: meters, nonce: nonce)
        } else {
            mapFocus = .fit(c.map(\.c), nonce: nonce)
        }
        tab = .map
    }

    /// Move the map tab's camera without switching tab.
    func focus(_ c: CLLocationCoordinate2D, meters: Double) {
        nonce += 1
        mapFocus = MapFocus(center: c, meters: meters, nonce: nonce)
    }
}

struct RootView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var planner: PlannerStore
    @StateObject private var router = Router()
    @State private var splash = true
    @State private var incoming: IncomingPlan?
    @State private var badLink = false

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(Tab.today)
                NavigationStack { PlacesView() }
                    .tabItem { Label("Explore", systemImage: "binoculars") }.tag(Tab.places)
                NavigationStack { MapScreen() }
                    .tabItem { Label("Map", systemImage: "map") }.tag(Tab.map)
                NavigationStack { WalksView() }
                    .tabItem { Label("Walks", systemImage: "figure.walk") }.tag(Tab.walks)
                NavigationStack { PlannerView() }
                    .tabItem { Label("My week", systemImage: "calendar") }.tag(Tab.planner)
            }
            .environmentObject(router)
            if splash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .onOpenURL { url in
            if let items = PlanShare.read(url) { incoming = IncomingPlan(items: items) } else { badLink = true }
        }
        .sheet(item: $incoming) { p in ImportPlanSheet(items: p.items) { replace in
            planner.importItems(p.items, replaceDays: replace)
            router.tab = .planner
        } }
        .alert("That plan could not be read.", isPresented: $badLink) { Button("OK") {} }
        .task { await weather.refresh() }
        .onAppear {
            location.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut(duration: 0.4)) { splash = false } }
        }
    }
}

struct IncomingPlan: Identifiable {
    let id = UUID()
    let items: [PlanItem]
}

/// Asked when a plan arrives (QR code, link, .explorerplan file).
struct ImportPlanSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    let items: [PlanItem]
    let apply: (Bool) -> Void
    var body: some View {
        let days = Array(Set(items.map(\.day))).sorted()
        NavigationStack {
            List {
                Section {
                    Text("\(items.count) item\(items.count == 1 ? "" : "s") on \(days.count) day\(days.count == 1 ? "" : "s")")
                        .font(.headline)
                }
                ForEach(days, id: \.self) { d in
                    Section(Day.date(d).map { Day.format($0, "EEEE d MMMM") } ?? d) {
                        ForEach(items.filter { $0.day == d }) { it in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.title).font(.subheadline.weight(.semibold))
                                Text([it.time ?? it.slot.label, it.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("Add to my plan") { apply(false); dismiss() }
                    Button("Replace my plan on these days", role: .destructive) { apply(true); dismiss() }
                }
            }
            .themedList()
            .navigationTitle("Plan received")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct SplashView: View {
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        ZStack {
            theme.t.background.ignoresSafeArea()
            VStack(spacing: 18) {
                ExplorerMark(color: theme.t.primary).frame(width: 150, height: 150)
                VStack(spacing: 4) {
                    Text("INFINITE EXPLORER").font(.title3.weight(.bold)).tracking(4).foregroundStyle(theme.t.onBackground)
                    Text("NEXUS").font(.caption.weight(.semibold)).tracking(8).foregroundStyle(theme.t.primary)
                }
                Text("Birchington-on-Sea · Isle of Thanet").font(.footnote).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
            }
        }
    }
}

/// The app's mark: a Nexus hexagon with chem-arms and a lighthouse over waves.
struct ExplorerMark: View {
    var color: Color = .white
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2.8
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let sw = max(r * 0.07, 1.4)
            var hex = Path()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 - .pi / 2
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
            }
            hex.closeSubpath()
            ctx.stroke(hex, with: .color(color), style: StrokeStyle(lineWidth: sw, lineJoin: .round))
            // chem-arms from three alternate corners
            for i in [1, 3, 5] {
                let a = CGFloat(i) * .pi / 3 - .pi / 2
                let p0 = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                let p1 = CGPoint(x: c.x + r * 1.32 * cos(a), y: c.y + r * 1.32 * sin(a))
                var arm = Path(); arm.move(to: p0); arm.addLine(to: p1)
                ctx.stroke(arm, with: .color(color), style: StrokeStyle(lineWidth: sw, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: p1.x - sw * 1.6, y: p1.y - sw * 1.6, width: sw * 3.2, height: sw * 3.2)), with: .color(color))
            }
            // lighthouse
            let base = c.y + r * 0.38
            let top = c.y - r * 0.42
            var tower = Path()
            tower.move(to: CGPoint(x: c.x - r * 0.17, y: base))
            tower.addLine(to: CGPoint(x: c.x - r * 0.10, y: top))
            tower.addLine(to: CGPoint(x: c.x + r * 0.10, y: top))
            tower.addLine(to: CGPoint(x: c.x + r * 0.17, y: base))
            tower.closeSubpath()
            ctx.stroke(tower, with: .color(color), style: StrokeStyle(lineWidth: sw * 0.9, lineJoin: .round))
            var lamp = Path()
            lamp.addRect(CGRect(x: c.x - r * 0.08, y: top - r * 0.16, width: r * 0.16, height: r * 0.16))
            ctx.fill(lamp, with: .color(color))
            var roof = Path()
            roof.move(to: CGPoint(x: c.x - r * 0.12, y: top - r * 0.16))
            roof.addLine(to: CGPoint(x: c.x, y: top - r * 0.28))
            roof.addLine(to: CGPoint(x: c.x + r * 0.12, y: top - r * 0.16))
            ctx.stroke(roof, with: .color(color), style: StrokeStyle(lineWidth: sw * 0.9, lineJoin: .round))
            for side in [-1.0, 1.0] {
                var beam = Path()
                beam.move(to: CGPoint(x: c.x + side * r * 0.12, y: top - r * 0.08))
                beam.addLine(to: CGPoint(x: c.x + side * r * 0.52, y: top - r * 0.2))
                ctx.stroke(beam, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: sw * 0.6, lineCap: .round))
            }
            // waves
            for k in 0..<2 {
                var wave = Path()
                let y = base + r * (0.12 + CGFloat(k) * 0.14)
                let x0 = c.x - r * 0.5, x1 = c.x + r * 0.5
                wave.move(to: CGPoint(x: x0, y: y))
                let n = 4
                let w = (x1 - x0) / CGFloat(n)
                for j in 0..<n {
                    let xa = x0 + CGFloat(j) * w
                    wave.addQuadCurve(to: CGPoint(x: xa + w, y: y), control: CGPoint(x: xa + w / 2, y: y - r * 0.09))
                }
                ctx.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: sw * 0.8, lineCap: .round))
            }
        }
    }
}

/// Hashable wrapper so coordinates can travel through the router.
struct CLLocationCoordinate2DBox: Hashable {
    let lat: Double
    let lon: Double
    var c: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
}

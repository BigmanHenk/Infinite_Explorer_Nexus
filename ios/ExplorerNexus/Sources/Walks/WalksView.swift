import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct WalksView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationModel
    @State private var filter = 0     // 0 all, 1 short, 2 circular, 3 step-free

    private var list: [Walk] {
        store.walks.filter { w in
            switch filter {
            case 1: return w.distanceKm <= 4
            case 2: return w.circular
            case 3: return (w.accessibility ?? "").lowercased().contains("wheelchair") || (w.accessibility ?? "").lowercased().contains("buggy")
            default: return true
            }
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "All", on: filter == 0) { filter = 0 }
                        Chip(text: "Up to 4 km", on: filter == 1) { filter = 1 }
                        Chip(text: "Circular", on: filter == 2) { filter = 2 }
                        Chip(text: "Step-free", symbol: "figure.roll", on: filter == 3) { filter = 3 }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Section {
                ForEach(list) { w in
                    NavigationLink(value: w) { WalkRow(walk: w) }
                        .listRowBackground(theme.t.surface)
                }
            } header: { SectionHead("\(list.count) walks · maps work offline") }
        }
        .themedList()
        .navigationTitle("Walks")
        .explorerDestinations()
    }
}

struct WalkRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var location: LocationModel
    let walk: Walk
    var body: some View {
        HStack(spacing: 12) {
            RouteThumb(route: walk.route.isEmpty ? walk.points.map(\.coordinate) : walk.route, color: theme.t.primary)
                .frame(width: 54, height: 54)
                .background(theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(walk.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                HStack(spacing: 6) {
                    Text(String(format: "%.1f km", walk.distanceKm))
                    if let d = walk.durationMin { Text("· \(d / 60 > 0 ? "\(d / 60) h " : "")\(d % 60 > 0 ? "\(d % 60) min" : "")") }
                    Text("· \(walk.difficulty.capitalized)")
                    Text(walk.circular ? "· circular" : "· one way")
                }
                .font(.caption).foregroundStyle(theme.t.primary)
                Text(walk.summary).font(.caption).lineLimit(2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                if walk.tideWarning != nil {
                    Label("Check the tide", systemImage: "water.waves").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The route's shape as a tiny line drawing.
struct RouteThumb: View {
    let route: [CLLocationCoordinate2D]
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            guard route.count > 1 else { return }
            let pts = route.map { MKMapPoint($0) }
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            let span = max(maxX - minX, maxY - minY, 1)
            let pad: CGFloat = 7
            let s = (min(size.width, size.height) - 2 * pad) / span
            let ox = (size.width - (maxX - minX) * s) / 2
            let oy = (size.height - (maxY - minY) * s) / 2
            var p = Path()
            for (i, m) in pts.enumerated() {
                let q = CGPoint(x: ox + (m.x - minX) * s, y: oy + (m.y - minY) * s)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            let a = pts[0]
            ctx.fill(Path(ellipseIn: CGRect(x: ox + (a.x - minX) * s - 3, y: oy + (a.y - minY) * s - 3, width: 6, height: 6)), with: .color(.green))
        }
    }
}

struct WalkDetailView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationModel
    let walk: Walk
    @State private var planning: PlanTarget?
    @State private var following = false

    private var coords: [CLLocationCoordinate2D] { walk.route.isEmpty ? walk.points.map(\.coordinate) : walk.route }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(walk.title).font(.title2.weight(.bold)).foregroundStyle(theme.t.onBackground)
                HStack(spacing: 14) {
                    stat("ruler", String(format: "%.1f km", walk.distanceKm))
                    if let d = walk.durationMin { stat("clock", "\(d) min") }
                    stat("chart.bar", walk.difficulty.capitalized)
                    stat(walk.circular ? "arrow.triangle.2.circlepath" : "arrow.right", walk.circular ? "Circular" : "One way")
                }
                OfflineMapView(walk: walk, routeColor: UIColor(theme.t.primary), accent: UIColor(theme.t.primary),
                               focus: MapFocus.fit(coords))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                PhotoGallery(owner: "walk:" + walk.id, height: 200)
                if let t = walk.tideWarning { tideCard(t) }
                HStack(spacing: 10) {
                    Button { following = true } label: {
                        Label("Start walk", systemImage: "figure.walk.motion")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(theme.t.onPrimary)
                            .background(Color(hex: 0x3E9B4F), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    PlanButton { planning = PlanTarget(kind: .walk, refID: walk.id, title: walk.title) }
                }
                Card {
                    Text(walk.description).foregroundStyle(theme.t.onBackground)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Card {
                    SectionHead("The route")
                    ForEach(Array(walk.points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(theme.t.onPrimary)
                                .frame(width: 22, height: 22).background(theme.t.primary, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                                if let n = p.note { Text(n).font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(symbol: "flag", title: "Start", value: walk.start)
                        InfoRow(symbol: "road.lanes", title: "Surface", value: walk.surface)
                        InfoRow(symbol: "toilet", title: "Toilets", value: walk.toilets)
                        InfoRow(symbol: "cup.and.saucer", title: "Refreshments", value: walk.refreshments)
                        InfoRow(symbol: "parkingsign", title: "Parking", value: walk.parking)
                        InfoRow(symbol: "tram", title: "Train & bus", value: walk.publicTransport)
                        InfoRow(symbol: "pawprint", title: "Dogs", value: walk.dogs)
                        InfoRow(symbol: "figure.roll", title: "Access", value: walk.accessibility)
                    }
                }
                Card {
                    LinksBlock(website: nil, phone: nil,
                               directions: walk.points.first.map { ($0.lat, $0.lon, walk.start) }, sources: walk.sources)
                }
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planning) { AddToPlanSheet(target: $0) }
        .fullScreenCover(isPresented: $following) { WalkFollowView(walk: walk) }
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(theme.t.primary)
    }

    private func tideCard(_ text: String) -> some View {
        Card {
            Label("Tide warning", systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.bold)).foregroundStyle(.orange)
            Text(text).font(.footnote).foregroundStyle(theme.t.onBackground).fixedSize(horizontal: false, vertical: true)
            if let tides = store.tides {
                let up = tides.upcoming(from: Date(), count: 4)
                TideRow(extremes: up)
                Text("Times shown for the next tides at Margate.").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
            }
        }
    }
}

/// Following a walk: the map follows you, distance done/left along the route, next point
/// and its note, an off-route warning. Screen stays on.
struct WalkFollowView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var location: LocationModel
    @Environment(\.dismiss) private var dismiss
    let walk: Walk
    @State private var follow = true

    private var route: [CLLocationCoordinate2D] { walk.route.isEmpty ? walk.points.map(\.coordinate) : walk.route }

    var body: some View {
        let prog = location.location.map { RouteProgress(route: route, points: walk.points, at: $0.coordinate) }
        ZStack(alignment: .top) {
            OfflineMapView(walk: walk, routeColor: UIColor(theme.t.primary), accent: UIColor(theme.t.primary),
                           focus: MapFocus.fit(route), followUser: follow)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                HStack {
                    Button { dismiss() } label: {
                        Label("End", systemImage: "xmark").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9).background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button { follow.toggle() } label: {
                        Image(systemName: follow ? "location.north.line.fill" : "location")
                            .font(.headline).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 14)
                Spacer()
                panel(prog)
            }
            .padding(.bottom, 10)
        }
        .onAppear { location.setPrecise(true); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { location.setPrecise(false); UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func panel(_ p: RouteProgress?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(walk.title).font(.headline).foregroundStyle(theme.t.onBackground)
            if let p {
                if p.offRoute > 80 {
                    Label("You are \(distanceText(p.offRoute)) from the route", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                }
                HStack(spacing: 18) {
                    VStack(alignment: .leading) {
                        Text("Done").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                        Text(distanceText(p.done)).font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    VStack(alignment: .leading) {
                        Text("To go").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                        Text(distanceText(p.left)).font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    VStack(alignment: .leading) {
                        Text("At 4 km/h").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                        Text("\(Int(p.left / 4000 * 60)) min").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(theme.t.onBackground)
                ProgressView(value: p.fraction).tint(theme.t.primary)
                if let i = p.nextIndex {
                    let w = walk.points[i]
                    Text("Next: \(i + 1). \(w.name) · \(distanceText(p.toNext))").font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.t.primary)
                    if let n = w.note { Text(n).font(.caption).foregroundStyle(theme.t.onSurfaceVariant).lineLimit(4) }
                } else {
                    Text("You have reached the end of the walk.").font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.primary)
                }
            } else {
                Text("Waiting for your location… (works without signal; allow location for Explorer in Settings)")
                    .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
            }
        }
        .padding(14)
        .background(theme.t.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }
}

/// Where you are along a route: projected onto the nearest segment.
struct RouteProgress {
    let done: Double
    let left: Double
    let fraction: Double
    let offRoute: Double
    let nextIndex: Int?
    let toNext: Double

    init(route: [CLLocationCoordinate2D], points: [WalkPoint], at c: CLLocationCoordinate2D) {
        // local metric projection around the walker
        let lat0 = c.latitude * .pi / 180
        func xy(_ p: CLLocationCoordinate2D) -> (Double, Double) {
            ((p.longitude - c.longitude) * 111_320 * cos(lat0), (p.latitude - c.latitude) * 110_540)
        }
        var cum: [Double] = [0]
        for i in 1..<max(route.count, 1) {
            cum.append(cum[i - 1] + route[i - 1].distance(to: route[i]))
        }
        let total = cum.last ?? 0
        var best = (d: Double.infinity, along: 0.0)
        if route.count >= 2 {
            for i in 0..<(route.count - 1) {
                let a = xy(route[i]), b = xy(route[i + 1])
                let dx = b.0 - a.0, dy = b.1 - a.1
                let len2 = dx * dx + dy * dy
                let t = len2 > 0 ? max(0, min(1, -(a.0 * dx + a.1 * dy) / len2)) : 0
                let px = a.0 + t * dx, py = a.1 + t * dy
                let d = (px * px + py * py).squareRoot()
                if d < best.d { best = (d, cum[i] + t * (cum[i + 1] - cum[i])) }
            }
        } else if let only = route.first {
            best = (c.distance(to: only), 0)
        }
        done = best.along
        left = max(0, total - best.along)
        fraction = total > 0 ? best.along / total : 0
        offRoute = best.d
        // each waypoint's position along the route
        var next: Int?
        var toNext = 0.0
        for (i, w) in points.enumerated() {
            var along = 0.0, bd = Double.infinity
            for (j, r) in route.enumerated() {
                let d = r.distance(to: w.coordinate)
                if d < bd { bd = d; along = cum[min(j, cum.count - 1)] }
            }
            if along > best.along + 15 { next = i; toNext = along - best.along; break }
        }
        nextIndex = next
        self.toNext = toNext
    }
}

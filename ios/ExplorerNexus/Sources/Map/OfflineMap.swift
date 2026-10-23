import MapKit
import SwiftUI
import UIKit

/// The offline map tiles: bundled map-lo.sqlite (z9-16) and map-hi.sqlite (z17), rendered on
/// the PC from OpenStreetMap by tools/build/s02_tiles.py; 512-px images on the 256 grid. Deeper than the deepest
/// level (or outside the detailed area) the nearest rendered parent tile is cropped and
/// scaled up, so zooming in never shows blank squares.
final class OfflineTileOverlay: MKTileOverlay {
    static let shared = OfflineTileOverlay()
    private let lo: SQLiteDB?
    private let hi: SQLiteDB?
    private(set) var maxRendered = 17
    private let cache = NSCache<NSString, NSData>()

    private init() {
        func open(_ name: String) -> SQLiteDB? {
            Bundle.main.path(forResource: name, ofType: "sqlite", inDirectory: "Content").flatMap { SQLiteDB(path: $0) }
        }
        lo = open("map-lo")
        hi = open("map-hi")
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 9
        maximumZ = 20
        cache.countLimit = 300
        lo?.query("SELECT value FROM meta WHERE key = 'maxzoom'") { r in
            if let v = r.string(0), let z = Int(v) { self.maxRendered = z }
        }
    }

    private func raw(_ z: Int, _ x: Int, _ y: Int) -> Data? {
        let key = "\(z)/\(x)/\(y)" as NSString
        if let d = cache.object(forKey: key) { return d as Data }
        var out: Data?
        (z >= 17 ? hi : lo)?.query("SELECT data FROM tiles WHERE z = ? AND x = ? AND y = ?", [z, x, y]) { r in out = r.data(0) }
        if let out { cache.setObject(out as NSData, forKey: key) }
        return out
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        if path.z <= maxRendered, let d = raw(path.z, path.x, path.y) {
            result(d, nil)
            return
        }
        // walk up to a rendered ancestor and cut our piece out of it
        var z = min(path.z, maxRendered)
        while z >= 9 {
            let shift = path.z - z
            let px = path.x >> shift
            let py = path.y >> shift
            if shift > 0, let d = raw(z, px, py), let img = UIImage(data: d)?.cgImage {
                let n = 1 << shift
                let sub = CGFloat(img.width) / CGFloat(n)
                let ox = CGFloat(path.x - (px << shift)) * sub
                let oy = CGFloat(path.y - (py << shift)) * sub
                guard let crop = img.cropping(to: CGRect(x: ox, y: oy, width: sub, height: sub)) else { break }
                let size = CGSize(width: 512, height: 512)
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                let out = UIGraphicsImageRenderer(size: size, format: fmt).pngData { ctx in
                    ctx.cgContext.interpolationQuality = shift > 2 ? .medium : .high
                    UIImage(cgImage: crop).draw(in: CGRect(origin: .zero, size: size))
                }
                result(out, nil)
                return
            }
            // not rendered at this zoom here (outside the detailed box): try the parent
            z -= 1
        }
        result(OfflineTileOverlay.blank, nil)
    }

    /// Land-coloured tile for places outside the map.
    static let blank: Data = {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: fmt).pngData { ctx in
            UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }()

    /// Everything the map covers (camera can't leave it).
    static let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 51.27, longitude: 1.175),
                                           span: MKCoordinateSpan(latitudeDelta: 0.38, longitudeDelta: 0.65))
}

/// A pin on the map.
final class PinAnnotation: NSObject, MKAnnotation {
    enum Ref { case place(Place), event(EventItem), waypoint(Int, WalkPoint) }
    let ref: Ref
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ ref: Ref) {
        self.ref = ref
        switch ref {
        case .place(let p):
            coordinate = p.coordinate; title = p.name; subtitle = Cat.label(p.category)
        case .event(let e):
            coordinate = e.coordinate ?? Sun.birchington; title = e.title; subtitle = e.venue
        case .waypoint(let i, let w):
            coordinate = w.coordinate; title = "\(i + 1). \(w.name)"; subtitle = nil
        }
    }
}

/// MKMapView wrapped for SwiftUI: offline tiles, pins, one walk route, user location.
struct OfflineMapView: UIViewRepresentable {
    var places: [Place] = []
    var events: [EventItem] = []
    var walk: Walk? = nil
    var showWaypoints = true
    var routeColor: UIColor = .systemOrange
    var accent: UIColor = .systemOrange
    /// Change the value to move the camera (centre, metres across).
    var focus: MapFocus? = nil
    var followUser = false
    var onSelect: (PinAnnotation.Ref) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.addOverlay(OfflineTileOverlay.shared, level: .aboveLabels)
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: OfflineTileOverlay.region), animated: false)
        map.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 120, maxCenterCoordinateDistance: 90_000), animated: false)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "wp")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        let start = MKCoordinateRegion(center: Sun.birchington, latitudinalMeters: 4000, longitudinalMeters: 4000)
        map.setRegion(start, animated: false)
        context.coordinator.sync(map)
        context.coordinator.applyFocus(map, focus, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
        context.coordinator.applyFocus(map, focus, animated: true)
        let mode: MKUserTrackingMode = followUser ? .followWithHeading : .none
        if followUser, map.userTrackingMode != mode { map.setUserTrackingMode(mode, animated: true) }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OfflineMapView
        private var shownKey = ""
        private var focusKey: String?
        private var routeLine: MKPolyline?

        init(_ p: OfflineMapView) { parent = p }

        func sync(_ map: MKMapView) {
            let key = parent.places.map(\.id).joined(separator: ",") + "|" + parent.events.map(\.id).joined(separator: ",")
                + "|" + (parent.walk?.id ?? "") + "|\(parent.showWaypoints)"
            guard key != shownKey else { return }
            shownKey = key
            map.removeAnnotations(map.annotations.filter { $0 is PinAnnotation })
            if let r = routeLine { map.removeOverlay(r); routeLine = nil }
            var pins: [PinAnnotation] = parent.places.map { PinAnnotation(.place($0)) }
            pins += parent.events.filter { $0.coordinate != nil }.map { PinAnnotation(.event($0)) }
            if let w = parent.walk {
                if parent.showWaypoints {
                    pins += w.points.enumerated().map { PinAnnotation(.waypoint($0.offset, $0.element)) }
                }
                var coords = w.route.isEmpty ? w.points.map(\.coordinate) : w.route
                let line = MKPolyline(coordinates: &coords, count: coords.count)
                map.addOverlay(line, level: .aboveLabels)
                routeLine = line
            }
            map.addAnnotations(pins)
        }

        func applyFocus(_ map: MKMapView, _ f: MapFocus?, animated: Bool) {
            guard let f, f.key != focusKey else { return }
            focusKey = f.key
            if let rect = f.rect {
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: animated)
            } else {
                map.setRegion(MKCoordinateRegion(center: f.center, latitudinalMeters: f.meters, longitudinalMeters: f.meters), animated: animated)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            if let l = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = parent.routeColor.withAlphaComponent(0.9)
                r.lineWidth = 5
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as? MKMarkerAnnotationView
                v?.markerTintColor = parent.accent
                v?.glyphText = "\(cluster.memberAnnotations.count)"
                return v
            }
            guard let pin = annotation as? PinAnnotation else { return nil }
            switch pin.ref {
            case .place(let p):
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: pin) as? MKMarkerAnnotationView
                v?.markerTintColor = UIColor(Cat.color(p.category))
                v?.glyphImage = UIImage(systemName: Cat.symbol(p.category))
                v?.glyphText = nil
                v?.clusteringIdentifier = parent.walk == nil ? "places" : nil
                v?.displayPriority = p.isPhoto || ["sight", "museum", "history", "beach"].contains(p.category) ? .defaultHigh : .defaultLow
                v?.canShowCallout = true
                v?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
                return v
            case .event(let e):
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: pin) as? MKMarkerAnnotationView
                v?.markerTintColor = parent.accent
                v?.glyphImage = UIImage(systemName: Cat.eventSymbol(e.category))
                v?.glyphText = nil
                v?.clusteringIdentifier = "events"
                v?.canShowCallout = true
                v?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
                return v
            case .waypoint(let i, _):
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "wp", for: pin) as? MKMarkerAnnotationView
                v?.markerTintColor = parent.routeColor
                v?.glyphImage = nil
                v?.glyphText = "\(i + 1)"
                v?.clusteringIdentifier = nil
                v?.displayPriority = .required
                v?.canShowCallout = true
                v?.rightCalloutAccessoryView = nil
                return v
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let pin = view.annotation as? PinAnnotation else { return }
            parent.onSelect(pin.ref)
        }
    }
}

/// A camera move request. Two requests for the same view are equal (views can rebuild
/// them freely without the map jumping back); bump `nonce` to move there again.
struct MapFocus: Equatable {
    var center: CLLocationCoordinate2D = Sun.birchington
    var meters: CLLocationDistance = 3000
    var rect: MKMapRect? = nil
    var nonce = 0

    var key: String {
        if let r = rect { return "r\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.size.width)),\(Int(r.size.height))#\(nonce)" }
        return String(format: "c%.5f,%.5f,%.0f#%d", center.latitude, center.longitude, meters, nonce)
    }

    static func == (a: MapFocus, b: MapFocus) -> Bool { a.key == b.key }

    static func fit(_ coords: [CLLocationCoordinate2D], nonce: Int = 0) -> MapFocus {
        var r = MKMapRect.null
        for c in coords {
            let p = MKMapPoint(c)
            r = r.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
        }
        if coords.count == 1 { return MapFocus(center: coords[0], meters: 1200, nonce: nonce) }
        return MapFocus(center: coords.first ?? Sun.birchington, rect: r.isNull ? nil : r, nonce: nonce)
    }
}

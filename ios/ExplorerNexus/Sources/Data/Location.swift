import Combine
import CoreLocation
import Foundation

/// Where the phone is (GPS works without signal), shared by lists, map and walk follow.
@MainActor
final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: CLLocationDirection?
    @Published var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private var precise = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        status = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    /// Walk follow: best accuracy and compass while it is on screen.
    func setPrecise(_ on: Bool) {
        precise = on
        manager.desiredAccuracy = on ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = on ? 5 : 25
        if on { manager.startUpdatingHeading() } else { manager.stopUpdatingHeading() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.location = l }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func distance(to c: CLLocationCoordinate2D) -> CLLocationDistance? {
        location.map { $0.coordinate.distance(to: c) }
    }
}

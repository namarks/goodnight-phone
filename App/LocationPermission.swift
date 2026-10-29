import CoreLocation
import UIKit

/// Walks the user from "not asked" → When In Use → Always, and tracks Precise Location
/// (iBeacon detection doesn't work with approximate location).
@MainActor
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var isPrecise: Bool

    private let manager: CLLocationManager
    private var wantsAlways = false

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.status = manager.authorizationStatus
        self.isPrecise = manager.accuracyAuthorization == .fullAccuracy
        super.init()
        manager.delegate = self
    }

    var isReady: Bool { status == .authorizedAlways && isPrecise }

    var label: String {
        switch status {
        case .authorizedAlways: return isPrecise ? "Always, precise" : "Turn on Precise Location"
        case .authorizedWhenInUse: return "Needs “Always”"
        case .denied, .restricted: return "Off — open Settings"
        default: return "Not set"
        }
    }

    func request() {
        switch status {
        case .notDetermined:
            wantsAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            // Denied, or Always without Precise: only Settings can fix it.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    func refresh() {
        status = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in
            self.status = status
            self.isPrecise = precise
            // Second step of the flow: upgrade When In Use to Always right away.
            if status == .authorizedWhenInUse, self.wantsAlways {
                self.wantsAlways = false
                self.manager.requestAlwaysAuthorization()
            }
            if status == .authorizedAlways {
                RoomMonitor.shared.start()   // picks up the background location session right away
            }
        }
    }
}

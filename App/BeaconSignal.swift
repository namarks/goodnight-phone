import CoreLocation

/// Live signal from the bedroom beacon while Lights Out is open, for tuning the beacon.
/// Uses beacon ranging, which iOS only runs in the foreground. It's display-only:
/// whether you're in the room (and so whether apps are blocked) still comes from RoomMonitor.
@MainActor
final class BeaconSignal: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Reading: Equatable {
        var proximity: CLProximity
        var meters: Double   // rough estimate; negative when unknown
        var rssi: Int        // dBm
    }

    /// nil when the beacon isn't being heard.
    @Published private(set) var reading: Reading?

    private let manager = CLLocationManager()
    private var watching: BeaconConfig?
    private var constraint: CLBeaconIdentityConstraint?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Ranges for `beacon`, replacing whatever was ranged before. Safe to call repeatedly.
    func watch(_ beacon: BeaconConfig?) {
        guard beacon != watching else { return }
        stop()
        guard let beacon, let constraint = beacon.constraint else { return }
        watching = beacon
        self.constraint = constraint
        manager.startRangingBeacons(satisfying: constraint)
    }

    func stop() {
        if let constraint { manager.stopRangingBeacons(satisfying: constraint) }
        constraint = nil
        watching = nil
        reading = nil
    }

    var label: String {
        guard let reading else { return "Not detected" }
        var parts: [String]
        switch reading.proximity {
        case .immediate: parts = ["Very close"]
        case .near: parts = ["Near"]
        case .far: parts = ["Far"]
        default: parts = ["Weak"]
        }
        if reading.meters >= 0 { parts.append(String(format: "about %.1f m", reading.meters)) }
        parts.append("\(reading.rssi) dBm")
        return parts.joined(separator: " · ")
    }

    /// 0...1 for the signal bars: −95 dBm or weaker is empty, −55 dBm or stronger is full.
    var strength: Double {
        guard let reading else { return 0 }
        return min(max(Double(reading.rssi + 95) / 40, 0), 1)
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        // An RSSI of 0 means iOS has the beacon on record but didn't hear it this round.
        let best = beacons.filter { $0.rssi != 0 }.max { $0.rssi < $1.rssi }
        let reading = best.map { Reading(proximity: $0.proximity, meters: $0.accuracy, rssi: $0.rssi) }
        Task { @MainActor in
            guard self.constraint != nil else { return }
            self.reading = reading
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailRangingFor constraint: CLBeaconIdentityConstraint,
        error: Error
    ) {
        Task { @MainActor in self.reading = nil }
    }
}

extension BeaconConfig {
    var constraint: CLBeaconIdentityConstraint? {
        guard let id = UUID(uuidString: uuid) else { return nil }
        switch (major, minor) {
        case let (major?, minor?): return CLBeaconIdentityConstraint(uuid: id, major: major, minor: minor)
        case let (major?, nil): return CLBeaconIdentityConstraint(uuid: id, major: major)
        default: return CLBeaconIdentityConstraint(uuid: id)
        }
    }
}

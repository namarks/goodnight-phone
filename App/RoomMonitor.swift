import CoreLocation
import Foundation

/// Watches for the bedroom beacon with Core Location's CLMonitor.
///
/// iOS keeps monitoring even when the app isn't running and relaunches it in the
/// background on enter/exit, so `start()` must run on every launch (AppDelegate does this).
/// Requires "Always" location access with Precise Location on.
@MainActor
final class RoomMonitor {
    static let shared = RoomMonitor()

    private static let monitorName = "LightsOutBedroom"
    static let conditionID = "bedroom"

    private var monitor: CLMonitor?
    private var eventsTask: Task<Void, Never>?
    private var serviceSession: Any?   // CLServiceSession on iOS 18+

    /// Safe to call repeatedly: restarts monitoring if it ever stopped.
    func start() {
        holdServiceSessionIfAuthorized()
        guard eventsTask == nil else { return }
        eventsTask = Task { await self.run() }
    }

    /// iOS 18+: hold an explicit "Always" session so beacon events keep arriving when the app
    /// is relaunched in the background. Only created once Always is granted, so it never
    /// triggers a surprise permission prompt.
    private func holdServiceSessionIfAuthorized() {
        if #available(iOS 18.0, *) {
            guard serviceSession == nil,
                  CLLocationManager().authorizationStatus == .authorizedAlways else { return }
            serviceSession = CLServiceSession(authorization: .always)
        }
    }

    private func run() async {
        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        await syncCondition()
        await refreshFromSystem()

        do {
            for try await event in await monitor.events {
                guard event.identifier == Self.conditionID else { continue }
                apply(event.state)
            }
        } catch {
            Shared.log("Beacon monitoring stopped: \(error.localizedDescription)")
        }
        // Release this monitor so the next start() (app foreground or relaunch) creates a fresh one.
        self.monitor = nil
        eventsTask = nil
    }

    /// Makes the monitor watch exactly the beacon saved in settings.
    func syncCondition() async {
        guard let monitor else { return }
        let config = Shared.beacon
        let alreadyWatching = await monitor.hasCondition(Self.conditionID)
        if alreadyWatching, config == Shared.monitoredBeacon { return }

        await monitor.remove(Self.conditionID)
        Shared.monitoredBeacon = nil

        if let config, let condition = config.condition {
            await monitor.add(condition, identifier: Self.conditionID, assuming: .unsatisfied)
            Shared.monitoredBeacon = config
            Shared.log("Watching for beacon \(config.shortDescription)")
        }
        setInRoom(false, reason: "beacon settings changed")
    }

    /// Re-reads the latest state from Core Location (used when the app comes to the foreground,
    /// so a missed event can never leave you stuck).
    func refreshFromSystem() async {
        guard let monitor, let state = await monitor.lastState(for: Self.conditionID) else { return }
        apply(state)
    }

    private func apply(_ state: CLMonitor.Event.State) {
        switch state {
        case .satisfied: setInRoom(true)
        case .unsatisfied: setInRoom(false)
        default: break   // .unknown / .unmonitored: keep the last known state
        }
    }

    /// `reason` is only passed for non-beacon changes (e.g. switching beacons).
    private func setInRoom(_ inRoom: Bool, reason: String? = nil) {
        if Shared.inRoom != inRoom, reason == nil {
            Shared.log(inRoom ? "Entered bedroom" : "Left bedroom")
        }
        Shared.inRoom = inRoom
        Blocker.refresh(reason: reason ?? (inRoom ? "in the bedroom" : "left the bedroom"))
        AppModel.shared.reload()
    }
}

// Small helpers that run inside the CLMonitor actor and return just what the app needs.
extension CLMonitor {
    func hasCondition(_ identifier: String) -> Bool {
        record(for: identifier) != nil
    }

    func lastState(for identifier: String) -> CLMonitor.Event.State? {
        record(for: identifier)?.lastEvent.state
    }
}

extension BeaconConfig {
    var condition: CLMonitor.BeaconIdentityCondition? {
        guard let id = UUID(uuidString: uuid) else { return nil }
        switch (major, minor) {
        case let (major?, minor?): return CLMonitor.BeaconIdentityCondition(uuid: id, major: major, minor: minor)
        case let (major?, nil): return CLMonitor.BeaconIdentityCondition(uuid: id, major: major)
        default: return CLMonitor.BeaconIdentityCondition(uuid: id)
        }
    }
}

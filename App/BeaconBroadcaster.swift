import CoreBluetooth
import CoreLocation
import UIKit

/// Lets a spare iPad or iPhone running Lights Out stand in for the bedroom beacon until a
/// real one arrives. One instance lives for the whole app session, so the broadcast keeps
/// going on any screen. iOS only broadcasts iBeacon data while the app is on screen, so the
/// display is kept awake while broadcasting.
@MainActor
final class BeaconBroadcaster: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let shared = BeaconBroadcaster()

    enum Status: Equatable {
        case off, starting, broadcasting, bluetoothOff, notAllowed, unsupported
        case failed(String)
    }

    @Published private(set) var isOn = false
    @Published private(set) var status = Status.off

    private var manager: CBPeripheralManager?

    private override init() { super.init() }

    var label: String {
        switch status {
        case .off: return "Off"
        case .starting: return "Starting…"
        case .broadcasting: return "Broadcasting"
        case .bluetoothOff: return "Turn on Bluetooth"
        case .notAllowed: return "Bluetooth off for Lights Out — open Settings"
        case .unsupported: return "Not supported on this device"
        case .failed(let message): return message
        }
    }

    func setOn(_ on: Bool) {
        on ? start() : stop()
    }

    func start() {
        isOn = true
        UIApplication.shared.isIdleTimerDisabled = true
        if let manager {
            advertiseIfReady(manager)
        } else {
            status = .starting
            // Creating the manager shows the Bluetooth permission prompt the first time.
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }

    func stop() {
        isOn = false
        UIApplication.shared.isIdleTimerDisabled = false
        manager?.stopAdvertising()
        status = .off
    }

    /// iOS drops the iBeacon data while the app is in the background, so restart the
    /// broadcast when it comes back to the foreground.
    func resume() {
        guard isOn, let manager else { return }
        manager.stopAdvertising()
        advertiseIfReady(manager)
    }

    private func advertiseIfReady(_ manager: CBPeripheralManager) {
        switch manager.state {
        case .poweredOn:
            if manager.isAdvertising {
                status = .broadcasting
            } else {
                status = .starting
                manager.startAdvertising(Self.advertisement)
            }
        case .poweredOff: status = .bluetoothOff
        case .unauthorized: status = .notAllowed
        case .unsupported: status = .unsupported
        default: status = .starting   // .unknown / .resetting: a state update follows
        }
    }

    private static let advertisement: [String: Any]? = {
        let region = CLBeaconRegion(
            uuid: BeaconConfig.standInUUID, major: 1, minor: 1, identifier: "LightsOutStandIn"
        )
        return region.peripheralData(withMeasuredPower: nil) as? [String: Any]
    }()

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            guard self.isOn, let manager = self.manager else { return }
            self.advertiseIfReady(manager)
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            guard self.isOn else { return }
            self.status = message.map(Status.failed) ?? .broadcasting
        }
    }
}

extension BeaconConfig {
    /// Broadcast by every copy of the app in stand-in mode, so the phone can watch for it
    /// without anyone typing a UUID.
    static let standInUUID = UUID(uuidString: "E6B2E125-B543-4BA4-8D19-B68DBA9F147C")!
    static let standIn = BeaconConfig(uuid: standInUUID.uuidString)
}

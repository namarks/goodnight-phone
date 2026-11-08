import CoreBluetooth
import Foundation

/// Looks for a bedroom hub (a XIAO board or a spare iPad/iPhone broadcasting) while its setup
/// screen is open, so someone coming back from installing the board on a computer sees "Found
/// your board" with one tap left. Display only: picking the hub and watching it is HubMonitor's
/// job. No state restoration, and it stops scanning when the screen closes.
@MainActor
final class HubFinder: NSObject, ObservableObject, CBCentralManagerDelegate {
    enum State: Equatable { case idle, searching, found, bluetoothOff, notAllowed }

    @Published private(set) var state = State.idle

    private var central: CBCentralManager?

    func start() {
        guard central == nil else { return }
        state = .searching
        // Creating the manager shows the Bluetooth permission prompt the first time.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func stop() {
        central?.stopScan()
        central?.delegate = nil
        central = nil
        state = .idle
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard central === self.central else { return }
            switch central.state {
            case .poweredOn:
                if state != .found { state = .searching }
                central.scanForPeripherals(withServices: [BeaconBroadcaster.serviceUUID])
            case .poweredOff:
                state = .bluetoothOff
            case .unauthorized:
                state = .notAllowed
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            guard central === self.central else { return }
            state = .found
            central.stopScan()
        }
    }
}

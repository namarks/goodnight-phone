import CoreBluetooth
import UIKit

/// Lets a spare iPad or iPhone running Lights Out stand in for the bedroom beacon. It offers a
/// Bluetooth connection (not an iBeacon); connected phones read the signal strength on each
/// heartbeat (see HubMonitor). Each phone tells it its bedtime hours, and it only sends that
/// phone heartbeats during them, so the phone isn't woken all day.
///
/// One instance lives for the whole app session, so it keeps going on any screen. iOS only keeps
/// this running while the app is on screen, so the display is kept awake while it's on, and the
/// service is withdrawn when the app leaves the screen so phones count you as outside instead of
/// freezing on their last reading.
@MainActor
final class BeaconBroadcaster: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let shared = BeaconBroadcaster()

    /// The stand-in's Bluetooth service. Same in every copy of the app, so the phone can find it.
    static let serviceUUID = CBUUID(nsuuid: BeaconConfig.standInUUID)
    static let heartbeatUUID = CBUUID(string: "17FEA0BC-C577-41FE-B8A1-9604CDE1C469")
    /// Phones write their BedtimeSchedule (JSON) here.
    static let scheduleUUID = CBUUID(string: "8C4D4E0A-2F5B-4B8E-9C1D-3A6F7E2B5D90")
    /// Heartbeat values: a beat means "read my signal now"; pause means bedtime hours just ended.
    static let beatValue = Data([1])
    static let pauseValue = Data([0])

    private static let interval: TimeInterval = 2
    private static let savedKey = "standInBroadcasting"

    enum Status: Equatable {
        case off, starting, broadcasting, bluetoothOff, notAllowed, unsupported
        case failed(String)
    }

    @Published private(set) var isOn = false
    @Published private(set) var status = Status.off
    /// Phones currently connected and listening for the heartbeat.
    @Published private(set) var phones = 0

    private var manager: CBPeripheralManager?
    private var heartbeat: CBMutableCharacteristic?
    private var timer: Timer?
    private var subscribers: [UUID: CBCentral] = [:]
    private var schedules: [UUID: BedtimeSchedule] = [:]
    /// Whether each phone was last sent a beat (true) or a pause (false).
    private var wasAwake: [UUID: Bool] = [:]

    private override init() { super.init() }

    var label: String {
        switch status {
        case .off: return "Off"
        case .starting: return "Starting…"
        case .broadcasting:
            switch phones {
            case 0: return "Waiting for your phone"
            case 1: return "Phone connected"
            default: return "\(phones) phones connected"
            }
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
        UserDefaults.standard.set(true, forKey: Self.savedKey)
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
        UserDefaults.standard.set(false, forKey: Self.savedKey)
        UIApplication.shared.isIdleTimerDisabled = false
        withdraw()
        status = .off
    }

    /// Turns broadcasting back on when the app opens, if it was on when the app last closed.
    func restore() {
        if !isOn, UserDefaults.standard.bool(forKey: Self.savedKey) { start() }
    }

    /// The app is leaving the screen. iOS would stop the heartbeat anyway; withdrawing the service
    /// tells connected phones right away.
    func suspend() {
        guard isOn else { return }
        withdraw()
        status = .starting
    }

    /// Back on screen: publish the service again.
    func resume() {
        guard isOn, let manager else { return }
        advertiseIfReady(manager)
    }

    private func withdraw() {
        timer?.invalidate()
        timer = nil
        if let manager, manager.state == .poweredOn {
            manager.stopAdvertising()
            manager.removeAllServices()
        }
        heartbeat = nil
        subscribers = [:]
        schedules = [:]
        wasAwake = [:]
        phones = 0
    }

    private func advertiseIfReady(_ manager: CBPeripheralManager) {
        switch manager.state {
        case .poweredOn:
            if heartbeat == nil {
                let heartbeat = CBMutableCharacteristic(
                    type: Self.heartbeatUUID, properties: [.notify], value: nil, permissions: []
                )
                let schedule = CBMutableCharacteristic(
                    type: Self.scheduleUUID, properties: [.write], value: nil, permissions: [.writeable]
                )
                let service = CBMutableService(type: Self.serviceUUID, primary: true)
                service.characteristics = [heartbeat, schedule]
                self.heartbeat = heartbeat
                status = .starting
                manager.add(service)   // advertising starts once the service is added
            } else if manager.isAdvertising {
                status = .broadcasting
            } else {
                status = .starting
                manager.startAdvertising([
                    CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                    CBAdvertisementDataLocalNameKey: "Lights Out",
                ])
            }
        case .poweredOff: status = .bluetoothOff
        case .unauthorized: status = .notAllowed
        case .unsupported: status = .unsupported
        default: status = .starting   // .unknown / .resetting: a state update follows
        }
    }

    /// Sends each phone a beat during its bedtime hours, and one pause when they end.
    private func beat() {
        guard let manager, let heartbeat else { return }
        for (id, central) in subscribers {
            let awake = schedules[id]?.contains(.now) ?? true
            if awake {
                // Returns false when the send queue is full; the next beat goes out shortly.
                _ = manager.updateValue(Self.beatValue, for: heartbeat, onSubscribedCentrals: [central])
                wasAwake[id] = true
            } else if wasAwake[id] != false,
                      manager.updateValue(Self.pauseValue, for: heartbeat, onSubscribedCentrals: [central]) {
                wasAwake[id] = false
            }
        }
    }

    // MARK: - CBPeripheralManagerDelegate (delivered on the main queue)

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            if peripheral.state != .poweredOn {
                // iOS drops added services when Bluetooth turns off; add them again when it's back.
                withdraw()
            }
            guard isOn else { return }
            advertiseIfReady(peripheral)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        let message = error?.localizedDescription
        MainActor.assumeIsolated {
            // Turned off (or the app left the screen) while this was being added: don't leave it
            // published, or a later start would add a second copy.
            guard isOn, let heartbeat, service.characteristics?.contains(where: { $0 === heartbeat }) == true else {
                if message == nil, let service = service as? CBMutableService { peripheral.remove(service) }
                return
            }
            if let message {
                self.heartbeat = nil
                status = .failed(message)
            } else {
                advertiseIfReady(peripheral)
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let message = error?.localizedDescription
        MainActor.assumeIsolated {
            guard isOn else { return }
            status = message.map(Status.failed) ?? .broadcasting
            if message == nil, timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.beat() }
                }
            }
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        MainActor.assumeIsolated {
            subscribers[central.identifier] = central
            phones = subscribers.count
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        MainActor.assumeIsolated {
            subscribers[central.identifier] = nil
            schedules[central.identifier] = nil
            wasAwake[central.identifier] = nil
            phones = subscribers.count
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        MainActor.assumeIsolated {
            guard let first = requests.first else { return }
            let data = requests
                .filter { $0.characteristic.uuid == Self.scheduleUUID }
                .sorted { $0.offset < $1.offset }
                .reduce(into: Data()) { $0.append($1.value ?? Data()) }
            if let schedule = try? JSONDecoder().decode(BedtimeSchedule.self, from: data) {
                schedules[first.central.identifier] = schedule
                peripheral.respond(to: first, withResult: .success)
            } else {
                peripheral.respond(to: first, withResult: .unlikelyError)
            }
        }
    }
}

extension BeaconConfig {
    /// Identifies the stand-in device. Same in every copy of the app, so choosing "Use a spare
    /// iPad or iPhone" needs no typing.
    static let standInUUID = UUID(uuidString: "E6B2E125-B543-4BA4-8D19-B68DBA9F147C")!
    static let standIn = BeaconConfig(uuid: standInUUID.uuidString)

    /// The stand-in is watched over a Bluetooth connection (HubMonitor), not as an iBeacon.
    var isStandIn: Bool { uuid == Self.standIn.uuid }

    var displayName: String { isStandIn ? "Spare iPad or iPhone" : shortDescription }
}

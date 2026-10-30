import CoreBluetooth
import Foundation

/// Watches for the stand-in device (a spare iPad or iPhone running Goodnight Phone) over a Bluetooth
/// connection instead of as an iBeacon. Like Brick Night, "in the bedroom" means the signal is
/// stronger than a boundary you set standing at the bedroom door, so the zone can stop short of
/// the kitchen.
///
/// During bedtime hours the stand-in sends a heartbeat every 2 seconds. Each one wakes the app
/// (bluetooth-central background mode) to read the signal strength, so this works with the app
/// closed; outside bedtime hours it stays quiet so the phone isn't woken all day. While the app
/// is open it reads the signal every second itself (live Signal row, setting the boundary).
/// iOS relaunches the app for these events via state restoration, so `sync()` runs on every
/// launch. A force-quit stops that until Goodnight Phone is opened again.
///
/// Whenever the phone can't hear the stand-in (out of range, its app closed, Bluetooth off), you
/// count as outside.
@MainActor
final class HubMonitor: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = HubMonitor()

    enum Link: Equatable { case off, bluetoothOff, notAllowed, searching, connected }

    @Published private(set) var link = Link.off
    /// Subscribed to the stand-in's heartbeat (connected, and its broadcast is on).
    @Published private(set) var isListening = false
    /// Signal strength in dBm (median of the last few readings).
    @Published private(set) var rssi: Int?
    /// Signal strength at the bedroom door. Nothing counts as in the room until it's set.
    @Published private(set) var boundary = Shared.hubBoundary {
        didSet { presence.thresholds = boundary.map(RoomCalibration.thresholds(boundary:)) }
    }
    @Published private(set) var isCalibrating = false

    private static let restoreID = "GoodnightPhoneHub"

    private var central: CBCentralManager?
    private var hub: CBPeripheral?
    private var scheduleCharacteristic: CBCharacteristic?
    /// Median smoothing, separate enter/leave thresholds and dwell times, so the signal's
    /// 5–10 dB jumps can't flip you in and out of the room.
    private var presence = RoomPresenceStateMachine(
        inRoom: Shared.inRoom,
        thresholds: Shared.hubBoundary.map(RoomCalibration.thresholds(boundary:))
    )
    private var calibration: [Int] = []
    private var pollTimer: Timer?

    private override init() { super.init() }

    var linkLabel: String {
        switch link {
        case .off: return "Off"
        case .bluetoothOff: return "Turn on Bluetooth"
        case .notAllowed: return "Bluetooth off for Goodnight Phone — open Settings"
        case .searching: return "Looking for it…"
        case .connected: return isListening ? "Connected" : "Connected, but it isn't broadcasting"
        }
    }

    /// 0...1 for the signal bars: −95 dBm or weaker is empty, −55 dBm or stronger is full.
    var strength: Double {
        guard let rssi else { return 0 }
        return min(max(Double(rssi + 95) / 40, 0), 1)
    }

    /// Starts or stops to match the beacon setting, and retries finding the stand-in if it's lost.
    /// Safe to call repeatedly.
    func sync() {
        let wanted = Shared.beacon?.isStandIn == true
        if !wanted, boundary != nil {
            // A different spare device, or a different spot, needs a new door reading.
            Shared.hubBoundary = nil
            boundary = nil
        }
        if wanted {
            if central != nil {
                if link != .connected {
                    reconnect()
                } else if let hub, !isListening {
                    // Connected but not hearing the heartbeat (a missed re-add or a failed
                    // subscribe): don't trust the last state, and try again.
                    goOutside(reason: "can't hear the bedroom hub")
                    hub.discoverServices([BeaconBroadcaster.serviceUUID])
                } else {
                    sendSchedule()   // in case an earlier send failed
                }
            } else {
                // Creating the manager shows the Bluetooth permission prompt the first time.
                central = CBCentralManager(
                    delegate: self, queue: nil,
                    options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID]
                )
            }
        } else if let central {
            if let hub { central.cancelPeripheralConnection(hub) }
            central.stopScan()
            central.delegate = nil
            self.central = nil
            hub = nil
            link = .off
            forgetReadings()
            RoomMonitor.shared.setInRoom(false, reason: "beacon settings changed")
        }
    }

    /// Called as the app comes on and off screen.
    func setForeground(_ isForeground: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        if isForeground {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)   // keeps polling while the screen scrolls
            pollTimer = timer
        } else if Shared.beacon?.isStandIn == true, !Shared.schedule.contains(.now) {
            // The stand-in stays quiet outside bedtime hours, so nothing would update this before
            // bedtime starts. Start bedtime from "outside" rather than a stale "in the bedroom".
            pause()
        }
    }

    /// Tells the stand-in your bedtime hours, so it only wakes this phone during them.
    func sendSchedule() {
        let hours = PhoneHours(schedule: Shared.schedule, timeZone: TimeZone.current.identifier)
        guard let hub, hub.state == .connected, let scheduleCharacteristic,
              let data = try? JSONEncoder().encode(hours) else { return }
        hub.writeValue(data, for: scheduleCharacteristic, type: .withResponse)
    }

    /// Records the signal over the next few readings and saves it as the bedroom boundary.
    func calibrate() {
        guard isListening else { return }
        calibration = []
        isCalibrating = true
    }

    // MARK: - Connection

    /// Reconnects to the known stand-in (iOS completes this whenever it's back in range) and scans
    /// in case its Bluetooth address has changed since.
    private func reconnect() {
        guard let central, central.state == .poweredOn else { return }
        if let hub, hub.state == .connected {
            connected(hub)
            return
        }
        link = .searching
        goOutside(reason: "can't reach the bedroom hub")
        if let hub { central.connect(hub) }
        central.scanForPeripherals(withServices: [BeaconBroadcaster.serviceUUID])
    }

    private func found(_ peripheral: CBPeripheral) {
        guard let central, link != .connected else { return }
        // Keep scanning until a connection actually completes (connected() stops it), in case
        // this attempt never does.
        if let hub, hub !== peripheral { central.cancelPeripheralConnection(hub) }
        hub = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    private func connected(_ peripheral: CBPeripheral) {
        guard peripheral === hub else { return }
        central?.stopScan()
        if link != .connected { Shared.log("Connected to the bedroom hub") }
        link = .connected
        forgetReadings()
        peripheral.discoverServices([BeaconBroadcaster.serviceUUID])
    }

    /// Out of reach (or the stand-in stopped), so you're not in the bedroom.
    private func disconnected(_ peripheral: CBPeripheral) {
        guard peripheral === hub else { return }
        if link == .connected { Shared.log("Lost the bedroom hub") }
        forgetReadings()
        if Shared.inRoom { RoomMonitor.shared.setInRoom(false) }
        reconnect()
    }

    /// The stand-in withdrew its service (broadcast turned off, or its app left the screen).
    /// Count you as outside and look for the service again; it reappears when it's back on.
    private func serviceGone(_ peripheral: CBPeripheral) {
        guard peripheral === hub else { return }
        forgetReadings()
        goOutside(reason: "bedroom hub stopped broadcasting")
        peripheral.discoverServices([BeaconBroadcaster.serviceUUID])
    }

    private func forgetReadings() {
        isListening = false
        scheduleCharacteristic = nil
        presence.forgetReadings()
        rssi = nil
        isCalibrating = false
    }

    private func goOutside(reason: String) {
        if Shared.inRoom { RoomMonitor.shared.setInRoom(false, reason: reason) }
    }

    // MARK: - Signal

    /// Bedtime hours ended (or the app closed outside them): readings stop until bedtime.
    private func pause() {
        presence.forgetReadings()
        goOutside(reason: "outside bedtime hours")
    }

    private func poll() {
        guard isListening, let hub else { return }
        presence.sync(inRoom: Shared.inRoom)
        if presence.tick(at: .now) == .left { RoomMonitor.shared.setInRoom(false) }
        hub.readRSSI()
    }

    private func record(_ value: Int) {
        guard RoomPresenceStateMachine.isValid(value) else { return }   // 127 means iOS couldn't measure it
        if Shared.inRoom, !Shared.isInRoom() {
            // Not confirmed for a while (force-quit, restart, a long gap), and Blocker already
            // ignores it: start again from outside and let the readings re-enter.
            RoomMonitor.shared.setInRoom(false, reason: "no recent reading")
        }
        presence.sync(inRoom: Shared.inRoom)   // other events (Bluetooth off, settings) may have changed it
        let transition = presence.add(rssi: value, at: .now)
        rssi = presence.smoothedRSSI

        if isCalibrating {
            calibration.append(value)
            if calibration.count >= RoomCalibration.sampleCount { finishCalibration() }
        }
        guard boundary != nil else {
            goOutside(reason: "no bedroom boundary set")
            return
        }
        guard isListening else { return }
        Shared.hubLastHeard = .now   // keeps the current in/out state trusted (Shared.isInRoom)
        switch transition {
        case .entered: RoomMonitor.shared.setInRoom(true)
        case .left: RoomMonitor.shared.setInRoom(false)
        case nil: break
        }
    }

    private func finishCalibration() {
        let value = RoomCalibration.boundary(doorSamples: calibration)
        calibration = []
        isCalibrating = false
        guard let value else { return }
        let thresholds = RoomCalibration.thresholds(boundary: value)
        Shared.hubBoundary = value
        boundary = value
        Shared.log("Bedroom boundary set at \(value) dBm (in at \(thresholds.enter), out at \(thresholds.leave))")
        AppModel.shared.reload()
    }

    // MARK: - CBCentralManagerDelegate / CBPeripheralDelegate (delivered on the main queue)

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        MainActor.assumeIsolated {
            // Prefer the one we were actually connected to; drop leftover connection attempts.
            guard let peripheral = restored.first(where: { $0.state == .connected }) ?? restored.first else { return }
            for other in restored where other !== peripheral { central.cancelPeripheralConnection(other) }
            hub = peripheral
            peripheral.delegate = self
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard central === self.central else { return }
            switch central.state {
            case .poweredOn:
                reconnect()
            case .poweredOff:
                link = .bluetoothOff
                forgetReadings()
                goOutside(reason: "Bluetooth is off")
            case .unauthorized:
                link = .notAllowed
                forgetReadings()
                goOutside(reason: "Bluetooth isn't allowed for Goodnight Phone")
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
        MainActor.assumeIsolated { found(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { connected(peripheral) }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated { disconnected(peripheral) }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated { disconnected(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        MainActor.assumeIsolated {
            let ours = invalidatedServices.contains { $0.uuid == BeaconBroadcaster.serviceUUID }
            // Also covers the service coming back after a withdrawal: rediscover and resubscribe.
            if ours || !isListening { serviceGone(peripheral) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === hub else { return }
            guard let service = peripheral.services?.first(where: { $0.uuid == BeaconBroadcaster.serviceUUID }) else {
                // Connected, but its broadcast is off. didModifyServices fires when it comes back.
                goOutside(reason: "bedroom hub isn't broadcasting")
                return
            }
            peripheral.discoverCharacteristics(
                [BeaconBroadcaster.heartbeatUUID, BeaconBroadcaster.scheduleUUID], for: service
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard peripheral === hub else { return }
            let characteristics = service.characteristics ?? []
            guard characteristics.contains(where: { $0.uuid == BeaconBroadcaster.heartbeatUUID }) else {
                goOutside(reason: "bedroom hub isn't broadcasting")
                return
            }
            for characteristic in characteristics {
                switch characteristic.uuid {
                case BeaconBroadcaster.heartbeatUUID: peripheral.setNotifyValue(true, for: characteristic)
                case BeaconBroadcaster.scheduleUUID: scheduleCharacteristic = characteristic
                default: break
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard peripheral === hub, characteristic.uuid == BeaconBroadcaster.heartbeatUUID else { return }
            let listening = error == nil && characteristic.isNotifying
            isListening = listening
            if listening {
                sendSchedule()
            } else {
                goOutside(reason: "can't hear the bedroom hub")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard peripheral === hub, characteristic.uuid == BeaconBroadcaster.heartbeatUUID else { return }
            if characteristic.value == BeaconBroadcaster.pauseValue { pause() } else { peripheral.readRSSI() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let value = error == nil ? RSSI.intValue : nil
        MainActor.assumeIsolated {
            guard peripheral === hub, let value else { return }
            record(value)
        }
    }
}

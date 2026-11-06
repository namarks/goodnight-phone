import CoreBluetooth
import Foundation
import kbeaconlib2

/// Sets up and tunes the recommended Blue Charm beacons (KKM KBeacon Pro firmware: the USB BC-U1
/// and the coin-cell BC05) from inside the app, so nobody needs the vendor's app. Setup gives the beacon an ID of its own, so a neighbor's
/// Blue Charm can't count as your bedroom, and starts it at a modest transmit power; the range
/// buttons step that power up or down.
///
/// The app only talks to the beacon during setup or a range change. Blocking never depends on
/// this connection: RoomMonitor watches the beacon's iBeacon broadcast like any other beacon.
/// While connected the beacon stops broadcasting, so every job disconnects when it finishes.
@MainActor
final class BlueCharm: NSObject, ObservableObject {
    static let shared = BlueCharm()

    enum Phase: Equatable {
        case idle
        case searching
        case connecting
        case writing
        case failed(String)
    }

    @Published private(set) var phase = Phase.idle
    /// Live signal (dBm) from the paired beacon while the app is open; nil when not heard in
    /// the last few seconds. Display only, like BeaconSignal: blocking still follows RoomMonitor.
    @Published private(set) var signalRSSI: Int?

    var isBusy: Bool {
        switch phase {
        case .searching, .connecting, .writing: return true
        case .idle, .failed: return false
        }
    }

    /// Transmit power steps the firmware accepts, weakest first (dBm).
    static let powerSteps = [-40, -20, -16, -12, -8, -4, 0, 4]
    /// Where setup starts. −12 dBm reached past the bedroom door on the first real test, and a
    /// range that's too long keeps you blocked outside the room, so start small; Longer is a tap away.
    static let startingPower = -20
    /// Factory password (sixteen zeros). Left as is: KKM can't reset a lost password.
    private static let password = "0000000000000000"
    /// During setup the phone is held next to the beacon, so anything weaker is someone else's.
    private static let nearbyRSSI = -65

    enum SetupError: LocalizedError {
        case bluetoothOff, bluetoothNotAllowed, notFound, passwordChanged, connectionFailed, writeFailed

        var errorDescription: String? {
            switch self {
            case .bluetoothOff: return "Turn on Bluetooth and try again."
            case .bluetoothNotAllowed: return "Goodnight Phone needs Bluetooth. Turn it on in Settings → Goodnight Phone."
            case .notFound: return "No Blue Charm beacon found. Make sure it's plugged in, or that the battery one is turned on (twist it open and hold the white button inside for 3 seconds, until the light flashes red). Then hold your iPhone right next to it and try again. If that doesn't work, unplug it and plug it back in."
            case .passwordChanged: return "This beacon has a password set, so Goodnight Phone can't change it. You can still type in its UUID below."
            case .connectionFailed: return "Couldn't connect to the beacon. Unplug it and plug it back in (for the battery one, hold the button inside for 5 seconds to turn it off, then 3 seconds to turn it back on), then try again."
            case .writeFailed: return "The beacon didn't accept the change. Try again."
            }
        }
    }

    /// Lazy: the SDK creates a Bluetooth central on first use, which would show the Bluetooth
    /// prompt to everyone at launch.
    private lazy var manager = KBeaconsMgr.sharedBeaconManager
    private var bluetoothWaiter: CheckedContinuation<Void, Error>?
    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var seen: [String: KBeacon] = [:]
    private var signalPeripheralID: String?
    private var signalHeardAt: Date?
    private var signalTimer: Timer?

    private override init() { super.init() }

    // MARK: - Jobs

    /// Finds the beacon next to the phone, gives it a fresh ID at the starting power, and returns
    /// what to save. The caller saves it as the bedroom beacon.
    func setUp() async -> BlueCharmPairing? {
        await run { [self] in
            let beacon = try await nearestBeacon()
            let pairing = BlueCharmPairing(
                peripheralID: beacon.uuidString ?? "",
                uuid: UUID().uuidString,
                txPower: Self.startingPower,
                setUpAt: .now
            )
            let config = KBCfgAdvIBeacon()
            config.setSlotIndex(0)
            config.setUuid(pairing.uuid)
            config.setMajorID(1)
            config.setMinorID(1)
            config.setTxPower(pairing.txPower)
            // Once a second: the usual beacon rate, which is what battery-life claims assume
            // (about four years on the BC05's coin cell). Twice as often would halve that, and iOS
            // notices a bedroom beacon just as well either way.
            config.setAdvPeriod(1000)
            config.setAdvTriggerOnly(false)
            // Stay connectable, or range changes would need the beacon unplugged first.
            config.setAdvConnectable(true)
            try await write(config, to: beacon)
            Shared.log("Set up Blue Charm beacon \(beacon.model ?? "?") at \(pairing.txPower) dBm")
            return pairing
        }
    }

    /// Changes the paired beacon's transmit power. Returns the updated pairing.
    func setPower(_ dBm: Int, for pairing: BlueCharmPairing) async -> BlueCharmPairing? {
        await run { [self] in
            let beacon = try await nearestBeacon(peripheralID: pairing.peripheralID)
            let config = KBCfgAdvIBeacon()
            config.setSlotIndex(0)
            config.setTxPower(dBm)
            try await write(config, to: beacon)
            var updated = pairing
            updated.txPower = dBm
            Shared.log("Beacon range set to \(dBm) dBm")
            return updated
        }
    }

    private func run<T>(_ job: () async throws -> T) async -> T? {
        guard !isBusy else { return nil }
        defer { resumeSignalScan() }
        do {
            let result = try await job()
            phase = .idle
            return result
        } catch {
            manager.stopScanning()
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    // MARK: - Live signal

    /// Scans for the paired beacon while the app is open, for the Signal row. iOS beacon ranging
    /// (BeaconSignal) has proven unreliable, and the beacon's own Bluetooth advertising is what
    /// setup already finds it by. Pass nil to stop. Safe to call repeatedly.
    func watchSignal(of pairing: BlueCharmPairing?) {
        let id = pairing.map(\.peripheralID).flatMap { $0.isEmpty ? nil : $0 }
        guard id != signalPeripheralID else { return }
        // Only touch the SDK if a scan was running: creating it shows the Bluetooth prompt.
        if signalPeripheralID != nil, !isBusy { manager.stopScanning() }
        signalTimer?.invalidate()
        signalTimer = nil
        signalPeripheralID = id
        signalHeardAt = nil
        signalRSSI = nil
        guard id != nil else { return }
        signalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                // The beacon advertises several times a second; a few quiet seconds means not heard.
                if let heard = self.signalHeardAt, Date.now.timeIntervalSince(heard) > 4 {
                    self.signalRSSI = nil
                }
            }
        }
        resumeSignalScan()
    }

    private func resumeSignalScan() {
        guard signalPeripheralID != nil, !isBusy else { return }
        manager.delegate = self
        manager.cbBeaconMgr.delegate = manager
        // If Bluetooth isn't on yet, onCentralBleStateChange calls this again.
        if manager.cbBeaconMgr.state == .poweredOn { manager.startScanning() }
    }

    // MARK: - Steps

    private func bluetoothReady() async throws {
        manager.delegate = self
        // The SDK only sets its central's delegate when it starts scanning; take state changes now.
        manager.cbBeaconMgr.delegate = manager
        for _ in 0..<2 {
            switch manager.cbBeaconMgr.state {
            case .poweredOn: return
            case .poweredOff, .resetting: throw SetupError.bluetoothOff
            case .unauthorized: throw SetupError.bluetoothNotAllowed
            default:
                // Unknown until the system reports in, and the first use shows the permission prompt.
                try await withCheckedThrowingContinuation { bluetoothWaiter = $0 }
            }
        }
    }

    /// Scans for a few seconds and returns the beacon with this peripheral ID, or else the
    /// strongest one held right next to the phone.
    private func nearestBeacon(peripheralID: String? = nil) async throws -> KBeacon {
        try await bluetoothReady()
        phase = .searching
        seen = [:]
        manager.clearBeacons()
        guard manager.startScanning() else { throw SetupError.bluetoothOff }
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            if let peripheralID, seen[peripheralID] != nil { break }
        }
        manager.stopScanning()
        let found: KBeacon?
        if let peripheralID {
            found = seen[peripheralID]
        } else {
            found = seen.values.filter { $0.rssi >= Self.nearbyRSSI }.max { $0.rssi < $1.rssi }
        }
        guard let found else { throw SetupError.notFound }
        return found
    }

    private func write(_ config: KBCfgAdvIBeacon, to beacon: KBeacon) async throws {
        phase = .connecting
        defer { beacon.disconnect() }
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            connectWaiter = waiter
            if !beacon.connect(Self.password, timeout: 15, delegate: self) {
                connectWaiter = nil
                waiter.resume(throwing: SetupError.connectionFailed)
            }
        }
        phase = .writing
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            beacon.modifyConfig(obj: config) { ok, _ in
                if ok { waiter.resume() } else { waiter.resume(throwing: SetupError.writeFailed) }
            }
        }
    }
}

// MARK: - SDK delegates (delivered on the main queue)

extension BlueCharm: KBeaconMgrDelegate, ConnStateDelegate {
    nonisolated func onBeaconDiscovered(beacons: [KBeacon]) {
        MainActor.assumeIsolated {
            for beacon in beacons {
                guard let id = beacon.uuidString else { continue }
                seen[id] = beacon
                if id == signalPeripheralID, !isBusy {
                    signalRSSI = Int(beacon.rssi)
                    signalHeardAt = .now
                }
            }
        }
    }

    nonisolated func onCentralBleStateChange(newState: BLECentralMgrState) {
        MainActor.assumeIsolated {
            if newState == .PowerOn { resumeSignalScan() }
            guard newState != .Unknown, let waiter = bluetoothWaiter else { return }
            bluetoothWaiter = nil
            waiter.resume()
        }
    }

    nonisolated func onConnStateChange(_ beacon: KBeacon, state: KBConnState, evt: KBConnEvtReason) {
        MainActor.assumeIsolated {
            guard let waiter = connectWaiter else { return }
            switch state {
            case .Connected:
                connectWaiter = nil
                waiter.resume()
            case .Disconnected:
                connectWaiter = nil
                waiter.resume(throwing: evt == .ConnAuthFail ? SetupError.passwordChanged : SetupError.connectionFailed)
            default:
                break
            }
        }
    }
}

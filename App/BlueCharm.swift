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
        /// Connected after a range change, waiting a moment in case another tap follows.
        case holding
        case failed(String)
    }

    @Published private(set) var phase = Phase.idle
    /// Live signal (dBm) from the paired beacon while the app is open; nil when not heard in
    /// the last few seconds. Display only, like BeaconSignal: blocking still follows RoomMonitor.
    @Published private(set) var signalRSSI: Int?
    /// The range step the user last tapped, while it's on its way to the beacon (see requestPower).
    @Published private(set) var targetPower: Int?
    /// True while a range change is talking to the beacon, including the brief hold afterwards.
    private var tuning = false
    /// How long to stay connected after a range change for another tap.
    private static let holdOpen: TimeInterval = 2

    var isBusy: Bool {
        switch phase {
        case .searching, .connecting, .writing, .holding: return true
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
    /// When the current scan started, so "not heard" can count from it.
    private var signalScanStartedAt: Date?
    /// The last time a stuck "in the bedroom" was re-checked (see checkRoom).
    private var lastRoomRecheck: Date?
    private var loggedDisagreement = false

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

    /// Moves the paired beacon's range to `dBm`. Returns at once so the buttons can keep up:
    /// `targetPower` shows the new step straight away, and taps that arrive while a change is on
    /// its way just move the target. One connection carries them all and stays open a moment for
    /// the next tap, so tapping Longer three times is one connect and up to three quick writes,
    /// not three rounds of scan, connect, write. `onWritten` runs after each write the beacon accepts.
    func requestPower(_ dBm: Int, for pairing: BlueCharmPairing, onWritten: @escaping (BlueCharmPairing) -> Void) {
        if tuning {
            targetPower = dBm
            return
        }
        // Setup is running; leave it alone.
        guard !isBusy else { return }
        targetPower = dBm
        tuning = true
        Task {
            _ = await run { [self] in try await tune(pairing, onWritten: onWritten) }
            tuning = false
            targetPower = nil
        }
    }

    private func tune(_ pairing: BlueCharmPairing, onWritten: (BlueCharmPairing) -> Void) async throws {
        // The Signal row's scan has usually just heard the beacon, so skip the search.
        let beacon: KBeacon
        if let heard = signalHeardAt, Date.now.timeIntervalSince(heard) < 4,
           signalPeripheralID == pairing.peripheralID, let known = seen[pairing.peripheralID] {
            try await bluetoothReady()
            manager.stopScanning()
            beacon = known
        } else {
            beacon = try await nearestBeacon(peripheralID: pairing.peripheralID)
        }
        // Only what a range change needs: skip reading the trigger settings.
        let para = KBConnPara()
        para.readTriggerPara = false
        try await connect(beacon, para: para)
        defer { beacon.disconnect() }
        var written = pairing
        var quietSince = Date.now
        while true {
            if let target = targetPower, target != written.txPower {
                phase = .writing
                let config = KBCfgAdvIBeacon()
                config.setSlotIndex(0)
                config.setTxPower(target)
                try await modify(config, on: beacon)
                written.txPower = target
                onWritten(written)
                Shared.log("Beacon range set to \(target) dBm")
                quietSince = .now
                continue
            }
            // Connected, the beacon isn't broadcasting, so don't hold on long.
            phase = .holding
            guard Date.now.timeIntervalSince(quietSince) < Self.holdOpen else { return }
            try await Task.sleep(for: .milliseconds(100))
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
        signalScanStartedAt = nil
        signalRSSI = nil
        guard id != nil else { return }
        signalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                // The beacon advertises several times a second; a few quiet seconds means not heard.
                if let heard = self.signalHeardAt, Date.now.timeIntervalSince(heard) > 4 {
                    self.signalRSSI = nil
                }
                self.checkRoom()
            }
        }
        resumeSignalScan()
    }

    private func resumeSignalScan() {
        guard signalPeripheralID != nil, !isBusy else { return }
        manager.delegate = self
        manager.cbBeaconMgr.delegate = manager
        // If Bluetooth isn't on yet, onCentralBleStateChange calls this again.
        if manager.cbBeaconMgr.state == .poweredOn, manager.startScanning() {
            signalScanStartedAt = .now
        }
    }

    /// On a real night CLMonitor kept saying "in the bedroom" for 15+ minutes after the Blue
    /// Charm was unplugged, app open, while this scan heard nothing. So when the scan hasn't
    /// heard the paired beacon for a minute and Status still says in the room, RoomMonitor drops
    /// CLMonitor's answer and watches again from "outside"; if the beacon is really there, iOS
    /// reports it again within seconds. One re-check per stretch of silence: if iOS says "in"
    /// again while the scan still hears nothing, the scan is the one that's wrong, so leave it.
    private func checkRoom() {
        guard let id = signalPeripheralID, !isBusy, let started = signalScanStartedAt else { return }
        // Silence counts from the later of the last packet and this scan's start (it restarts
        // after each range change, when the beacon was just connected and so certainly there).
        let since = max(started, signalHeardAt ?? started)
        guard Date.now.timeIntervalSince(since) > 60,
              Shared.inRoom, Shared.pairedBlueCharm?.peripheralID == id else { return }
        if let lastRoomRecheck, since < lastRoomRecheck {
            // Logged once so the Activity list shows which side to doubt.
            if !loggedDisagreement, Date.now.timeIntervalSince(lastRoomRecheck) > 60 {
                loggedDisagreement = true
                Shared.log("iOS still reports the beacon, but Bluetooth doesn't hear it")
            }
            return
        }
        lastRoomRecheck = .now
        Task { await RoomMonitor.shared.recheck() }
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
        try await connect(beacon)
        defer { beacon.disconnect() }
        phase = .writing
        try await modify(config, on: beacon)
    }

    private func connect(_ beacon: KBeacon, para: KBConnPara = KBConnPara()) async throws {
        phase = .connecting
        // A disconnect from the last change may still be finishing; the SDK won't connect until it has.
        for _ in 0..<30 where beacon.state != .Disconnected {
            try await Task.sleep(for: .milliseconds(100))
        }
        do {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                connectWaiter = waiter
                if !beacon.connectEnhanced(Self.password, timeout: 15, connPara: para, delegate: self) {
                    connectWaiter = nil
                    waiter.resume(throwing: SetupError.connectionFailed)
                }
            }
        } catch {
            beacon.disconnect()
            throw error
        }
    }

    private func modify(_ config: KBCfgAdvIBeacon, on beacon: KBeacon) async throws {
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
            if newState == .PowerOn {
                resumeSignalScan()
            } else {
                // Not scanning, so silence from here on says nothing about the beacon.
                signalScanStartedAt = nil
                signalHeardAt = nil
            }
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

import Foundation

// Pure in/out-of-room logic for the spare-device stand-in (HubMonitor). No CoreBluetooth here,
// so the unit tests compile this folder directly without the app.

/// Turns the one boundary you set at the bedroom door into separate enter and leave thresholds.
enum RoomCalibration {
    /// Entering needs a signal this much stronger than the door, so you're clearly inside.
    static let enterMargin = 3
    /// Leaving needs it this much weaker, so a weak moment by the bed doesn't count as leaving.
    static let leaveMargin = 5
    /// Readings taken at the door to set the boundary.
    static let sampleCount = 5

    struct Thresholds: Equatable {
        var enter: Int   // in the room once the median is at least this
        var leave: Int   // out of the room once it's at or below this
    }

    /// The boundary is the median of the door readings, so one odd reading can't skew it.
    static func boundary(doorSamples: [Int]) -> Int? {
        RoomPresenceStateMachine.median(doorSamples.filter(RoomPresenceStateMachine.isValid))
    }

    static func thresholds(boundary: Int) -> Thresholds {
        Thresholds(enter: boundary + enterMargin, leave: boundary - leaveMargin)
    }
}

/// Decides in or out of the room from timestamped signal-strength readings.
///
/// Bluetooth signal strength swings 5–10 dB from one reading to the next, so three layers keep
/// this from flapping: the median of the last few readings, separate enter and leave thresholds,
/// and dwell time (the new state has to hold continuously before it counts). Leaving is slower
/// than entering on purpose: wrongly deciding you've left lifts the block.
///
/// Readings arrive every 2 seconds during bedtime hours (the stand-in's heartbeat) and every
/// second while the app is open.
struct RoomPresenceStateMachine {
    struct Timing: Equatable {
        var enterDwell: TimeInterval = 6
        var leaveDwell: TimeInterval = 20
        /// Readings older than this (e.g. from before bedtime hours) aren't mixed with new ones.
        var staleAfter: TimeInterval = 10
        /// With no readings at all for this long, you count as out of range.
        var gapTimeout: TimeInterval = 30
        var window = 5
        /// Readings needed before any decision, so one lucky reading can't switch the state.
        var minimumSamples = 3
    }

    enum Transition: Equatable { case entered, left }

    var thresholds: RoomCalibration.Thresholds?
    let timing: Timing
    private(set) var inRoom: Bool
    private(set) var samples: [Int] = []
    private var lastSampleAt: Date?
    private var candidateSince: Date?

    init(inRoom: Bool, thresholds: RoomCalibration.Thresholds?, timing: Timing = Timing()) {
        self.inRoom = inRoom
        self.thresholds = thresholds
        self.timing = timing
    }

    /// iOS reports 127 when it couldn't measure the signal this time.
    static func isValid(_ rssi: Int) -> Bool { rssi < 0 }

    /// The middle reading (the stronger of the middle two for an even count).
    static func median(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    /// The smoothed signal in dBm, for display.
    var smoothedRSSI: Int? { Self.median(samples) }

    /// Feeds one reading. Returns a transition when the state switches.
    mutating func add(rssi: Int, at time: Date) -> Transition? {
        guard Self.isValid(rssi) else { return tick(at: time) }
        // A long silence means you were out of range, even if nothing called tick() meanwhile.
        let gapLeave = tick(at: time)
        if let lastSampleAt, time.timeIntervalSince(lastSampleAt) > timing.staleAfter {
            samples = []
            candidateSince = nil
        }
        lastSampleAt = time
        samples.append(rssi)
        if samples.count > timing.window { samples.removeFirst(samples.count - timing.window) }
        return gapLeave ?? evaluate(at: time)
    }

    /// Call when there's no new reading: leaves once readings have stopped for `gapTimeout`.
    mutating func tick(at time: Date) -> Transition? {
        guard inRoom, let lastSampleAt, time.timeIntervalSince(lastSampleAt) >= timing.gapTimeout
        else { return nil }
        samples = []
        return switchTo(false)
    }

    /// Drops the readings (reconnecting, bedtime hours over) but keeps the in/out state.
    mutating func forgetReadings() {
        samples = []
        lastSampleAt = nil
        candidateSince = nil
    }

    /// Adopts a state decided elsewhere (e.g. Bluetooth turned off) without dropping the readings.
    mutating func sync(inRoom: Bool) {
        guard self.inRoom != inRoom else { return }
        self.inRoom = inRoom
        candidateSince = nil
    }

    private mutating func evaluate(at time: Date) -> Transition? {
        guard let thresholds, samples.count >= timing.minimumSamples,
              let rssi = smoothedRSSI else { return nil }

        let wantsIn = inRoom ? rssi > thresholds.leave : rssi >= thresholds.enter
        guard wantsIn != inRoom else {
            candidateSince = nil
            return nil
        }
        let since = candidateSince ?? time
        candidateSince = since
        let dwell = wantsIn ? timing.enterDwell : timing.leaveDwell
        guard time.timeIntervalSince(since) >= dwell else { return nil }
        return switchTo(wantsIn)
    }

    private mutating func switchTo(_ newValue: Bool) -> Transition {
        inRoom = newValue
        candidateSince = nil
        return newValue ? .entered : .left
    }
}

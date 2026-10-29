import XCTest

final class RoomPresenceTests: XCTestCase {
    /// The boundary from the flapping report: set at the bedroom door, iPhone reading about −40 by the hub.
    private let boundary = -47
    private var thresholds: RoomCalibration.Thresholds { RoomCalibration.thresholds(boundary: boundary) }
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    /// The stand-in's bedtime heartbeat.
    private let heartbeat: TimeInterval = 2

    /// Feeds readings `interval` apart and returns each transition with its time offset.
    private func run(
        _ machine: inout RoomPresenceStateMachine,
        _ readings: [Int],
        from offset: TimeInterval = 0,
        every interval: TimeInterval? = nil
    ) -> [(RoomPresenceStateMachine.Transition, TimeInterval)] {
        let interval = interval ?? heartbeat
        var transitions: [(RoomPresenceStateMachine.Transition, TimeInterval)] = []
        for (i, rssi) in readings.enumerated() {
            let t = offset + TimeInterval(i) * interval
            if let transition = machine.add(rssi: rssi, at: start.addingTimeInterval(t)) {
                transitions.append((transition, t))
            }
        }
        return transitions
    }

    /// Deterministic noise so failures reproduce.
    private func noisy(around center: Int, amplitude: Int, count: Int, seed: UInt64 = 42) -> [Int] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return center + Int((state >> 33) % UInt64(2 * amplitude + 1)) - amplitude
        }
    }

    /// The logic that flapped in the report: average of the last 4, ±2 dB, no dwell.
    private func averageOf4TransitionCount(_ readings: [Int]) -> Int {
        var samples: [Int] = [], inRoom = false, count = 0
        for value in readings {
            samples.append(value)
            if samples.count > 4 { samples.removeFirst() }
            guard samples.count == 4 else { continue }
            let average = samples.reduce(0, +) / 4
            if inRoom, average < boundary - 2 { inRoom = false; count += 1 }
            else if !inRoom, average >= boundary + 2 { inRoom = true; count += 1 }
        }
        return count
    }

    /// Median of 5 with one ±3 dB margin and no dwell: steadier, but a 3-reading dip still flips it.
    private func medianOf5TransitionCount(_ readings: [Int]) -> Int {
        var samples: [Int] = [], inRoom = false, count = 0
        for value in readings {
            samples.append(value)
            if samples.count > 5 { samples.removeFirst() }
            guard samples.count >= 3 else { continue }
            let median = samples.sorted()[samples.count / 2]
            if inRoom, median < boundary - 3 { inRoom = false; count += 1 }
            else if !inRoom, median >= boundary + 3 { inRoom = true; count += 1 }
        }
        return count
    }

    /// Resembles the iPhone log from 22:09:52 to 22:10:43 (a reading a second): about −40 next to
    /// the hub with short 10–15 dB dips, which entered and left three times each in under a minute.
    private let loggedReplay: [Int] = [
        -41, -39, -40, -42, -38, -40, -55, -54, -56, -40,
        -39, -41, -43, -40, -38, -40, -52, -57, -53, -41,
        -40, -39, -38, -42, -40, -41, -54, -56, -55, -39,
        -40, -42, -41, -39, -40, -38, -40, -41, -50, -40,
        -39, -43, -40, -41, -42, -38, -40, -39, -41, -40,
        -40, -39,
    ]

    /// Lying in bed at bedtime (a reading every 2 s) with a few 6-second dips, e.g. rolling over.
    private let bedtimeDips: [Int] = [
        -40, -41, -39, -55, -56, -54, -40, -39, -41, -40,
        -53, -57, -55, -41, -40, -39, -42, -40, -56, -54,
        -55, -40, -41, -40, -39, -41,
    ]

    // MARK: - No flapping

    func testNoisySignalNearHubNeverFlaps() {
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        let transitions = run(&machine, noisy(around: -40, amplitude: 10, count: 300))
        XCTAssertLessThanOrEqual(transitions.filter { $0.0 == .entered }.count, 1)
        XCTAssertEqual(transitions.filter { $0.0 == .left }.count, 0)
        XCTAssertTrue(machine.inRoom)
    }

    func testLoggedReplayProducesAtMostOneTransition() {
        XCTAssertGreaterThanOrEqual(averageOf4TransitionCount(loggedReplay), 4, "replay should flap under the reported logic")
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        let transitions = run(&machine, loggedReplay, every: 1)
        XCTAssertLessThanOrEqual(transitions.count, 1)
        XCTAssertTrue(transitions.allSatisfy { $0.0 == .entered })

        var alreadyIn = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        XCTAssertTrue(run(&alreadyIn, loggedReplay, every: 1).isEmpty)
    }

    func testShortDipsAtBedtimeDontLeave() {
        XCTAssertGreaterThanOrEqual(medianOf5TransitionCount(bedtimeDips), 4, "dips should flap without hysteresis and dwell")
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        XCTAssertEqual(run(&machine, bedtimeDips).map(\.0), [.entered])
        XCTAssertTrue(machine.inRoom)
    }

    // MARK: - Real changes

    func testEnterWaitsForDwell() {
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        let transitions = run(&machine, Array(repeating: -40, count: 15))
        XCTAssertEqual(transitions.map(\.0), [.entered])
        // 3 readings to decide anything, then the dwell: about 10 s at bedtime.
        XCTAssertGreaterThanOrEqual(transitions[0].1, machine.timing.enterDwell)
        XCTAssertLessThanOrEqual(transitions[0].1, machine.timing.enterDwell + 3 * heartbeat)
    }

    func testWalkingOutLeavesOnceAfterDwell() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        let readings = noisy(around: -40, amplitude: 5, count: 15) + noisy(around: -62, amplitude: 5, count: 40, seed: 7)
        let transitions = run(&machine, readings)
        XCTAssertEqual(transitions.map(\.0), [.left])
        // Dropped at 30 s; the median takes 3 readings to follow, then the leave dwell.
        XCTAssertGreaterThanOrEqual(transitions[0].1, 30 + machine.timing.leaveDwell)
        XCTAssertLessThanOrEqual(transitions[0].1, 30 + machine.timing.leaveDwell + 3 * heartbeat)
        XCTAssertFalse(machine.inRoom)
    }

    func testDipShorterThanLeaveDwellStaysInRoom() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        // 16 s at −65, as if stepping into the hallway for a moment.
        let readings = Array(repeating: -40, count: 10) + Array(repeating: -65, count: 8) + Array(repeating: -40, count: 15)
        XCTAssertTrue(run(&machine, readings).isEmpty)
        XCTAssertTrue(machine.inRoom)
    }

    func testStandingAtDoorHoldsEitherState() {
        let steady = noisy(around: boundary, amplitude: 2, count: 300)
        var outside = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        var inside = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        XCTAssertTrue(run(&outside, steady).isEmpty)
        XCTAssertTrue(run(&inside, steady).isEmpty)
    }

    func testStandingAtDoorNeverFlipsBack() {
        // Swings reaching the enter line can count as walking in once, but never back out.
        let swinging = noisy(around: boundary, amplitude: 3, count: 300)
        for start in [false, true] {
            var machine = RoomPresenceStateMachine(inRoom: start, thresholds: thresholds)
            XCTAssertLessThanOrEqual(run(&machine, swinging).count, 1)
        }
    }

    func testNothingHappensUntilBoundaryIsSet() {
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: nil)
        XCTAssertTrue(run(&machine, Array(repeating: -35, count: 30)).isEmpty)
        machine.thresholds = thresholds
        XCTAssertEqual(run(&machine, Array(repeating: -35, count: 10), from: 60).map(\.0), [.entered])
    }

    func testSyncAdoptsOutsideStateAndReentersAfterDwell() {
        var machine = RoomPresenceStateMachine(inRoom: false, thresholds: thresholds)
        _ = run(&machine, Array(repeating: -40, count: 10))
        machine.sync(inRoom: false)   // e.g. Bluetooth turned off
        let transitions = run(&machine, Array(repeating: -40, count: 10), from: 20)
        XCTAssertEqual(transitions.map(\.0), [.entered])
        XCTAssertGreaterThanOrEqual(transitions[0].1, 20 + machine.timing.enterDwell)
    }

    // MARK: - Gaps

    func testSilenceLeavesOnlyAfterTimeout() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        _ = run(&machine, Array(repeating: -40, count: 10))   // last reading at 18 s
        let timeout = machine.timing.gapTimeout
        XCTAssertNil(machine.tick(at: start.addingTimeInterval(18 + timeout - 1)))
        XCTAssertEqual(machine.tick(at: start.addingTimeInterval(18 + timeout)), .left)
        XCTAssertNil(machine.tick(at: start.addingTimeInterval(18 + timeout + 10)))
    }

    func testReadingAfterLongGapCountsAsHavingLeft() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        _ = run(&machine, Array(repeating: -40, count: 10))
        XCTAssertEqual(machine.add(rssi: -40, at: start.addingTimeInterval(120)), .left)
        // Old readings were dropped, so getting back in needs fresh readings and the enter dwell.
        XCTAssertEqual(machine.samples, [-40])
        XCTAssertNil(machine.add(rssi: -40, at: start.addingTimeInterval(122)))
    }

    func testStaleReadingsAreDroppedWithoutLeaving() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        _ = run(&machine, [-40, -41, -39, -40, -42])
        XCTAssertNil(machine.add(rssi: -45, at: start.addingTimeInterval(8 + 12)))
        XCTAssertEqual(machine.samples, [-45])
        XCTAssertTrue(machine.inRoom)
    }

    func testInvalidReadingsAreIgnored() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        let readings = (0..<40).map { $0.isMultiple(of: 2) ? 127 : -40 }
        XCTAssertTrue(run(&machine, readings).isEmpty)
        XCTAssertEqual(machine.smoothedRSSI, -40)
    }

    // MARK: - Smoothing

    func testMedianRejectsSingleOutliers() {
        var machine = RoomPresenceStateMachine(inRoom: true, thresholds: thresholds)
        _ = run(&machine, [-40, -41, -80, -39, -40])
        XCTAssertEqual(machine.smoothedRSSI, -40)
        _ = run(&machine, [-10], from: 10)
        XCTAssertEqual(machine.smoothedRSSI, -40)
        XCTAssertEqual(machine.samples.count, machine.timing.window)
    }

    // MARK: - Calibration

    func testCalibrationUsesMedianOfDoorReadings() {
        XCTAssertEqual(RoomCalibration.boundary(doorSamples: [-47, -46, -60, -48, -47]), -47)
        XCTAssertEqual(RoomCalibration.boundary(doorSamples: [-47, -46, -60, -48, 127]), -47)   // 127 = unmeasured
        XCTAssertNil(RoomCalibration.boundary(doorSamples: [127]))
    }

    func testThresholdsBracketTheBoundary() {
        let t = RoomCalibration.thresholds(boundary: -47)
        XCTAssertEqual(t, RoomCalibration.Thresholds(enter: -44, leave: -52))
        XCTAssertEqual(t.enter - t.leave, RoomCalibration.enterMargin + RoomCalibration.leaveMargin)
    }
}

import XCTest

final class BedtimeScheduleTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday 30 October 2026 (Saturday is the 31st, Sunday 1 November) at the given time, UTC.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let month = day > 31 ? 11 : 10
        let parts = DateComponents(year: 2026, month: month, day: day > 31 ? day - 31 : day, hour: hour, minute: minute)
        return calendar.date(from: parts)!
    }

    private let friday = 6, saturday = 7, sunday = 1

    func testUsualHoursEveryNight() {
        let schedule = BedtimeSchedule()   // 9 PM – 7 AM
        XCTAssertTrue(schedule.contains(at(30, 21), calendar: calendar), "start is inclusive")
        XCTAssertTrue(schedule.contains(at(31, 3), calendar: calendar))
        XCTAssertFalse(schedule.contains(at(31, 7), calendar: calendar), "end is exclusive")
        XCTAssertFalse(schedule.contains(at(30, 20, 59), calendar: calendar))
        XCTAssertFalse(schedule.contains(at(30, 12), calendar: calendar))
    }

    func testNightOffBelongsToTheDayItStarts() {
        var schedule = BedtimeSchedule()
        schedule.nights[friday - 1] = .off
        XCTAssertTrue(schedule.contains(at(30, 3), calendar: calendar), "Thursday night still runs into Friday morning")
        XCTAssertFalse(schedule.contains(at(30, 22), calendar: calendar), "Friday night is off")
        XCTAssertFalse(schedule.contains(at(31, 3), calendar: calendar), "including Saturday morning")
        XCTAssertTrue(schedule.contains(at(31, 22), calendar: calendar), "Saturday night is back to usual")
    }

    func testDifferentHoursForOneNight() {
        var schedule = BedtimeSchedule()
        schedule.nights[saturday - 1] = .hours(start: 23 * 60, end: 9 * 60)
        XCTAssertFalse(schedule.contains(at(31, 22), calendar: calendar))
        XCTAssertTrue(schedule.contains(at(31, 23), calendar: calendar))
        XCTAssertTrue(schedule.contains(at(32, 8), calendar: calendar), "Saturday night runs to 9 on Sunday")
        XCTAssertFalse(schedule.contains(at(32, 9), calendar: calendar))
        XCTAssertTrue(schedule.contains(at(32, 21), calendar: calendar), "Sunday is on usual hours")
        XCTAssertFalse(schedule.contains(at(31, 7, 30), calendar: calendar), "Friday night still ends at 7")
    }

    func testDaytimeHoursDontCrossMidnight() {
        var schedule = BedtimeSchedule()
        schedule.nights[sunday - 1] = .hours(start: 13 * 60, end: 15 * 60)
        XCTAssertTrue(schedule.contains(at(32, 14), calendar: calendar))
        XCTAssertFalse(schedule.contains(at(32, 21), calendar: calendar))
        XCTAssertFalse(schedule.contains(at(33, 3), calendar: calendar), "nothing carries into Monday morning")
    }

    func testEqualStartAndEndLastsADay() {
        var schedule = BedtimeSchedule()
        schedule.startMinutes = 21 * 60
        schedule.endMinutes = 21 * 60
        XCTAssertTrue(schedule.contains(at(30, 12), calendar: calendar), "every night 24 hours = any time")
        schedule.nights[friday - 1] = .off
        XCTAssertTrue(schedule.contains(at(30, 20), calendar: calendar), "Thursday's 24 hours")
        XCTAssertFalse(schedule.contains(at(30, 21), calendar: calendar))
        XCTAssertFalse(schedule.contains(at(31, 20), calendar: calendar))
        XCTAssertTrue(schedule.contains(at(31, 21), calendar: calendar))
    }

    func testAnyTimeIgnoresNights() {
        var schedule = BedtimeSchedule()
        schedule.limitToHours = false
        schedule.nights = Array(repeating: .off, count: 7)
        XCTAssertTrue(schedule.contains(at(30, 12), calendar: calendar))
        XCTAssertEqual(schedule.boundaries, [])
    }

    func testBoundariesCoverEveryNight() {
        var schedule = BedtimeSchedule()
        XCTAssertEqual(schedule.boundaries, [21 * 60, 7 * 60])
        schedule.nights[saturday - 1] = .hours(start: 23 * 60, end: 9 * 60)
        schedule.nights[friday - 1] = .off
        XCTAssertEqual(schedule.boundaries, [21 * 60, 7 * 60, 23 * 60, 9 * 60])
        schedule.nights = Array(repeating: .off, count: 7)
        XCTAssertEqual(schedule.boundaries, [])
    }

    func testCurrentNight() {
        var schedule = BedtimeSchedule()
        schedule.startMinutes = 22 * 60
        schedule.endMinutes = 6 * 60
        schedule.nights[friday - 1] = .off
        XCTAssertNotNil(schedule.currentNight(at: at(30, 3), calendar: calendar), "still Thursday night")
        XCTAssertNil(schedule.currentNight(at: at(30, 12), calendar: calendar), "tonight is off")
        XCTAssertNotNil(schedule.currentNight(at: at(31, 12), calendar: calendar))
    }

    func testSchedulesSavedBeforePerNightHours() throws {
        let saved = #"{"limitToHours":true,"startMinutes":1320,"endMinutes":360}"#
        let schedule = try JSONDecoder().decode(BedtimeSchedule.self, from: Data(saved.utf8))
        XCTAssertEqual(schedule.startMinutes, 22 * 60)
        XCTAssertEqual(schedule.endMinutes, 6 * 60)
        XCTAssertEqual(schedule.nights, Array(repeating: .usual, count: 7))
    }

    func testRoundTrip() throws {
        var schedule = BedtimeSchedule()
        schedule.nights[friday - 1] = .off
        schedule.nights[saturday - 1] = .hours(start: 23 * 60, end: 9 * 60)
        let decoded = try JSONDecoder().decode(BedtimeSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(decoded, schedule)
    }
}

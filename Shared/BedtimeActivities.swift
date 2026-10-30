import Foundation
import DeviceActivity

extension DeviceActivityName {
    fileprivate static let bedtimePrefix = "goodnightphone.bedtime."

    /// A daily wake-up at one of the schedule's start or end times.
    fileprivate static func bedtime(atMinutes minutes: Int) -> Self {
        Self(bedtimePrefix + String(minutes))
    }

    /// Ours, but not the test block's: the per-time wake-ups, plus the start/end pair used
    /// before per-night hours.
    var isBedtime: Bool {
        rawValue.hasPrefix(Self.bedtimePrefix)
            || rawValue == "goodnightphone.bedtimeStart" || rawValue == "goodnightphone.bedtimeEnd"
    }
}

/// Wakes the DeviceActivity extension at the start and end of bedtime hours,
/// so blocking turns on at 9 PM even if you're already lying in bed.
///
/// Rather than one long overnight interval, each start or end time across the week gets its own
/// short daily window that begins (or ends) exactly at that time. The extension just calls
/// `Blocker.refresh` on every callback, which reads the wall clock and the night of the week, so
/// the result is correct no matter which callback fires, including on nights that are off or
/// have other hours.
enum BedtimeActivities {
    private static let windowMinutes = 20   // DeviceActivity requires at least 15

    static func syncIfNeeded() {
        let schedule = Shared.schedule
        if Shared.syncedSchedule != schedule { sync(schedule) }
    }

    static func sync(_ schedule: BedtimeSchedule) {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter(\.isBedtime))
        Shared.syncedSchedule = schedule

        do {
            // At most 14 times (7 nights × start and end), within DeviceActivity's limit of 20.
            for minutes in schedule.boundaries.sorted() {
                try center.startMonitoring(.bedtime(atMinutes: minutes), during: wakeWindow(at: minutes))
            }
            if schedule.limitToHours {
                Shared.log("Bedtime hours set to \(schedule.summary)")
            }
        } catch {
            Shared.syncedSchedule = nil   // retry next time the app opens
            Shared.log("Couldn't schedule bedtime hours: \(error.localizedDescription)")
        }
    }

    /// A short window that starts at `minutes`, or ends at it if starting would cross midnight.
    private static func wakeWindow(at minutes: Int) -> DeviceActivitySchedule {
        let (start, end) = minutes + windowMinutes < 24 * 60
            ? (minutes, minutes + windowMinutes)
            : (minutes - windowMinutes, minutes)
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: start / 60, minute: start % 60),
            intervalEnd: DateComponents(hour: end / 60, minute: end % 60),
            repeats: true
        )
    }
}

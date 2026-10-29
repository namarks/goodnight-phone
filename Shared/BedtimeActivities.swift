import Foundation
import DeviceActivity

extension DeviceActivityName {
    static let bedtimeStart = Self("lightsout.bedtimeStart")
    static let bedtimeEnd = Self("lightsout.bedtimeEnd")
}

/// Wakes the DeviceActivity extension at the start and end of bedtime hours,
/// so blocking turns on at 9 PM even if you're already lying in bed.
///
/// Rather than one long overnight interval, each boundary gets its own short
/// same-day window that begins (or ends) exactly at the boundary. The extension
/// just calls `Blocker.refresh` on every callback, which reads the wall clock,
/// so the result is correct no matter which callback fires.
enum BedtimeActivities {
    private static let windowMinutes = 20   // DeviceActivity requires at least 15

    static func syncIfNeeded() {
        let schedule = Shared.schedule
        if Shared.syncedSchedule != schedule { sync(schedule) }
    }

    static func sync(_ schedule: BedtimeSchedule) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.bedtimeStart, .bedtimeEnd])
        Shared.syncedSchedule = schedule

        guard schedule.limitToHours, schedule.startMinutes != schedule.endMinutes else { return }
        do {
            try center.startMonitoring(.bedtimeStart, during: wakeWindow(at: schedule.startMinutes))
            try center.startMonitoring(.bedtimeEnd, during: wakeWindow(at: schedule.endMinutes))
            Shared.log("Bedtime hours set to \(schedule.summary)")
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

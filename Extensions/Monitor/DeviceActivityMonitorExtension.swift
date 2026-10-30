import DeviceActivity
import Foundation

/// Woken by the system at the start and end of bedtime hours (see BedtimeActivities).
/// It doesn't decide anything itself: Blocker re-reads "in the bedroom?" and the clock.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Blocker.refresh(reason: reason(for: activity))
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Blocker.refresh(reason: reason(for: activity))
    }

    private func reason(for activity: DeviceActivityName) -> String {
        if activity == .testBlock { return "test ended" }
        // Each wake-up is shared by every night with that time, so ask the clock which it was.
        if activity.isBedtime { return Shared.schedule.contains(.now) ? "bedtime started" : "bedtime ended" }
        return "schedule check"
    }
}

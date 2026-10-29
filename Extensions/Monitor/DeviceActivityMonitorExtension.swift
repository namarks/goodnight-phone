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
        switch activity {
        case .bedtimeStart: return "bedtime started"
        case .bedtimeEnd: return "bedtime ended"
        case .testBlock: return "test ended"
        default: return "schedule check"
        }
    }
}

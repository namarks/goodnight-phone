import DeviceActivity
import Foundation

extension DeviceActivityName {
    static let testBlock = Self("goodnightphone.testBlock")
}

/// "Try it now": blocks the chosen apps for a couple of minutes without a beacon,
/// so new users (and App Review) can see the shield before the bedroom is set up.
/// Like the real thing, it can't be cancelled early. It only ever adds a block.
enum TestBlock {
    static let duration: TimeInterval = 2 * 60

    static var endsAt: Date? {
        guard let end = Shared.testBlockUntil, end > .now else { return nil }
        return end
    }

    static func start(now: Date = .now) {
        let end = now.addingTimeInterval(duration)
        Shared.testBlockUntil = end

        // Wakes the Monitor extension when the test ends, so the shield lifts even with
        // the app closed. DeviceActivity needs a window of at least 15 minutes, so this one
        // started in the past and ends when the test does.
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let window = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: end.addingTimeInterval(-16 * 60)),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        let center = DeviceActivityCenter()
        center.stopMonitoring([.testBlock])
        do {
            try center.startMonitoring(.testBlock, during: window)
        } catch {
            // The block still lifts the next time Goodnight Phone opens.
            Shared.log("Couldn't schedule the end of the test: \(error.localizedDescription)")
        }
        Blocker.refresh(reason: "test started")
    }
}

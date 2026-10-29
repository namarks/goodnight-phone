import FamilyControls
import Foundation

/// UI-facing view of the shared state. All writes go through here so the
/// shield, the bedtime schedule and the beacon monitor stay in sync.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var selection = FamilyActivitySelection()
    @Published private(set) var schedule = BedtimeSchedule()
    @Published private(set) var beacon: BeaconConfig?
    @Published private(set) var inRoom = false
    @Published private(set) var isBlocking = false
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var screenTimeApproved = false

    private var scheduleTask: Task<Void, Never>?

    private init() { reload() }

    func reload() {
        selection = Shared.selection
        schedule = Shared.schedule
        beacon = Shared.beacon
        inRoom = Shared.inRoom
        isBlocking = Shared.isBlocking
        log = Shared.logEntries.reversed()
        screenTimeApproved = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Settings are locked while apps are blocked — leaving the room is the only off switch.
    var isLocked: Bool { isBlocking && screenTimeApproved }

    var isInBedtimeHours: Bool { schedule.contains(.now) }

    // MARK: - Actions

    func requestScreenTime() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            BedtimeActivities.syncIfNeeded()
            Blocker.refresh(reason: "Screen Time access granted")
        } catch {
            Shared.log("Screen Time access not granted: \(error.localizedDescription)")
        }
        reload()
    }

    func saveSelection(_ newValue: FamilyActivitySelection) {
        Shared.selection = newValue
        Blocker.refresh(reason: "blocked apps changed")
        reload()
    }

    /// Saves immediately; re-registers the DeviceActivity schedule after the user stops scrolling.
    func saveSchedule(_ newValue: BedtimeSchedule) {
        guard newValue != schedule else { return }
        Shared.schedule = newValue
        schedule = newValue
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if AuthorizationCenter.shared.authorizationStatus == .approved {
                BedtimeActivities.sync(newValue)
            }
            Blocker.refresh(reason: "bedtime hours changed")
            self?.reload()
        }
    }

    func saveBeacon(_ newValue: BeaconConfig?) {
        Shared.beacon = newValue
        beacon = newValue
        Task {
            await RoomMonitor.shared.syncCondition()
            reload()
        }
    }

    /// Called when the app comes to the foreground.
    func refreshEverything() async {
        RoomMonitor.shared.start()   // no-op if already running
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            BedtimeActivities.syncIfNeeded()
        }
        await RoomMonitor.shared.refreshFromSystem()
        Blocker.refresh(reason: "status check")
        reload()
    }
}

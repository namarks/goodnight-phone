import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// One named store, shared by the app and its extensions.
    static let bedroom = Self("bedroom")
}

/// The single source of truth for "should apps be blocked right now?"
///
/// Blocking = in the bedroom AND inside bedtime hours AND something is selected.
/// It recomputes from shared state every time, so calling it extra times is harmless.
/// The app calls it on beacon enter/exit; the DeviceActivity extension calls it when
/// bedtime hours start and end.
enum Blocker {
    private static let store = ManagedSettingsStore(named: .bedroom)

    @discardableResult
    static func refresh(reason: String, now: Date = .now) -> Bool {
        let selection = Shared.selection
        let shouldBlock = Shared.inRoom
            && Shared.schedule.contains(now)
            && !selection.isEmptySelection

        if shouldBlock {
            let apps = selection.applicationTokens
            let categories = selection.categoryTokens
            let sites = selection.webDomainTokens
            store.shield.applications = apps.isEmpty ? nil : apps
            store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
            store.shield.webDomains = sites.isEmpty ? nil : sites
            store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        } else {
            store.clearAllSettings()
        }

        if Shared.isBlocking != shouldBlock {
            Shared.log(shouldBlock ? "Blocking on — \(reason)" : "Blocking off — \(reason)")
        }
        Shared.isBlocking = shouldBlock
        return shouldBlock
    }
}

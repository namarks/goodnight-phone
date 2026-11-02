import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// The first named store, shared by the app and its extensions. It holds the categories
    /// and the first 50 apps and sites; any more spill into `bedroom2`, `bedroom3`, and so on.
    static let bedroom = Self("bedroom")

    /// The store for the given group of 50 apps/sites (0 is `bedroom`).
    static func bedroom(_ index: Int) -> Self {
        index == 0 ? .bedroom : Self("bedroom\(index + 1)")
    }
}

/// The single source of truth for "should apps be blocked right now?"
///
/// Blocking = (in the bedroom AND inside bedtime hours, OR a test block is running)
/// AND something is selected.
/// It recomputes from shared state every time, so calling it extra times is harmless.
/// The app calls it on beacon enter/exit; the DeviceActivity extension calls it when
/// bedtime hours start and end.
enum Blocker {
    /// iOS shields at most 50 apps (and 50 sites) per store, and ignores a store's whole app
    /// list past that. Stores combine, so a bigger list is split into groups of 50.
    static let tokensPerStore = 50
    /// 20 stores = up to 1,000 apps. Every one is cleared when blocking stops.
    static let maxStores = 20

    private static let stores = (0..<maxStores).map { ManagedSettingsStore(named: .bedroom($0)) }

    @discardableResult
    static func refresh(reason: String, now: Date = .now) -> Bool {
        let selection = Shared.selection
        let testing = (Shared.testBlockUntil ?? .distantPast) > now
        let shouldBlock = (testing || (Shared.isInRoom(at: now) && Shared.schedule.contains(now)))
            && !selection.isEmptySelection

        if shouldBlock {
            let appGroups = chunks(selection.applicationTokens)
            let siteGroups = chunks(selection.webDomainTokens)
            let categories = selection.categoryTokens
            for (index, store) in stores.enumerated() {
                let apps = index < appGroups.count ? appGroups[index] : []
                let sites = index < siteGroups.count ? siteGroups[index] : []
                store.shield.applications = apps.isEmpty ? nil : apps
                store.shield.webDomains = sites.isEmpty ? nil : sites
                // Categories have no per-store cap worth splitting (iOS has only a dozen or so).
                if index == 0 && !categories.isEmpty {
                    store.shield.applicationCategories = .specific(categories)
                    store.shield.webDomainCategories = .specific(categories)
                } else {
                    store.shield.applicationCategories = nil
                    store.shield.webDomainCategories = nil
                }
            }
        } else {
            stores.forEach { $0.clearAllSettings() }
        }

        if Shared.isBlocking != shouldBlock {
            Shared.log(shouldBlock ? "Blocking on — \(reason)" : "Blocking off — \(reason)")
        }
        Shared.isBlocking = shouldBlock
        return shouldBlock
    }

    /// Splits tokens into groups of `tokensPerStore`, at most `maxStores` groups.
    static func chunks<T: Hashable>(_ tokens: Set<T>) -> [Set<T>] {
        let list = Array(tokens)
        return stride(from: 0, to: min(list.count, tokensPerStore * maxStores), by: tokensPerStore).map {
            Set(list[$0..<min($0 + tokensPerStore, list.count)])
        }
    }
}

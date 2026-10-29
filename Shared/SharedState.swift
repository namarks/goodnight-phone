import Foundation
import FamilyControls

/// State shared between the app and its DeviceActivity extension.
/// Everything lives in the App Group's UserDefaults so either process can read and write it.
enum Shared {
    /// The App Group ID is injected into each target's Info.plist by project.yml.
    static let groupID: String = {
        let id = Bundle.main.object(forInfoDictionaryKey: "LightsOutAppGroup") as? String ?? ""
        assert(!id.isEmpty, "LightsOutAppGroup is missing from Info.plist — regenerate the project with setup.sh")
        return id
    }()

    static let defaults: UserDefaults = UserDefaults(suiteName: groupID) ?? .standard

    private enum Key {
        static let selection = "selection"
        static let inRoom = "inRoom"
        static let isBlocking = "isBlocking"
        static let schedule = "schedule"
        static let syncedSchedule = "syncedSchedule"
        static let beacon = "beacon"
        static let monitoredBeacon = "monitoredBeacon"
        static let log = "log"
        static let testBlockUntil = "testBlockUntil"
    }

    // MARK: - What to block

    static var selection: FamilyActivitySelection {
        get { decode(FamilyActivitySelection.self, Key.selection) ?? FamilyActivitySelection() }
        set { encode(newValue, Key.selection) }
    }

    // MARK: - Where you are and what's applied

    /// True while the phone is within range of the bedroom beacon. Written only by the app.
    static var inRoom: Bool {
        get { defaults.bool(forKey: Key.inRoom) }
        set { defaults.set(newValue, forKey: Key.inRoom) }
    }

    /// Mirrors whether the shield is currently applied, for the UI.
    static var isBlocking: Bool {
        get { defaults.bool(forKey: Key.isBlocking) }
        set { defaults.set(newValue, forKey: Key.isBlocking) }
    }

    /// End of a "Try it now" test block (TestBlock), if one was started.
    static var testBlockUntil: Date? {
        get { defaults.object(forKey: Key.testBlockUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.testBlockUntil) }
    }

    // MARK: - When to block

    static var schedule: BedtimeSchedule {
        get { decode(BedtimeSchedule.self, Key.schedule) ?? BedtimeSchedule() }
        set { encode(newValue, Key.schedule) }
    }

    /// The schedule last handed to DeviceActivityCenter, so we only re-register when it changes.
    static var syncedSchedule: BedtimeSchedule? {
        get { decode(BedtimeSchedule.self, Key.syncedSchedule) }
        set { encode(newValue, Key.syncedSchedule) }
    }

    // MARK: - Which beacon marks the bedroom

    static var beacon: BeaconConfig? {
        get { decode(BeaconConfig.self, Key.beacon) }
        set { encode(newValue, Key.beacon) }
    }

    /// The beacon the location monitor is currently watching.
    static var monitoredBeacon: BeaconConfig? {
        get { decode(BeaconConfig.self, Key.monitoredBeacon) }
        set { encode(newValue, Key.monitoredBeacon) }
    }

    // MARK: - Activity log (shown in the app; handy for tuning the beacon)

    static var logEntries: [LogEntry] {
        decode([LogEntry].self, Key.log) ?? []
    }

    static func log(_ message: String) {
        var entries = logEntries
        entries.append(LogEntry(date: .now, message: message))
        if entries.count > 60 { entries.removeFirst(entries.count - 60) }
        encode(entries, Key.log)
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var message: String
}

/// The iBeacon that marks the bedroom. Major/minor are optional and only needed
/// when several beacons share one UUID (common with vendor default UUIDs).
struct BeaconConfig: Codable, Equatable {
    var uuid: String
    var major: UInt16?
    var minor: UInt16?

    var isValid: Bool { UUID(uuidString: uuid) != nil && !(major == nil && minor != nil) }

    var shortDescription: String {
        var text = String(uuid.uppercased().prefix(8)) + "…"
        if let major { text += " major \(major)" }
        if let minor { text += " minor \(minor)" }
        return text
    }
}

extension FamilyActivitySelection {
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    /// iOS shields at most 50 tokens of each kind; anything past that may not be blocked.
    var exceedsShieldLimit: Bool {
        applicationTokens.count > 50 || categoryTokens.count > 50 || webDomainTokens.count > 50
    }

    var summary: String {
        var parts: [String] = []
        let apps = applicationTokens.count, cats = categoryTokens.count, sites = webDomainTokens.count
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }
}

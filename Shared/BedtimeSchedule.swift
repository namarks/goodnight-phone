import Foundation

/// The hours during which being in the bedroom blocks apps.
/// Stored as minutes after midnight so overnight windows (9 PM – 7 AM) are easy.
///
/// There are usual hours, and each night of the week can follow them, have its own hours, or be
/// off. A night belongs to the day it starts on: Friday's 9 PM – 7 AM runs into Saturday morning.
struct BedtimeSchedule: Codable, Equatable {
    /// One night of the week.
    enum Night: Codable, Equatable {
        case usual
        case hours(start: Int, end: Int)
        /// Nothing is blocked from this night's start until the next night's.
        case off
    }

    /// When false, apps are blocked any time you're in the bedroom.
    var limitToHours: Bool = true
    var startMinutes: Int = 21 * 60      // 9:00 PM
    var endMinutes: Int = 7 * 60         // 7:00 AM
    /// Indexed by weekday, Sunday first (Calendar's weekday − 1).
    var nights: [Night] = Array(repeating: .usual, count: 7)

    init() {}

    // Schedules saved before per-night hours have no `nights`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitToHours = try container.decodeIfPresent(Bool.self, forKey: .limitToHours) ?? true
        startMinutes = try container.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 21 * 60
        endMinutes = try container.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 7 * 60
        let saved = try container.decodeIfPresent([Night].self, forKey: .nights) ?? []
        nights = saved.count == 7 ? saved : Array(repeating: .usual, count: 7)
    }

    /// A night's start and end, or nil if it's off.
    func hours(onWeekday weekday: Int) -> (start: Int, end: Int)? {
        switch nights[(weekday + 6) % 7] {
        case .usual: return (startMinutes, endMinutes)
        case .hours(let start, let end): return (start, end)
        case .off: return nil
        }
    }

    /// Whether `date` falls inside bedtime hours. Start is inclusive, end exclusive.
    /// A night whose start and end are equal lasts 24 hours.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard limitToHours else { return true }
        if lastNight(at: date, calendar: calendar) != nil { return true }
        let now = Self.minutes(from: date, calendar: calendar)
        guard let tonight = hours(onWeekday: calendar.component(.weekday, from: date)) else { return false }
        return now >= tonight.start && now - tonight.start < Self.length(tonight)
    }

    /// Yesterday's hours, if that night is still going at `date`.
    private func lastNight(at date: Date, calendar: Calendar) -> (start: Int, end: Int)? {
        let today = calendar.component(.weekday, from: date)
        guard let hours = self.hours(onWeekday: today == 1 ? 7 : today - 1) else { return nil }
        let sinceStart = Self.minutes(from: date, calendar: calendar) + 24 * 60 - hours.start
        return sinceStart < Self.length(hours) ? hours : nil
    }

    /// Every start and end time across the week: the moments blocking can turn on or off.
    var boundaries: Set<Int> {
        guard limitToHours else { return [] }
        return Set((1...7).compactMap { hours(onWeekday: $0) }.flatMap { [$0.start, $0.end] })
    }

    /// Whether any night is off or has hours other than the usual ones. A night set to its own
    /// hours that happen to match the usual ones doesn't count.
    var variesByNight: Bool {
        (1...7).contains { weekday in
            guard let hours = self.hours(onWeekday: weekday) else { return true }
            return hours != (startMinutes, endMinutes)
        }
    }

    /// For the Hours by night row, about the nights that are on (the day circles show which):
    /// "Same hours", the hours they all share when that's not the usual ones, "Varies", or "All off".
    var nightsSummary: String {
        let on = (1...7).compactMap { hours(onWeekday: $0) }
        guard let shared = on.first else { return "All off" }
        guard on.allSatisfy({ $0 == shared }) else { return "Varies" }
        return shared == (startMinutes, endMinutes) ? "Same hours" : Self.summary(start: shared.start, end: shared.end)
    }

    var summary: String {
        guard limitToHours else { return "Any time" }
        if !variesByNight { return Self.summary(start: startMinutes, end: endMinutes) }
        return (1...7).map { weekday in
            let name = Calendar.current.shortWeekdaySymbols[weekday - 1]
            guard let hours = self.hours(onWeekday: weekday) else { return "\(name) off" }
            return "\(name) \(Self.summary(start: hours.start, end: hours.end))"
        }.joined(separator: ", ")
    }

    /// The hours of the night you're in now, or of tonight once last night's are over;
    /// nil if that night is off.
    func currentNight(at date: Date = .now, calendar: Calendar = .current) -> String? {
        let night = lastNight(at: date, calendar: calendar)
            ?? hours(onWeekday: calendar.component(.weekday, from: date))
        return night.map { Self.summary(start: $0.start, end: $0.end) }
    }

    static func summary(start: Int, end: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        if start == end { return "24 hours from \(formatter.string(from: date(fromMinutes: start)))" }
        return "\(formatter.string(from: date(fromMinutes: start))) – \(formatter.string(from: date(fromMinutes: end)))"
    }

    /// Minutes from a night's start to its end.
    private static func length(_ hours: (start: Int, end: Int)) -> Int {
        let length = (hours.end - hours.start + 24 * 60) % (24 * 60)
        return length == 0 ? 24 * 60 : length
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

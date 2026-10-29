import Foundation

/// The hours during which being in the bedroom blocks apps.
/// Stored as minutes after midnight so overnight windows (9 PM – 7 AM) are easy.
struct BedtimeSchedule: Codable, Equatable {
    /// When false, apps are blocked any time you're in the bedroom.
    var limitToHours: Bool = true
    var startMinutes: Int = 21 * 60      // 9:00 PM
    var endMinutes: Int = 7 * 60         // 7:00 AM

    /// Whether `date` falls inside bedtime hours. Start is inclusive, end exclusive.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard limitToHours, startMinutes != endMinutes else { return true }
        let now = Self.minutes(from: date, calendar: calendar)
        if startMinutes < endMinutes {
            return now >= startMinutes && now < endMinutes
        }
        return now >= startMinutes || now < endMinutes   // crosses midnight
    }

    var summary: String {
        guard limitToHours, startMinutes != endMinutes else { return "Any time" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let start = formatter.string(from: Self.date(fromMinutes: startMinutes))
        let end = formatter.string(from: Self.date(fromMinutes: endMinutes))
        return "\(start) – \(end)"
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

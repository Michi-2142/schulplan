import Foundation

/// Datumshelfer. Die API arbeitet mit lokalen Kalendertagen (`yyyy-MM-dd`), deshalb
/// rechnen wir durchgehend im Kalender von Europe/Berlin.
enum SchoolCalendar {
    static let timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func date(_ iso: String) -> Date? { isoFormatter.date(from: String(iso.prefix(10))) }

    static var today: String { iso(.now) }

    static func addDays(_ days: Int, to iso: String) -> String {
        guard let date = date(iso), let result = calendar.date(byAdding: .day, value: days, to: date) else { return iso }
        return self.iso(result)
    }

    /// Montag der Woche, in der `date` liegt. Am Wochenende zählt bereits die nächste Woche.
    static func schoolWeekStart(for date: Date = .now) -> String {
        let cal = calendar
        var reference = date
        let weekday = cal.component(.weekday, from: date) // 1 = So, 7 = Sa
        if weekday == 7 { reference = cal.date(byAdding: .day, value: 2, to: date) ?? date }
        if weekday == 1 { reference = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        let start = cal.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        return iso(start)
    }

    /// Mo–Fr ab `weekStart`.
    static func schoolDays(from weekStart: String) -> [String] {
        (0..<5).map { addDays($0, to: weekStart) }
    }

    /// ISO-Wochentag 1 = Mo … 7 = So
    static func isoWeekday(_ iso: String) -> Int {
        guard let date = date(iso) else { return 1 }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func shortWeekday(_ iso: String) -> String {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][isoWeekday(iso) - 1]
    }

    static func longWeekday(_ iso: String) -> String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][isoWeekday(iso) - 1]
    }

    /// `17.11.`
    static func dayMonth(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2]).\(parts[1])."
    }

    static func dayNumber(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]) else { return iso }
        return String(day)
    }

    /// „Heute“, „Morgen“ oder „Mi 19.11.“
    static func relativeLabel(_ iso: String) -> String {
        if iso == today { return "Heute" }
        if iso == addDays(1, to: today) { return "Morgen" }
        return "\(shortWeekday(iso)) \(dayMonth(iso))"
    }

    /// Minuten seit Mitternacht für `HH:MM`.
    static func minutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }

    static var nowMinutes: Int {
        let components = calendar.dateComponents([.hour, .minute], from: .now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

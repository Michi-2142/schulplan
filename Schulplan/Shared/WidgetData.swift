import Foundation

/// Kompakter Stand für die Widgets. Die App schreibt ihn nach jedem Abruf in den
/// App-Group-Container, die Widget-Erweiterung liest ihn nur – sie braucht weder Netz noch Keychain.
struct WidgetData: Codable, Sendable {
    var updatedAt: Date
    var selectedStudentId: String?
    var isDemo: Bool
    var students: [WidgetStudent]

    /// Kind laut Konfiguration, sonst das in der App gewählte, sonst das erste.
    func student(id: String?) -> WidgetStudent? {
        if let id, let match = students.first(where: { $0.id == id }) { return match }
        return students.first { $0.id == selectedStudentId } ?? students.first
    }
}

struct WidgetStudent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var className: String?
    var fetchedAt: Date
    /// Stunden ab heute (aktuelle und nächste Woche).
    var lessons: [Lesson]
    var exams: [WidgetExam]
    var openHomework: Int
    var openLetters: Int
    var unreadMessages: Int
}

struct WidgetExam: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var subject: String
    var type: String?
    var date: String
}

import Security

/// Ablage des Widget-Stands in einer gemeinsamen Keychain-Gruppe. Eine App Group bräuchte ein
/// eigenes Provisioning-Profil – die Keychain-Gruppe deckt das vorhandene Team-Profil ab.
enum WidgetStore {
    static let accessGroup = "W63SR2C3Q9.de.codeunity.Schulplan.shared"
    static let todayKind = "SchulplanToday"
    static let changesKind = "SchulplanChanges"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "de.codeunity.Schulplan.widget",
            kSecAttrAccount as String: "widget",
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    static func load() -> WidgetData? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }

    static func save(_ value: WidgetData?) {
        guard let value else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Auch bei gesperrtem Gerät lesbar, damit Widgets aktuell bleiben.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}

/// Was ein Widget zu einem Zeitpunkt zeigt: welcher Tag, welche Stunde gerade läuft, was sich ändert.
struct DayPlan: Sendable {
    let date: Date
    let today: String
    /// Angezeigter Tag: heute, solange noch Unterricht ist – danach der nächste Schultag.
    let day: String?
    let lessons: [Lesson]
    /// Laufende oder nächste Stunde (nur, wenn `day` heute ist).
    let current: Lesson?
    let currentIsRunning: Bool
    /// Alle noch anstehenden Abweichungen vom Regelplan, nach Tag und Stunde sortiert.
    let changes: [Lesson]

    init(student: WidgetStudent?, at date: Date) {
        self.date = date
        let today = SchoolCalendar.iso(date)
        self.today = today
        let now = SchoolCalendar.minutes(of: date)
        let all = (student?.lessons ?? [])
            .filter { $0.date >= today }
            .sorted { ($0.date, $0.hourSort) < ($1.date, $1.hourSort) }

        let todays = all.filter { $0.date == today }
        let lastEnd = todays.compactMap { SchoolCalendar.minutes($0.end) }.max() ?? 0
        let day = !todays.isEmpty && now < lastEnd ? today : all.first { $0.date > today }?.date
        self.day = day
        lessons = all.filter { $0.date == day }

        if day == today {
            let active = lessons.filter { $0.state != .cancelled }
            if let running = active.first(where: {
                guard let start = SchoolCalendar.minutes($0.start), let end = SchoolCalendar.minutes($0.end) else { return false }
                return start <= now && now < end
            }) {
                current = running
                currentIsRunning = true
            } else {
                current = active.first { (SchoolCalendar.minutes($0.start) ?? 0) > now }
                currentIsRunning = false
            }
        } else {
            current = lessons.first { $0.state != .cancelled }
            currentIsRunning = false
        }

        changes = all.filter { lesson in
            guard lesson.state != .regular else { return false }
            guard lesson.date == today else { return true }
            return (SchoolCalendar.minutes(lesson.end) ?? 24 * 60) > now
        }
    }

    var dayLabel: String {
        guard let day else { return "Schulfrei" }
        return SchoolCalendar.relativeLabel(day, from: today)
    }

    var changesOnDay: Int { lessons.filter { $0.state != .regular }.count }

    /// Zeitpunkte, an denen sich die Anzeige ändert: Stundenbeginn und -ende des angezeigten Tags.
    var upcomingTransitions: [Date] {
        guard let day else { return [] }
        return lessons
            .flatMap { [SchoolCalendar.dateTime(day, $0.start), SchoolCalendar.dateTime(day, $0.end)] }
            .compactMap { $0 }
            .filter { $0 > date }
    }
}

extension Lesson {
    /// Kurzer Hinweis zur Abweichung, z. B. „statt Mathematik“ oder „Raum 204 statt 112“.
    var changeNote: String? {
        switch state {
        case .substitution:
            if let originalSubject, originalSubject != subject { return "statt \(originalSubject)" }
            if let originalTeacher { return "statt \(originalTeacher)" }
            return comment
        case .roomChange:
            return [room.map { "Raum \($0)" }, originalRoom.map { "statt \($0)" }].compactMap { $0 }.joined(separator: " ")
        case .cancelled:
            return comment ?? "fällt aus"
        case .added:
            return comment ?? "zusätzlich"
        case .regular:
            return nil
        }
    }

    var shortSubject: String { subjectAbbr.flatMap { $0.isEmpty ? nil : $0 } ?? subject }
}

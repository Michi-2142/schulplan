import Foundation
import UserNotifications

enum NotificationPrefs {
    static var schedule: Bool { UserDefaults.standard.object(forKey: "notifySchedule") as? Bool ?? true }
    static var exams: Bool { UserDefaults.standard.object(forKey: "notifyExams") as? Bool ?? true }
    static var homework: Bool { UserDefaults.standard.object(forKey: "notifyHomework") as? Bool ?? false }
    static var messages: Bool { UserDefaults.standard.object(forKey: "notifyMessages") as? Bool ?? true }
    static var letters: Bool { UserDefaults.standard.object(forKey: "notifyLetters") as? Bool ?? true }
    static var tiles: Bool { UserDefaults.standard.object(forKey: "notifyTiles") as? Bool ?? true }
    static var events: Bool { UserDefaults.standard.object(forKey: "notifyEvents") as? Bool ?? true }
    static var grades: Bool { UserDefaults.standard.object(forKey: "notifyGrades") as? Bool ?? true }
    static var administration: Bool { UserDefaults.standard.object(forKey: "notifyAdministration") as? Bool ?? true }
}

enum NotificationManager {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func deliver(_ events: [ChangeEvent]) async {
        let wanted = events.filter { event in
            switch event.kind {
            case .newExam: NotificationPrefs.exams
            case .newHomework: NotificationPrefs.homework
            case .newMessage: NotificationPrefs.messages
            case .newLetter: NotificationPrefs.letters
            case .tileChanged: NotificationPrefs.tiles
            case .newEvent, .eventChanged: NotificationPrefs.events
            case .newGrade: NotificationPrefs.grades
            case .newAbsence, .exemptionDecided, .newInvoice, .alldayNote, .parentTalk: NotificationPrefs.administration
            default: NotificationPrefs.schedule
            }
        }
        guard !wanted.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let today = SchoolCalendar.today
        let tomorrow = SchoolCalendar.addDays(1, to: today)

        // Viele Änderungen auf einmal (z. B. ganzer Tag entfällt) → eine Sammelmitteilung pro Tag.
        // Nachrichten, Briefe, Pinnwand und Termine einzeln – nur Stundenplan wird pro Tag gebündelt.
        let individual: [ChangeEvent.Kind: (thread: String, tab: String)] = [
            .newMessage: ("messages", "messages"), .newLetter: ("letters", "school"),
            .tileChanged: ("tiles", "school"), .newEvent: ("events", "school"), .eventChanged: ("events", "school"),
            .newGrade: ("grades", "school"), .newAbsence: ("absences", "school"), .exemptionDecided: ("absences", "school"),
            .newInvoice: ("invoices", "school"), .alldayNote: ("allday", "school"), .parentTalk: ("parenttalks", "school"),
        ]
        for event in wanted {
            guard let target = individual[event.kind] else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.displayTitle
            content.body = event.body
            // Elternbriefe sind wichtig genug, um auch durch den Fokus-Modus zu kommen.
            await add(content, threadId: target.thread, urgent: [.newLetter, .newAbsence, .exemptionDecided].contains(event.kind), center: center, tab: target.tab)
        }

        let grouped = Dictionary(grouping: wanted.filter { individual[$0.kind] == nil }) { $0.date ?? "" }
        for (date, dayEvents) in grouped.sorted(by: { $0.key < $1.key }) {
            let urgent = date == today || date == tomorrow
            if dayEvents.count > 3 {
                let content = UNMutableNotificationContent()
                let label = date.isEmpty ? "Schulplan" : "\(SchoolCalendar.longWeekday(date)), \(SchoolCalendar.dayMonth(date))"
                let names = Set(dayEvents.compactMap(\.student))
                content.title = (names.count == 1 ? "\(names.first!) · " : "") + "\(dayEvents.count) Änderungen · \(label)"
                content.body = dayEvents.map(\.displayTitle).joined(separator: "\n")
                await add(content, threadId: date, urgent: urgent, center: center)
            } else {
                for event in dayEvents {
                    let content = UNMutableNotificationContent()
                    content.title = event.displayTitle
                    content.body = event.body
                    await add(content, threadId: date, urgent: urgent && event.kind != .newHomework, center: center)
                }
            }
        }
    }

    static func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Entfall · Mathematik"
        content.body = "So sehen Mitteilungen aus, wenn sich der Plan ändert."
        await add(content, threadId: "test", urgent: true, center: .current())
    }

    private static func add(_ content: UNMutableNotificationContent, threadId: String, urgent: Bool,
                            center: UNUserNotificationCenter, tab: String = "changes") async {
        content.sound = .default
        content.threadIdentifier = threadId
        // Zeitkritisch kommt auch im Fokus-Modus durch – wichtig für Ausfälle am selben Morgen.
        content.interruptionLevel = urgent ? .timeSensitive : .active
        content.userInfo = ["tab": tab]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

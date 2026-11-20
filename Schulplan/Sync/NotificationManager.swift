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

    /// Mehr Mitteilungen auf einmal werden zu einer Sammelmitteilung – sonst flutet ein Rückstau den Sperrbildschirm.
    private static let maxSeparate = 4

    /// Arten, die an einen Tag gebunden sind – liegt der schon hinter uns, ist die Mitteilung wertlos.
    private static let timeBound: Set<ChangeEvent.Kind> = [
        .cancelled, .substitution, .roomChange, .added, .restored, .changed, .newExam, .newHomework, .alldayNote,
    ]

    static func isPast(_ event: ChangeEvent, today: String = SchoolCalendar.today, now: Date = .now) -> Bool {
        guard timeBound.contains(event.kind) else { return false }
        if let endsAt = event.endsAt { return endsAt < now }
        guard let date = event.date else { return false }
        return date < today
    }

    static func deliver(_ events: [ChangeEvent]) async {
        let today = SchoolCalendar.today
        let wanted = events.filter { event in
            guard !isPast(event, today: today) else { return false }
            return switch event.kind {
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
        let tomorrow = SchoolCalendar.addDays(1, to: today)

        struct Pending { var content: UNMutableNotificationContent; var threadId: String; var urgent: Bool; var tab: String; var lines: [String] }
        var pending: [Pending] = []

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
            pending.append(Pending(content: content, threadId: target.thread,
                                   urgent: [.newLetter, .newAbsence, .exemptionDecided].contains(event.kind),
                                   tab: target.tab, lines: [event.displayTitle]))
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
                pending.append(Pending(content: content, threadId: date, urgent: urgent, tab: "changes", lines: [content.title]))
            } else {
                for event in dayEvents {
                    let content = UNMutableNotificationContent()
                    content.title = event.displayTitle
                    content.body = event.body
                    pending.append(Pending(content: content, threadId: date, urgent: urgent && event.kind != .newHomework,
                                           tab: "changes", lines: [event.displayTitle]))
                }
            }
        }

        if pending.count > maxSeparate {
            let content = UNMutableNotificationContent()
            content.title = "Schulplan · \(wanted.count) Neuigkeiten"
            let lines = pending.flatMap(\.lines)
            content.body = (lines.prefix(6) + (lines.count > 6 ? ["… und \(lines.count - 6) weitere"] : [])).joined(separator: "\n")
            let tabs = Set(pending.map(\.tab))
            await add(content, threadId: "summary", urgent: pending.contains(where: \.urgent), center: center,
                      tab: tabs.count == 1 ? tabs.first! : "changes")
        } else {
            for item in pending {
                await add(item.content, threadId: item.threadId, urgent: item.urgent, center: center, tab: item.tab)
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

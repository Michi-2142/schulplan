import AppIntents
import WidgetKit

// MARK: - Konfiguration: welches Kind?

struct StudentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static let defaultQuery = StudentQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StudentQuery: EntityQuery {
    private var all: [StudentEntity] {
        (WidgetStore.load()?.students ?? []).map { StudentEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [StudentEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StudentEntity] { all }
}

struct SelectStudentIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Kind wählen"
    static let description = IntentDescription("Ohne Auswahl zeigt das Widget das Kind, das in der App gewählt ist.")

    @Parameter(title: "Kind")
    var student: StudentEntity?
}

// MARK: - Zeitleiste

struct PlanEntry: TimelineEntry {
    let date: Date
    let student: WidgetStudent?
    let plan: DayPlan
    /// Mehrere Kinder im Konto – dann steht der Name im Kopf.
    let showsName: Bool
    /// Noch nie synchronisiert bzw. abgemeldet.
    let isEmpty: Bool

    var deepLinkQuery: String { student.map { "?student=\($0.id)" } ?? "" }
}

struct PlanProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        entry(for: WidgetSample.data, studentId: nil, at: .now)
    }

    func snapshot(for configuration: SelectStudentIntent, in context: Context) async -> PlanEntry {
        // In der Widget-Galerie lieber Beispieldaten als ein leeres Widget zeigen.
        let data = WidgetStore.load().flatMap { $0.students.isEmpty ? nil : $0 } ?? (context.isPreview ? WidgetSample.data : nil)
        return entry(for: data, studentId: configuration.student?.id, at: .now)
    }

    func timeline(for configuration: SelectStudentIntent, in context: Context) async -> Timeline<PlanEntry> {
        let data = WidgetStore.load()
        let now = Date.now
        let first = entry(for: data, studentId: configuration.student?.id, at: now)

        // Neue Einträge zu jedem Stundenbeginn/-ende und um Mitternacht (Tageswechsel).
        let calendar = SchoolCalendar.calendar
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        var dates = first.plan.upcomingTransitions.filter { $0 < midnight }
        dates.append(midnight)
        let entries = [first] + dates.prefix(40).map { entry(for: data, studentId: configuration.student?.id, at: $0) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<SelectStudentIntent>] { [] }

    private func entry(for data: WidgetData?, studentId: String?, at date: Date) -> PlanEntry {
        let student = data?.student(id: studentId)
        return PlanEntry(
            date: date,
            student: student,
            plan: DayPlan(student: student, at: date),
            showsName: (data?.students.count ?? 0) > 1,
            isEmpty: student == nil
        )
    }
}

// MARK: - Beispieldaten für Galerie und Platzhalter

enum WidgetSample {
    static var data: WidgetData {
        WidgetData(updatedAt: .now, selectedStudentId: "sample", isDemo: true, students: [student])
    }

    static var student: WidgetStudent {
        let today = SchoolCalendar.today
        let tomorrow = SchoolCalendar.addDays(1, to: today)
        let times = [("07:55", "08:40"), ("08:45", "09:30"), ("09:50", "10:35"), ("10:40", "11:25"), ("11:40", "12:25"), ("12:30", "13:15")]
        let plan: [(String, String, String, String, LessonState)] = [
            ("Mathematik", "M", "Kar", "204", .regular),
            ("Deutsch", "D", "Hof", "204", .substitution),
            ("Englisch", "E", "Sch", "112", .regular),
            ("Biologie", "Bio", "Lan", "N1", .cancelled),
            ("Geschichte", "G", "Beck", "108", .roomChange),
            ("Sport", "Sp", "Mül", "TH1", .regular),
        ]
        func lessons(on day: String, changes: Bool) -> [Lesson] {
            plan.enumerated().map { index, item in
                let state = changes ? item.4 : (index == 1 ? .cancelled : .regular)
                return Lesson(
                    id: "\(day)|\(index + 1)", date: day, hour: "\(index + 1)", hourSort: index + 1,
                    start: times[index].0, end: times[index].1,
                    subject: item.0, subjectAbbr: item.1, teacher: item.2,
                    room: state == .roomChange ? "115" : item.3, state: state,
                    originalSubject: state == .substitution ? "Physik" : nil, originalTeacher: nil,
                    originalRoom: state == .roomChange ? item.3 : nil, comment: nil
                )
            }
        }
        return WidgetStudent(
            id: "sample", name: "Mia", className: "7b", fetchedAt: .now,
            lessons: lessons(on: today, changes: true) + lessons(on: tomorrow, changes: false),
            exams: [WidgetExam(id: "e1", subject: "Mathematik", type: "Schulaufgabe", date: SchoolCalendar.addDays(3, to: today))],
            openHomework: 2, openLetters: 1, unreadMessages: 0
        )
    }
}

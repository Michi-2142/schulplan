import Foundation
import WidgetKit

/// Schreibt den aktuellen Stand für die Widgets und stößt deren Neuaufbau an.
/// Wird nach jedem Abruf (auch im Hintergrund) und nach lokalen Änderungen aufgerufen.
enum WidgetBridge {
    static func publish() {
        let store = SessionStore.shared
        guard store.isLoggedIn else {
            clear()
            return
        }
        let today = SchoolCalendar.today
        let examHorizon = SchoolCalendar.addDays(21, to: today)
        let done = Set(UserDefaults.standard.stringArray(forKey: "doneHomework") ?? [])

        let students: [WidgetStudent] = store.activeStudents.compactMap { student in
            guard let snapshot = store.snapshot(for: student.id) else { return nil }
            return WidgetStudent(
                id: student.id,
                name: student.firstname.isEmpty ? student.displayName : student.firstname,
                className: student.className,
                fetchedAt: snapshot.fetchedAt,
                lessons: snapshot.lessons.filter { $0.date >= today },
                exams: snapshot.exams
                    .filter { $0.date >= today && $0.date <= examHorizon }
                    .sorted { $0.date < $1.date }
                    .map { WidgetExam(id: $0.id, subject: $0.subject, type: $0.type, date: $0.date) },
                openHomework: snapshot.homework.filter { !done.contains($0.id) && ($0.due ?? $0.date) >= today }.count,
                openLetters: (snapshot.letters ?? []).filter(\.needsAction).count,
                unreadMessages: (snapshot.threads ?? []).reduce(0) { $0 + $1.unreadCount }
            )
        }
        WidgetStore.save(WidgetData(updatedAt: .now, selectedStudentId: store.selectedStudent?.id, isDemo: store.isDemo, students: students))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetStore.save(nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

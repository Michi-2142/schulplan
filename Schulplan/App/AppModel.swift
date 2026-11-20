import Foundation
import Observation
import SwiftUI

enum AppTab: Hashable {
    case today, week, changes, messages, school
}

@MainActor
@Observable
final class AppModel {
    private let store = SessionStore.shared

    var isLoggedIn: Bool
    /// Stand je Kind (Schlüssel = Schüler-Id).
    var snapshots: [String: Snapshot] = [:]
    var history: [ChangeEvent]
    var students: [Student]
    var selectedStudentId: String?
    var isRefreshing = false
    var errorMessage: String?
    var selectedTab: AppTab = .today
    var doneHomework: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "doneHomework") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(doneHomework), forKey: "doneHomework")
            WidgetBridge.publish()
        }
    }

    init() {
        isLoggedIn = store.isLoggedIn
        history = store.history
        students = store.activeStudents
        selectedStudentId = store.selectedStudent?.id
        loadSnapshots()
        #if DEBUG
        // Für Screenshots im Simulator: `-startTab messages`
        if UserDefaults.standard.string(forKey: "startTab") == "messages" { selectedTab = .messages }
        if UserDefaults.standard.string(forKey: "startTab") == "changes" { selectedTab = .changes }
        if UserDefaults.standard.string(forKey: "startTab") == "school" { selectedTab = .school }
        if UserDefaults.standard.string(forKey: "startTab") == "week" { selectedTab = .week }
        // `-autoDemo YES` startet ohne Tippen direkt im Demo-Modus.
        if UserDefaults.standard.bool(forKey: "autoDemo"), !isLoggedIn { Task { await startDemo() } }
        #endif
    }

    var isDemo: Bool { store.isDemo }

    var selectedStudent: Student? { students.first { $0.id == selectedStudentId } ?? students.first }

    var hasSeveralStudents: Bool { students.count > 1 }

    /// Stand des gerade gewählten Kindes.
    var snapshot: Snapshot? {
        get { selectedStudent.flatMap { snapshots[$0.id] } }
        set { if let newValue { snapshots[newValue.studentId] = newValue } }
    }

    private func loadSnapshots() {
        var loaded: [String: Snapshot] = [:]
        for student in students {
            if let snapshot = store.snapshot(for: student.id) { loaded[student.id] = snapshot }
        }
        snapshots = loaded
    }

    /// Was beim Kind Aufmerksamkeit braucht: anstehende Planänderungen + unbestätigte Briefe.
    func attentionCount(for student: Student) -> Int {
        guard let snapshot = snapshots[student.id] else { return 0 }
        let today = SchoolCalendar.today
        return snapshot.lessons.filter { $0.state != .regular && $0.date >= today }.count
            + (snapshot.letters ?? []).filter(\.needsAction).count
    }

    /// Nachrichten gehören zum Konto, nicht zum Kind – Änderungen in allen Ständen nachziehen.
    private func updateAllSnapshots(_ change: (inout Snapshot) -> Void) {
        for (id, var snapshot) in snapshots {
            change(&snapshot)
            snapshots[id] = snapshot
            store.save(snapshot)
        }
    }

    var lessons: [Lesson] { snapshot?.lessons ?? [] }

    func lessons(on date: String) -> [Lesson] { lessons.filter { $0.date == date } }

    /// Alle anstehenden Abweichungen vom Regelplan.
    var upcomingChanges: [Lesson] {
        let today = SchoolCalendar.today
        return lessons.filter { $0.state != .regular && $0.date >= today }
    }

    var openHomeworkCount: Int {
        (snapshot?.homework ?? []).filter { !doneHomework.contains($0.id) && ($0.due ?? $0.date) >= SchoolCalendar.today }.count
    }

    var threads: [MessageThread] { snapshot?.threads ?? [] }
    var letters: [Letter] { snapshot?.letters ?? [] }
    var tiles: [Tile] { snapshot?.tiles ?? [] }
    var events: [SchoolEvent] { snapshot?.events ?? [] }

    var openLetters: Int { letters.filter(\.needsAction).count }

    var upcomingEvents: [SchoolEvent] {
        let today = SchoolCalendar.today
        return events.filter { $0.lastDay >= today }
    }

    func events(on date: String) -> [SchoolEvent] { events.filter { $0.covers(date) } }

    func confirm(_ letter: Letter) async throws {
        try await LettersAPI.confirm(letter)
        guard var current = snapshot, let index = current.letters?.firstIndex(where: { $0.id == letter.id }) else { return }
        current.letters?[index].confirmed = true
        snapshot = current
        store.save(current)
        WidgetBridge.publish()
    }

    var unreadMessages: Int { threads.reduce(0) { $0 + $1.unreadCount } }

    /// Lokal sofort als gelesen zeigen und den Stand sichern, damit kein erneuter Hinweis kommt.
    func markRead(_ thread: MessageThread) async {
        guard thread.unreadCount > 0 else { return }
        updateAllSnapshots { snapshot in
            guard let index = snapshot.threads?.firstIndex(where: { $0.subscriptionId == thread.subscriptionId }) else { return }
            snapshot.threads?[index].unreadCount = 0
        }
        WidgetBridge.publish()
        await MessengerAPI.markRead(thread)
    }

    /// Nach dem Senden die Vorschau in der Liste aktualisieren.
    func didSend(_ text: String, in thread: MessageThread) {
        let now = ISO8601DateFormatter().string(from: .now)
        updateAllSnapshots { snapshot in
            guard let index = snapshot.threads?.firstIndex(where: { $0.subscriptionId == thread.subscriptionId }) else { return }
            snapshot.threads?[index].preview = "Du: " + text
            snapshot.threads?[index].lastMessageAt = now
            snapshot.threads?.sort { ($0.lastMessageAt ?? "") > ($1.lastMessageAt ?? "") }
        }
    }

    // MARK: Anmeldung

    func login(email: String, password: String, code: String?, account: AccountChoice?) async throws -> LoginOutcome {
        let credentials = Credentials(
            emailOrUsername: email.trimmingCharacters(in: .whitespaces),
            password: password,
            userId: account?.userId,
            institutionId: account?.institutionId
        )
        store.isDemo = false
        let outcome = try await SchulmanagerAPI.shared.login(credentials, twoFactorCode: code?.isEmpty == false ? code : nil)
        if case .success(let students) = outcome {
            store.removeAllSnapshots()
            store.history = []
            snapshots = [:]
            self.students = students
            selectedStudentId = store.selectedStudent?.id
            await finishLogin()
        }
        return outcome
    }

    func startDemo() async {
        store.clearAll()
        store.isDemo = true
        students = DemoData.students
        selectedStudentId = DemoData.students.first?.id
        snapshots = [:]
        await finishLogin()
    }

    private func finishLogin() async {
        isLoggedIn = true
        _ = await NotificationManager.requestAuthorization()
        await refresh()
        BackgroundRefresh.schedule()
    }

    func logout() async {
        if !store.isDemo { await SchulmanagerAPI.shared.logout() }
        store.clearAll()
        WidgetBridge.clear()
        snapshots = [:]
        history = []
        students = []
        selectedStudentId = nil
        isLoggedIn = false
        selectedTab = .today
    }

    func selectStudent(_ id: String) async {
        guard id != selectedStudentId else { return }
        store.selectedStudentId = id
        withAnimation(.smooth) { selectedStudentId = id }
        WidgetBridge.publish()
        // Alle Kinder werden ohnehin abgeglichen – nur nachladen, wenn für dieses Kind noch nichts da ist.
        if snapshots[id] == nil { await refresh() }
    }

    // MARK: Aktualisieren

    func refresh() async {
        guard isLoggedIn, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            // Die App ist offen – Änderungen stehen im Verlauf, Banner wären nur Lärm.
            let result = try await SyncService.shared.sync(notify: false)
            for (id, snapshot) in result.snapshots { snapshots[id] = snapshot }
            students = store.activeStudents
            history = store.history
            errorMessage = nil
        } catch SMError.needsLogin {
            errorMessage = SMError.needsLogin.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Beim Öffnen der App: nur abrufen, wenn der letzte Stand älter als 2 Minuten ist.
    func refreshIfStale() async {
        loadSnapshots()
        history = store.history
        // Ältere Installationen haben noch keinen Widget-Stand – beim Öffnen einmal nachziehen.
        if WidgetStore.load() == nil { WidgetBridge.publish() }
        if let fetchedAt = snapshot?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 120 { return }
        await refresh()
    }

    func clearHistory() {
        store.history = []
        history = []
    }
}

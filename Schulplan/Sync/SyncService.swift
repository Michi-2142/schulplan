import Foundation

struct SyncResult: Sendable {
    var snapshots: [String: Snapshot]
    var events: [ChangeEvent]
}

/// Ein Abruf = Daten aller Kinder holen, mit dem letzten Stand vergleichen, speichern, benachrichtigen.
/// Wird von Vordergrund und Hintergrund-Aktualisierung gleichermaßen genutzt.
actor SyncService {
    static let shared = SyncService()

    private let api = SchulmanagerAPI.shared
    private let store = SessionStore.shared
    private var running: Task<SyncResult, Error>?

    /// Mehrfache gleichzeitige Aufrufe (Pull-to-Refresh + Hintergrund) teilen sich einen Abruf.
    func sync(notify: Bool = true) async throws -> SyncResult {
        if let running { return try await running.value }
        let task = Task { try await performSync(notify: notify) }
        running = task
        defer { running = nil }
        return try await task.value
    }

    /// Alle Kinder des Kontos abgleichen – sonst gingen Änderungen beim gerade nicht gewählten Kind verloren.
    private func performSync(notify: Bool) async throws -> SyncResult {
        let students = store.activeStudents
        guard !students.isEmpty else { throw SMError.needsLogin }
        let tagStudents = students.count > 1

        var snapshots: [String: Snapshot] = [:]
        var events: [ChangeEvent] = []
        var lastError: Error?

        for student in students {
            let old = store.snapshot(for: student.id)
            do {
                let new = store.isDemo
                    ? DemoData.snapshot(for: student, previous: old)
                    : try await fetch(student: student, previous: old)
                var studentEvents = ChangeDetector.diff(old: old, new: new)
                if tagStudents {
                    for index in studentEvents.indices { studentEvents[index].student = student.firstname }
                }
                events += studentEvents
                store.save(new)
                snapshots[student.id] = new
            } catch SMError.needsLogin {
                throw SMError.needsLogin
            } catch {
                lastError = error
                if let old { snapshots[student.id] = old }
            }
        }
        if snapshots.isEmpty, let lastError { throw lastError }
        WidgetBridge.publish()

        events = Self.mergeDuplicates(events)
        if !events.isEmpty {
            // Nachrichten haben ihren eigenen Tab – der Verlauf bleibt bei Plan, Briefen & Co.
            store.history = events.filter { $0.kind != .newMessage } + store.history
            if notify { await NotificationManager.deliver(events) }
        }
        return SyncResult(snapshots: snapshots, events: events)
    }

    /// Nachrichten, Pinnwand, Termine und gemeinsame Elternbriefe kommen bei jedem Kind gleich an –
    /// daraus wird ein Ereignis mit allen betroffenen Kindern („Mia, Ben“).
    static func mergeDuplicates(_ events: [ChangeEvent]) -> [ChangeEvent] {
        var result: [ChangeEvent] = []
        var indexByKey: [String: Int] = [:]
        for event in events {
            let key = "\(event.kind.rawValue)|\(event.title)|\(event.body)|\(event.date ?? "")"
            if let index = indexByKey[key] {
                if let name = event.student, let existing = result[index].student, !existing.contains(name) {
                    result[index].student = existing + ", " + name
                }
            } else {
                indexByKey[key] = result.count
                result.append(event)
            }
        }
        return result
    }

    private func fetch(student: Student, previous: Snapshot?) async throws -> Snapshot {
        let weekStart = SchoolCalendar.schoolWeekStart()
        let rangeEnd = SchoolCalendar.addDays(13, to: weekStart) // diese + nächste Woche
        let today = SchoolCalendar.today
        let studentParam = student.raw.object != nil ? student.raw : ["id": .string(student.id)]

        let results = try await api.call([
            APICall(module: "schedules", endpoint: "get-actual-lessons", parameters: [
                "student": studentParam, "start": .string(weekStart), "end": .string(rangeEnd),
            ]),
            APICall(module: "schedules", endpoint: "get-class-hours"),
            APICall(module: "classbook", endpoint: "get-homework", parameters: ["student": studentParam]),
            APICall(module: "exams", endpoint: "get-exams", parameters: [
                // Ab Wochenanfang, damit der Wochenplan auch Arbeiten der vergangenen Tage zeigt.
                "student": studentParam, "start": .string(weekStart), "end": .string(SchoolCalendar.addDays(120, to: today)),
            ]),
            APICall(module: "messenger", endpoint: "get-subscriptions", parameters: ["all": true, "includeArchived": false]),
            APICall(module: "letters", endpoint: "get-letters", parameters: [:]),
            APICall(module: "main", endpoint: "get-tiles"),
            APICall(module: "calendar", endpoint: "get-events-for-user", parameters: [
                "start": .string(SchoolCalendar.addDays(-7, to: today)),
                "end": .string(SchoolCalendar.addDays(180, to: today)),
                "includeHolidays": true,
            ]),
            APICall(module: "calendar", endpoint: "get-event-categories"),
            APICall(module: "main", endpoint: "get-active-modules"),
            // Aktuelles Schuljahr – Fehlzeiten, Noten und Ganztag brauchen es wie in der Web-App.
            APICall(module: "main", endpoint: "get-current-term"),
        ])

        let samePerson = previous?.studentId == student.id
        var failed: [String] = []
        var snapshot = Snapshot(
            studentId: student.id, fetchedAt: .now, rangeStart: weekStart, rangeEnd: rangeEnd,
            lessons: [], homework: [], exams: []
        )

        // Schlägt ein Modul fehl, behalten wir den alten Stand. Sonst sähe jede Stunde wie gestrichen aus.
        if results[0].ok {
            snapshot.lessons = Parsers.lessons(from: results[0].data, classHours: results[1].ok ? results[1].data : nil)
        } else {
            failed.append("Stundenplan")
            if samePerson, let previous {
                snapshot.lessons = previous.lessons
                snapshot.rangeStart = previous.rangeStart
                snapshot.rangeEnd = previous.rangeEnd
            }
        }
        if results[2].ok {
            snapshot.homework = Parsers.homework(from: results[2].data)
        } else {
            failed.append("Hausaufgaben")
            if samePerson { snapshot.homework = previous?.homework ?? [] }
        }
        if results[3].ok {
            snapshot.exams = Parsers.exams(from: results[3].data)
        } else {
            failed.append("Arbeiten")
            if samePerson { snapshot.exams = previous?.exams ?? [] }
        }
        if results[4].ok {
            snapshot.threads = Parsers.threads(from: results[4].data)
        } else {
            failed.append("Nachrichten")
            if samePerson { snapshot.threads = previous?.threads }
        }
        if results[5].ok {
            snapshot.letters = Parsers.letters(from: results[5].data, studentId: student.id)
        } else {
            failed.append("Elternbriefe")
            if samePerson { snapshot.letters = previous?.letters }
        }
        if results[6].ok {
            snapshot.tiles = Parsers.tiles(from: results[6].data)
        } else {
            failed.append("Pinnwand")
            if samePerson { snapshot.tiles = previous?.tiles }
        }
        if results[7].ok {
            snapshot.events = Parsers.events(from: results[7].data, categories: results[8].ok ? results[8].data : nil)
        } else {
            failed.append("Termine")
            if samePerson { snapshot.events = previous?.events }
        }
        snapshot.modules = results[9].ok ? Parsers.modules(from: results[9].data) : previous?.modules
        snapshot.failedModules = failed
        let term = results[safe: 10].flatMap { $0.ok ? $0.data : nil }
        await fetchOptionalModules(into: &snapshot, student: student, term: term, previous: samePerson ? previous : nil)

        if failed.count >= 3, !results[0].ok, !results[2].ok, !results[3].ok {
            throw SMError.server("Schulmanager hat keine Daten geliefert (Status \(results[0].status)).")
        }
        return snapshot
    }

    /// Modulnamen, unter denen die Schule ein Modul führen kann (laut `get-active-modules`).
    static let moduleAliases: [String: [String]] = [
        "grades": ["grades"],
        "absences": ["classbook", "absences", "sick"],
        "exemptions": ["exemptions"],
        "allday": ["allday"],
        "invoices": ["invoicing", "invoices", "payments"],
        "parenttalks": ["parenttalks", "parent-talks"],
    ]

    /// Zusatzmodule in einem eigenen Aufruf – ein Fehler dort darf den Stundenplan nie gefährden.
    /// Abgefragt wird nur, was die Schule laut Modulliste aktiv hat.
    private func fetchOptionalModules(into snapshot: inout Snapshot, student: Student, term: JSONValue?, previous: Snapshot?) async {
        let active = Set((snapshot.modules ?? []).map(\.name))
        func isActive(_ key: String) -> Bool { !(Self.moduleAliases[key] ?? []).filter(active.contains).isEmpty }

        var calls: [APICall] = []
        var ranges: [String: Range<Int>] = [:]
        func add(_ key: String, _ newCalls: [APICall]) {
            ranges[key] = calls.count..<(calls.count + newCalls.count)
            calls += newCalls
        }
        let studentId = Poqa.numericId(student.id)
        let termId = term?["id"] ?? .null

        if isActive("grades") {
            add("grades", [APICall(module: "grades", endpoint: "get-grading-information-for-student",
                                   parameters: ["studentId": studentId, "termId": termId])])
        }
        if isActive("absences") {
            add("absences", [APICall(module: "classbook", endpoint: "get-history-absences-list",
                                     parameters: ["term": term ?? .null, "student": ["id": studentId]])])
        }
        if isActive("exemptions") {
            add("exemptions", Poqa.call(model: "modules/exemptions/exemption-request",
                                        options: ["where": ["studentId": studentId], "order": [["startDate", "DESC"]]],
                                        module: "exemptions"))
        }
        if isActive("allday") {
            add("alldayOffers", [APICall(module: "allday", endpoint: "get-allday-offers",
                                         parameters: ["studentId": studentId, "termId": termId])])
            add("alldayNotes", [APICall(module: "allday", endpoint: "get-allday-messages-for-student",
                                        parameters: ["studentId": studentId, "termId": termId])])
        }
        if isActive("invoices") {
            add("invoices", Poqa.call(model: "modules/invoicing/student-invoice",
                                      options: ["where": ["studentId": studentId], "order": [["id", "DESC"]], "limit": 60],
                                      module: "invoicing"))
            add("invoiceItems", Poqa.call(model: "modules/invoicing/student-item", module: "invoicing"))
        }
        if isActive("parenttalks") {
            add("rounds", Poqa.call(model: "modules/parenttalks/round", options: ["order": [["start", "DESC"]], "limit": 10],
                                    module: "parenttalks"))
            add("appointments", Poqa.call(model: "modules/parenttalks/appointment",
                                          options: ["include": [["association": "teacher", "required": false]]],
                                          module: "parenttalks"))
        }

        // Alte Werte übernehmen; nur Erfolgreiches wird überschrieben.
        snapshot.grades = previous?.grades
        snapshot.absences = previous?.absences
        snapshot.exemptions = previous?.exemptions
        snapshot.alldayOffers = previous?.alldayOffers
        snapshot.alldayNotes = previous?.alldayNotes
        snapshot.invoices = previous?.invoices
        snapshot.parentTalks = previous?.parentTalks
        guard !calls.isEmpty, let results = try? await api.call(calls) else { return }

        func result(_ key: String) -> APIResult? {
            guard let range = ranges[key] else { return nil }
            return Poqa.first(results[range])
        }

        if let grades = result("grades") { snapshot.grades = Parsers.grades(from: grades.data) }
        if let absences = result("absences") { snapshot.absences = Parsers.absences(from: absences.data) }
        if let exemptions = result("exemptions") { snapshot.exemptions = Parsers.exemptions(from: exemptions.data) }
        if let offers = result("alldayOffers") { snapshot.alldayOffers = Parsers.alldayOffers(from: offers.data) }
        if let notes = result("alldayNotes") { snapshot.alldayNotes = Parsers.alldayNotes(from: notes.data) }
        if let rounds = result("rounds") {
            snapshot.parentTalks = Parsers.parentTalks(rounds: rounds.data, appointments: result("appointments")?.data)
        }
        if let invoices = result("invoices") {
            let items = result("invoiceItems")?.data
            // Namen der Posten stehen in einem dritten Modell – nur nachladen, wenn es Posten gibt.
            let generalIds = Array(Set((items?.array ?? []).compactMap { $0["generalItemId"]?.string })).map(Poqa.numericId)
            var names: JSONValue?
            if !generalIds.isEmpty,
               let nameResults = try? await api.call(Poqa.call(
                   model: "modules/invoicing/general-item",
                   options: ["where": ["id": ["$in": .array(generalIds)]], "attributes": ["id", "name"]],
                   module: "invoicing")) {
                names = Poqa.first(nameResults[...])?.data
            }
            snapshot.invoices = Parsers.invoices(from: invoices.data, items: items, itemNames: names)
        }
    }
}

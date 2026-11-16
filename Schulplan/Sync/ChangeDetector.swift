import Foundation

/// Vergleicht zwei Abrufe und erzeugt daraus Ereignisse für Mitteilungen und Verlauf.
enum ChangeDetector {
    static func diff(old: Snapshot?, new: Snapshot, today: String = SchoolCalendar.today, now: Date = .now) -> [ChangeEvent] {
        // Ohne Vergleichsbasis (erster Abruf, anderes Kind) gibt es nichts zu melden.
        guard let old, old.studentId == new.studentId else { return [] }
        return lessonEvents(old: old, new: new, today: today, now: now)
            + examEvents(old: old, new: new, today: today, now: now)
            + homeworkEvents(old: old, new: new, today: today, now: now)
            + messageEvents(old: old, new: new, now: now)
            + letterEvents(old: old, new: new, now: now)
            + tileEvents(old: old, new: new, now: now)
            + calendarEvents(old: old, new: new, today: today, now: now)
            + moduleEvents(old: old, new: new, now: now)
    }

    /// Noten, Fehlzeiten, Beurlaubungen, Rechnungen, Ganztag, Elternsprechtag.
    /// Jeweils erst vergleichen, wenn beide Stände das Modul enthalten.
    private static func moduleEvents(old: Snapshot, new: Snapshot, now: Date) -> [ChangeEvent] {
        var events: [ChangeEvent] = []

        if let before = old.grades, let after = new.grades {
            let known = Set(before.flatMap { $0.grades.map(\.id) })
            for subject in after {
                for grade in subject.grades where !known.contains(grade.id) {
                    events.append(ChangeEvent(kind: .newGrade, detectedAt: now, date: grade.date,
                                              title: "Neue Note · \(subject.subject)",
                                              body: [grade.value, grade.type, grade.comment].compactMap { $0 }.joined(separator: " · ")))
                }
            }
        }

        if let before = old.absences, let after = new.absences {
            let known = Set(before.map(\.id))
            for absence in after where !known.contains(absence.id) {
                var when = "\(SchoolCalendar.shortWeekday(absence.date)) \(SchoolCalendar.dayMonth(absence.date))"
                if let from = absence.from { when += ", \(from)" + (absence.until.map { "–\($0)" } ?? "") }
                events.append(ChangeEvent(kind: .newAbsence, detectedAt: now, date: absence.date,
                                          title: absence.excused ? "Fehlzeit eingetragen" : "Fehlzeit – Entschuldigung fehlt",
                                          body: [when, absence.reason].compactMap { $0 }.joined(separator: " · ")))
            }
        }

        if let before = old.exemptions, let after = new.exemptions {
            let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for exemption in after {
                guard let granted = exemption.granted, previous[exemption.id]?.granted == nil, previous[exemption.id] != nil else { continue }
                events.append(ChangeEvent(kind: .exemptionDecided, detectedAt: now, date: exemption.startDate,
                                          title: granted ? "Beurlaubung genehmigt" : "Beurlaubung abgelehnt",
                                          body: ["\(SchoolCalendar.dayMonth(exemption.startDate))–\(SchoolCalendar.dayMonth(exemption.endDate))",
                                                 exemption.feedback].compactMap { $0 }.joined(separator: " · ")))
            }
        }

        if let before = old.invoices, let after = new.invoices {
            let known = Set(before.map(\.id))
            for invoice in after where !known.contains(invoice.id) && !invoice.paid {
                let sum = invoice.sum.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))) }
                events.append(ChangeEvent(kind: .newInvoice, detectedAt: now, date: nil, title: "Neue Rechnung",
                                          body: [sum, invoice.dueDate.map { "fällig \(SchoolCalendar.dayMonth($0))" }]
                                            .compactMap { $0 }.joined(separator: " · ")))
            }
        }

        if let before = old.alldayNotes, let after = new.alldayNotes {
            let known = Set(before.map(\.id))
            for note in after where !known.contains(note.id) {
                events.append(ChangeEvent(kind: .alldayNote, detectedAt: now, date: note.date, title: "Ganztag", body: note.message))
            }
        }

        if let before = old.parentTalks, let after = new.parentTalks {
            let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for round in after {
                if let old = previous[round.id] {
                    if round.isOpenForBooking, !old.isOpenForBooking {
                        events.append(ChangeEvent(kind: .parentTalk, detectedAt: now, date: nil,
                                                  title: "Elternsprechtag: Anmeldung offen", body: round.label))
                    }
                    let oldIds = Set(old.appointments.map(\.id))
                    for appointment in round.appointments where !oldIds.contains(appointment.id) {
                        events.append(ChangeEvent(kind: .parentTalk, detectedAt: now, date: nil,
                                                  title: "Elternsprechtag-Termin", body: [appointment.teacher, appointment.start
                                                    .flatMap(ISODate.parseFlexible)
                                                    .map { $0.formatted(.dateTime.weekday().day().month().hour().minute().locale(Locale(identifier: "de_DE"))) }]
                                                    .compactMap { $0 }.joined(separator: " · ")))
                    }
                } else {
                    events.append(ChangeEvent(kind: .parentTalk, detectedAt: now, date: nil,
                                              title: "Neuer Elternsprechtag", body: round.label))
                }
            }
        }
        return events
    }

    private static func letterEvents(old: Snapshot, new: Snapshot, now: Date) -> [ChangeEvent] {
        guard let before = old.letters, let after = new.letters else { return [] }
        let known = Set(before.map(\.id))
        return after.filter { !known.contains($0.id) }.map { letter in
            var body = "von \(letter.sender)"
            if letter.needsAction { body += " · Bitte bestätigen" }
            if let deadline = letter.answerDeadline.flatMap(ISODate.parseFlexible) {
                body += " bis \(SchoolCalendar.dayMonth(SchoolCalendar.iso(deadline)))"
            }
            return ChangeEvent(kind: .newLetter, detectedAt: now, date: nil, title: "Elternbrief · \(letter.title)", body: body)
        }
    }

    private static func tileEvents(old: Snapshot, new: Snapshot, now: Date) -> [ChangeEvent] {
        guard let before = old.tiles, let after = new.tiles else { return [] }
        let previous = Dictionary(before.map { ($0.id, $0.contentHash) }, uniquingKeysWith: { first, _ in first })
        return after.compactMap { tile in
            let isNew = previous[tile.id] == nil
            guard isNew || previous[tile.id] != tile.contentHash else { return nil }
            return ChangeEvent(kind: .tileChanged, detectedAt: now, date: nil,
                               title: (isNew ? "Neu auf der Pinnwand · " : "Pinnwand aktualisiert · ") + tile.title,
                               body: String(tile.content.prefix(180)))
        }
    }

    private static func calendarEvents(old: Snapshot, new: Snapshot, today: String, now: Date) -> [ChangeEvent] {
        guard let before = old.events, let after = new.events else { return [] }
        let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Nur Termine melden, die beide Abrufe abdecken könnten (nicht das neu ins Fenster gerutschte Ende).
        let horizon = SchoolCalendar.addDays(150, to: today)
        return after.compactMap { event in
            guard event.lastDay >= today, event.day <= horizon, !event.isHoliday else { return nil }
            var when = "\(SchoolCalendar.shortWeekday(event.day)) \(SchoolCalendar.dayMonth(event.day))"
            if let time = event.timeLabel { when += ", \(time)" }
            if let location = event.location { when += " · \(location)" }
            if let old = previous[event.id] {
                guard old.fingerprint != event.fingerprint else { return nil }
                return ChangeEvent(kind: .eventChanged, detectedAt: now, date: event.day,
                                   title: "Termin geändert · \(event.title)", body: when)
            }
            // Wiederkehrende Termine bekommen über den Beginn eine neue Id – verschobene erkennen wir am Titel.
            if let moved = before.first(where: { $0.title == event.title && !after.contains($0) && $0.lastDay >= today }) {
                return ChangeEvent(kind: .eventChanged, detectedAt: now, date: event.day,
                                   title: "Termin verschoben · \(event.title)",
                                   body: "\(when)\nvorher \(SchoolCalendar.shortWeekday(moved.day)) \(SchoolCalendar.dayMonth(moved.day))")
            }
            return ChangeEvent(kind: .newEvent, detectedAt: now, date: event.day, title: "Neuer Termin · \(event.title)", body: when)
        }
    }

    /// Neue ungelesene Nachrichten: neuer Thread mit Ungelesenem oder neuere letzte Nachricht.
    private static func messageEvents(old: Snapshot, new: Snapshot, now: Date) -> [ChangeEvent] {
        // Erst vergleichen, wenn beide Stände Nachrichten enthalten – sonst meldet der erste Abruf alles.
        guard let oldThreads = old.threads, let newThreads = new.threads else { return [] }
        let previous = Dictionary(oldThreads.map { ($0.subscriptionId, $0) }, uniquingKeysWith: { first, _ in first })
        return newThreads.compactMap { thread in
            guard thread.unreadCount > 0 else { return nil }
            if let before = previous[thread.subscriptionId] {
                let newer = (thread.lastMessageAt ?? "") > (before.lastMessageAt ?? "")
                guard newer || thread.unreadCount > before.unreadCount else { return nil }
            }
            return ChangeEvent(
                kind: .newMessage,
                detectedAt: now,
                date: nil,
                title: thread.sender.isEmpty ? thread.subject : "\(thread.sender) · \(thread.subject)",
                body: thread.preview ?? "Neue Nachricht"
            )
        }
    }

    private static func lessonEvents(old: Snapshot, new: Snapshot, today: String, now: Date) -> [ChangeEvent] {
        // Nur Tage vergleichen, die beide Abrufe abdecken und noch nicht vorbei sind.
        let from = max(old.rangeStart, new.rangeStart, today)
        let to = min(old.rangeEnd, new.rangeEnd)
        guard from <= to else { return [] }
        let inRange = { (lesson: Lesson) in lesson.date >= from && lesson.date <= to }

        let oldLessons = Dictionary(old.lessons.filter(inRange).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newLessons = Dictionary(new.lessons.filter(inRange).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newSlots = Set(newLessons.values.map { "\($0.date)|\($0.hour)" })

        var events: [ChangeEvent] = []
        for lesson in new.lessons where newLessons[lesson.id] == lesson {
            if let previous = oldLessons[lesson.id] {
                guard previous.fingerprint != lesson.fingerprint else { continue }
                if lesson.state == .regular, previous.state != .regular {
                    events.append(event(.restored, lesson, now: now, previous: previous))
                } else {
                    events.append(event(kind(for: lesson.state), lesson, now: now, previous: previous))
                }
            } else if lesson.state != .regular {
                events.append(event(kind(for: lesson.state), lesson, now: now, previous: nil))
            }
        }

        // Stunde ist ganz aus dem Plan verschwunden und nichts anderes steht in dem Slot.
        for lesson in old.lessons where oldLessons[lesson.id] == lesson && newLessons[lesson.id] == nil {
            guard lesson.state != .cancelled, !newSlots.contains("\(lesson.date)|\(lesson.hour)") else { continue }
            var gone = lesson
            gone.state = .cancelled
            events.append(event(.cancelled, gone, now: now, previous: nil))
        }
        return events
    }

    private static func examEvents(old: Snapshot, new: Snapshot, today: String, now: Date) -> [ChangeEvent] {
        let known = Set(old.exams.map(\.id))
        return new.exams.filter { !known.contains($0.id) && $0.date >= today }.map { exam in
            ChangeEvent(
                kind: .newExam,
                detectedAt: now,
                date: exam.date,
                title: "Neue \(exam.type ?? "Arbeit") · \(exam.subject)",
                body: ["\(SchoolCalendar.shortWeekday(exam.date)) \(SchoolCalendar.dayMonth(exam.date))", exam.start.map { "ab \($0) Uhr" }, exam.comment]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    private static func homeworkEvents(old: Snapshot, new: Snapshot, today: String, now: Date) -> [ChangeEvent] {
        let known = Set(old.homework.map(\.id))
        // Ältere Einträge, die erst durch ein größeres Zeitfenster sichtbar werden, nicht melden.
        let cutoff = SchoolCalendar.addDays(-3, to: today)
        return new.homework.filter { !known.contains($0.id) && ($0.due ?? $0.date) >= cutoff }.map { item in
            ChangeEvent(
                kind: .newHomework,
                detectedAt: now,
                date: item.due ?? item.date,
                title: "Hausaufgabe · \(item.subject)",
                body: item.text
            )
        }
    }

    private static func kind(for state: LessonState) -> ChangeEvent.Kind {
        switch state {
        case .cancelled: .cancelled
        case .substitution: .substitution
        case .roomChange: .roomChange
        case .added: .added
        case .regular: .changed
        }
    }

    static func event(_ kind: ChangeEvent.Kind, _ lesson: Lesson, now: Date, previous: Lesson?) -> ChangeEvent {
        let subject = lesson.originalSubject ?? previous?.subject ?? lesson.subject
        let title: String
        var details: [String] = []

        switch kind {
        case .cancelled:
            title = "Entfall · \(subject)"
            if let teacher = lesson.originalTeacher ?? lesson.teacher { details.append("bei \(teacher)") }
        case .substitution:
            title = "Vertretung · \(subject)"
            var line = lesson.subject
            if let teacher = lesson.teacher { line += " bei \(teacher)" }
            if let room = lesson.room { line += " in \(room)" }
            details.append(line)
            if let teacher = lesson.originalTeacher, teacher != lesson.teacher { details.append("statt \(teacher)") }
        case .roomChange:
            title = "Raumänderung · \(lesson.subject)"
            details.append("Raum \(lesson.room ?? "?")" + (lesson.originalRoom.map { " statt \($0)" } ?? ""))
        case .added:
            title = "Zusätzliche Stunde · \(lesson.subject)"
            details.append([lesson.teacher, lesson.room.map { "Raum \($0)" }].compactMap { $0 }.joined(separator: " · "))
        case .restored:
            title = "Findet wieder statt · \(lesson.subject)"
            details.append([lesson.teacher, lesson.room.map { "Raum \($0)" }].compactMap { $0 }.joined(separator: " · "))
        default:
            title = "Planänderung · \(lesson.subject)"
            details.append([lesson.teacher, lesson.room.map { "Raum \($0)" }].compactMap { $0 }.joined(separator: " · "))
        }
        if let comment = lesson.comment { details.append(comment) }

        var when = "\(SchoolCalendar.shortWeekday(lesson.date)) \(SchoolCalendar.dayMonth(lesson.date)), \(lesson.hourLabel). Stunde"
        if let start = lesson.start { when += " (\(start))" }
        let body = ([when] + details.filter { !$0.isEmpty }).joined(separator: "\n")
        return ChangeEvent(kind: kind, detectedAt: now, date: lesson.date, title: title, body: body)
    }
}

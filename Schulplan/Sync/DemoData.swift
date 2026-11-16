import Foundation

/// Beispieldaten zum Ausprobieren ohne Konto. Jeder Abruf ändert eine zufällige Stunde,
/// damit man Mitteilungen und Verlauf live sieht.
enum DemoData {
    static let students = [
        Student(id: "demo", firstname: "Mia", lastname: "Beispiel", className: "7b", raw: ["id": "demo"]),
        Student(id: "demo2", firstname: "Ben", lastname: "Beispiel", className: "3a", raw: ["id": "demo2"]),
    ]

    private struct Subject {
        var name: String
        var abbr: String
        var teacher: String
        var room: String
    }

    private static let subjects: [String: Subject] = [
        "M": Subject(name: "Mathematik", abbr: "M", teacher: "Kar", room: "204"),
        "D": Subject(name: "Deutsch", abbr: "D", teacher: "Hof", room: "204"),
        "E": Subject(name: "Englisch", abbr: "E", teacher: "Sch", room: "112"),
        "BIO": Subject(name: "Biologie", abbr: "Bio", teacher: "Lan", room: "N1"),
        "PH": Subject(name: "Physik", abbr: "Ph", teacher: "Wei", room: "N3"),
        "G": Subject(name: "Geschichte", abbr: "G", teacher: "Beck", room: "108"),
        "SP": Subject(name: "Sport", abbr: "Sp", teacher: "Mül", room: "TH1"),
        "KU": Subject(name: "Kunst", abbr: "Ku", teacher: "Roth", room: "K2"),
        "MU": Subject(name: "Musik", abbr: "Mu", teacher: "Vog", room: "M1"),
        "F": Subject(name: "Französisch", abbr: "F", teacher: "Dub", room: "115"),
        "INF": Subject(name: "Informatik", abbr: "Inf", teacher: "Klein", room: "PC1"),
        "REL": Subject(name: "Religion", abbr: "Rel", teacher: "Pf", room: "109"),
    ]

    private static let week: [[String]] = [
        ["M", "M", "D", "E", "BIO", "G"],
        ["E", "D", "SP", "SP", "F", "MU", "INF"],
        ["PH", "M", "D", "KU", "KU", "REL"],
        ["F", "E", "M", "G", "BIO", "D", "SP"],
        ["D", "INF", "E", "M", "PH"],
    ]

    private static let times = [
        ("07:55", "08:40"), ("08:45", "09:30"), ("09:50", "10:35"), ("10:40", "11:25"),
        ("11:40", "12:25"), ("12:30", "13:15"), ("14:00", "14:45"), ("14:45", "15:30"),
    ]

    static func snapshot(for student: Student, previous: Snapshot?) -> Snapshot {
        let weekStart = SchoolCalendar.schoolWeekStart()
        let rangeEnd = SchoolCalendar.addDays(13, to: weekStart)

        guard let previous, previous.studentId == student.id, previous.rangeStart == weekStart else {
            return Snapshot(
                studentId: student.id, fetchedAt: .now, rangeStart: weekStart, rangeEnd: rangeEnd,
                lessons: baseLessons(weekStart: weekStart, shift: student.id == "demo" ? 0 : 2),
                homework: student.id == "demo" ? homework() : Array(homework().prefix(1)),
                exams: student.id == "demo" ? exams() : [],
                threads: DemoMessenger.shared.threads(previous: nil),
                letters: letters(), tiles: tiles(), events: events(), modules: modules()
            ).withDemoModules(for: student)
        }

        var next = previous
        next.fetchedAt = .now
        mutateRandomLesson(&next.lessons)
        DemoMessenger.shared.maybeReceive()
        next.threads = DemoMessenger.shared.threads(previous: previous.threads)
        if next.letters == nil { next.letters = letters(); next.tiles = tiles(); next.events = events(); next.modules = modules() }
        if next.grades == nil { next = next.withDemoModules(for: student) }
        next.modules = modules()
        // Ab und zu kommt eine neue Note dazu.
        if Int.random(in: 0..<4) == 0, var subjects = next.grades, !subjects.isEmpty {
            let index = Int.random(in: 0..<subjects.count)
            let value = ["1", "2+", "2", "2-", "3", "1-"].randomElement()!
            subjects[index].grades.insert(Grade(id: UUID().uuidString, value: value, numeric: Parsers.decodeGrade(.string(value), system: 0).numeric,
                                                weight: 1, type: "Stegreifaufgabe", date: SchoolCalendar.today, comment: nil), at: 0)
            next.grades = subjects
        }
        // Ab und zu kommt ein neuer Elternbrief dazu.
        if Int.random(in: 0..<4) == 0 {
            next.letters?.insert(Letter(id: "l\(Int.random(in: 100...9999))", title: "Information zum Schwimmunterricht",
                                        sender: "Schulleitung", sentAt: ISO8601DateFormatter().string(from: .now),
                                        answerDeadline: nil, statusId: "st-new", confirmed: false, questionCount: 0), at: 0)
        }
        return next
    }

    /// `shift` verschiebt die Wochentage, damit das zweite Kind einen anderen Plan hat.
    private static func baseLessons(weekStart: String, shift: Int) -> [Lesson] {
        var lessons: [Lesson] = []
        for dayOffset in 0..<14 {
            let weekday = dayOffset % 7
            guard weekday < 5 else { continue }
            let date = SchoolCalendar.addDays(dayOffset, to: weekStart)
            for (index, key) in week[(weekday + shift) % week.count].enumerated() {
                guard let subject = subjects[key] else { continue }
                let number = index + 1
                lessons.append(Lesson(
                    id: "\(date)|\(number)|\(subject.name)", date: date, hour: "\(number)", hourSort: number,
                    start: times[index].0, end: times[index].1, subject: subject.name, subjectAbbr: subject.abbr,
                    teacher: subject.teacher, room: subject.room, state: .regular
                ))
            }
        }

        // Ein paar Änderungen, damit der Plan nicht leer wirkt.
        let today = SchoolCalendar.today
        let upcoming = lessons.indices.filter { lessons[$0].date >= today }
        if let index = upcoming.first(where: { lessons[$0].hourSort == 3 }) { apply(.cancelled, to: &lessons[index]) }
        if let index = upcoming.dropFirst(6).first(where: { lessons[$0].hourSort == 2 }) { apply(.substitution, to: &lessons[index]) }
        if let index = upcoming.dropFirst(12).first(where: { lessons[$0].hourSort == 4 }) { apply(.roomChange, to: &lessons[index]) }
        return lessons
    }

    private static func mutateRandomLesson(_ lessons: inout [Lesson]) {
        let today = SchoolCalendar.today
        let candidates = lessons.indices.filter { lessons[$0].date >= today && lessons[$0].date <= SchoolCalendar.addDays(3, to: today) }
        guard let index = candidates.randomElement() else { return }
        if lessons[index].state != .regular {
            restore(&lessons[index])
        } else {
            apply([.cancelled, .substitution, .roomChange].randomElement()!, to: &lessons[index])
        }
    }

    private static func apply(_ state: LessonState, to lesson: inout Lesson) {
        lesson.originalSubject = lesson.subject
        lesson.originalTeacher = lesson.teacher
        lesson.originalRoom = lesson.room
        lesson.state = state
        switch state {
        case .cancelled:
            lesson.comment = ["Lehrkraft erkrankt", "Exkursion", "Fortbildung", nil].randomElement()!
        case .substitution:
            let other = subjects.values.filter { $0.name != lesson.subject }.randomElement()!
            lesson.subject = other.name
            lesson.subjectAbbr = other.abbr
            lesson.teacher = other.teacher
            lesson.comment = "Aufgaben im Kursraum"
        case .roomChange:
            lesson.room = ["A013", "112", "Aula", "N2", "B204"].filter { $0 != lesson.room }.randomElement()!
            lesson.comment = nil
        default:
            break
        }
    }

    private static func restore(_ lesson: inout Lesson) {
        lesson.subject = lesson.originalSubject ?? lesson.subject
        lesson.teacher = lesson.originalTeacher ?? lesson.teacher
        lesson.room = lesson.originalRoom ?? lesson.room
        lesson.subjectAbbr = subjects.values.first { $0.name == lesson.subject }?.abbr
        lesson.originalSubject = nil
        lesson.originalTeacher = nil
        lesson.originalRoom = nil
        lesson.comment = nil
        lesson.state = .regular
    }

    private static func letters() -> [Letter] {
        let iso = ISO8601DateFormatter()
        return [
            Letter(id: "l1", title: "Einladung zum Elternabend der 7b", sender: "Frau Hofmann",
                   sentAt: iso.string(from: .now.addingTimeInterval(-3600 * 20)),
                   answerDeadline: SchoolCalendar.addDays(4, to: SchoolCalendar.today), statusId: "st1", confirmed: false, questionCount: 0),
            Letter(id: "l2", title: "Skilager 2027 – verbindliche Anmeldung", sender: "Herr Müller",
                   sentAt: iso.string(from: .now.addingTimeInterval(-3600 * 70)),
                   answerDeadline: SchoolCalendar.addDays(10, to: SchoolCalendar.today), statusId: "st2", confirmed: false, questionCount: 2),
            Letter(id: "l3", title: "Hinweise zur Notengebung im Halbjahr", sender: "Schulleitung",
                   sentAt: iso.string(from: .now.addingTimeInterval(-3600 * 24 * 9)), answerDeadline: nil,
                   statusId: "st3", confirmed: true, questionCount: 0),
        ]
    }

    static func letterDetail(_ letter: Letter) -> LetterDetail {
        switch letter.id {
        case "l1":
            LetterDetail(text: "Liebe Eltern", html: "<p>Liebe Eltern der f&uuml;nften Klassen,<br> herzlich willkommen!</p><p>hiermit laden wir Sie zum <strong>Elternabend der Klasse 7b</strong> am kommenden Donnerstag um 19:00 Uhr in Raum 204 ein.</p><p>Themen:</p><ul><li>Wandertag</li><li>Skilager &ndash; Kosten &amp; Anmeldung</li><li>Leistungsstand</li></ul><p>Mehr Infos auf <a href=\"https://example.org\">unserer Website</a>.</p><p>Viele Gr&uuml;&szlig;e<br> S. Hofmann</p>", attachments: [StoredFile(name: "Tagesordnung.pdf", descriptor: .null)])
        case "l2":
            LetterDetail(text: "Liebe Eltern,\n\ndas Skilager findet vom 18. bis 23. Januar statt. Bitte melden Sie Ihr Kind über die Rückmeldung verbindlich an und geben Sie die Schuhgröße für den Skiverleih an.", attachments: [StoredFile(name: "Packliste.pdf", descriptor: .null), StoredFile(name: "Kosten.pdf", descriptor: .null)])
        default:
            LetterDetail(text: "Sehr geehrte Eltern,\n\nanbei finden Sie wichtige Hinweise zur Notengebung im ersten Halbjahr.", attachments: [])
        }
    }

    private static func tiles() -> [Tile] {
        [
            Tile(id: "t1", title: "Krankmeldungen", content: "Bitte melden Sie Ihr Kind bis 7:45 Uhr über den Schulmanager krank. Ab dem dritten Krankheitstag ist ein ärztliches Attest erforderlich.", pinned: true, order: 0),
            Tile(id: "t2", title: "Fundsachen", content: "Die Fundkiste wird vor den Weihnachtsferien geleert. Nicht abgeholte Sachen gehen an die Kleiderkammer.", pinned: false, order: 1),
        ]
    }

    private static func events() -> [SchoolEvent] {
        let today = SchoolCalendar.today
        return [
            SchoolEvent(id: "e1@1", title: "Wandertag 7. Klassen", start: SchoolCalendar.addDays(4, to: today), end: nil, allDay: true,
                        location: "Treffpunkt Haupteingang", details: nil, category: "Ausflug", colorHex: "#E5533D", isHoliday: false),
            SchoolEvent(id: "e2@1", title: "Elternabend 7b", start: SchoolCalendar.addDays(3, to: today) + "T18:00:00.000Z",
                        end: SchoolCalendar.addDays(3, to: today) + "T19:30:00.000Z", allDay: false,
                        location: "Raum 204", details: nil, category: "Elternabend", colorHex: "#3D7BE5", isHoliday: false),
            SchoolEvent(id: "e3@1", title: "Weihnachtsferien", start: "2026-12-23", end: "2027-01-09", allDay: true,
                        location: nil, details: nil, category: "Ferien", colorHex: nil, isHoliday: true),
            SchoolEvent(id: "e4@1", title: "Weihnachtsbasar", start: "2026-12-05", end: nil, allDay: true,
                        location: "Aula", details: "Kuchenspenden bitte beim Elternbeirat anmelden.", category: "Schulfest", colorHex: "#2EAD6B", isHoliday: false),
        ]
    }

    private static func modules() -> [SchoolModule] {
        ["schedules", "classbook", "exams", "messenger", "letters", "calendar", "grades", "sick", "exemptions",
         "parenttalks", "documents", "allday", "electives", "invoicing"]
            .map { SchoolModule(name: $0, label: $0) }
    }

    private static func homework() -> [Homework] {
        let today = SchoolCalendar.today
        return [
            Homework(id: "hw1", subject: "Mathematik", date: today, due: SchoolCalendar.addDays(1, to: today),
                     text: "Buch S. 84, Nr. 3a–f und 5. Rechenweg aufschreiben!", teacher: "Kar"),
            Homework(id: "hw2", subject: "Englisch", date: today, due: SchoolCalendar.addDays(2, to: today),
                     text: "Workbook p. 42, ex. 1–3. Vocabulary Unit 3 lernen.", teacher: "Sch"),
            Homework(id: "hw3", subject: "Deutsch", date: SchoolCalendar.addDays(-1, to: today), due: SchoolCalendar.addDays(4, to: today),
                     text: "Inhaltsangabe zu „Die Brücke“ schreiben (max. 1 Seite).", teacher: "Hof"),
            Homework(id: "hw4", subject: "Biologie", date: SchoolCalendar.addDays(-2, to: today), due: today,
                     text: "Arbeitsblatt Zellaufbau fertigstellen.", teacher: "Lan"),
        ]
    }

    private static func exams() -> [Exam] {
        let today = SchoolCalendar.today
        return [
            Exam(id: "ex1", subject: "Mathematik", date: SchoolCalendar.addDays(5, to: today), start: "07:55", end: "09:30",
                 type: "Schulaufgabe", comment: "Lineare Funktionen"),
            Exam(id: "ex2", subject: "Englisch", date: SchoolCalendar.addDays(9, to: today), start: "09:50", end: "10:35",
                 type: "Stegreifaufgabe", comment: nil),
            Exam(id: "ex3", subject: "Biologie", date: SchoolCalendar.addDays(16, to: today), start: nil, end: nil,
                 type: "Test", comment: "Zelle & Mikroskop"),
        ]
    }

    // MARK: Zusatzmodule

    static func folder(_ id: String) -> (folders: [DocumentFolder], documents: [SchoolDocument]) {
        if id == "root" {
            return ([DocumentFolder(id: "f1", name: "Formulare"), DocumentFolder(id: "f2", name: "Schulordnung & Konzepte")],
                    [SchoolDocument(id: "d0", name: "Ferienplan 2026-27.pdf", file: StoredFile(name: "Ferienplan 2026-27.pdf", descriptor: .null))])
        }
        return ([], [
            SchoolDocument(id: "d1", name: "Antrag auf Beurlaubung.pdf", file: StoredFile(name: "Antrag auf Beurlaubung.pdf", descriptor: .null)),
            SchoolDocument(id: "d2", name: "Hinweise zur Krankmeldung", htmlText: "Bitte melden Sie Ihr Kind bis 7:45 Uhr krank."),
        ])
    }

    static func elections() -> [Election] {
        func elective(_ id: String, _ name: String) -> Elective { Elective(id: id, name: name, raw: ["id": .string(id), "name": .string(name)]) }
        return [
            Election(id: "w1", name: "Wahlkurse 2. Halbjahr", description: "Bitte drei Kurse nach Priorität ordnen.",
                     start: SchoolCalendar.addDays(-3, to: SchoolCalendar.today), end: SchoolCalendar.addDays(10, to: SchoolCalendar.today),
                     priorities: 3, finalized: false, subElectionId: nil,
                     electives: [elective("e1", "Schach"), elective("e2", "Theater"), elective("e3", "Robotik"), elective("e4", "Schulchor")]),
        ]
    }
}

extension Snapshot {
    func withDemoModules(for student: Student) -> Snapshot {
        var copy = self
        let today = SchoolCalendar.today
        func grade(_ id: String, _ value: String, _ type: String, _ days: Int) -> Grade {
            Grade(id: id, value: value, numeric: Parsers.decodeGrade(.string(value), system: 0).numeric, weight: type == "Schulaufgabe" ? 2 : 1,
                  type: type, date: SchoolCalendar.addDays(-days, to: today), comment: nil)
        }
        let prefix = student.id
        copy.grades = [
            GradeSubject(id: "\(prefix)-m", subject: "Mathematik", abbreviation: "M", system: 0,
                         grades: [grade("\(prefix)g1", "2", "Schulaufgabe", 12), grade("\(prefix)g2", "1-", "Stegreifaufgabe", 30)], finalGrade: nil),
            GradeSubject(id: "\(prefix)-d", subject: "Deutsch", abbreviation: "D", system: 0,
                         grades: [grade("\(prefix)g3", "3+", "Schulaufgabe", 20), grade("\(prefix)g4", "2", "Mündlich", 5)], finalGrade: nil),
            GradeSubject(id: "\(prefix)-e", subject: "Englisch", abbreviation: "E", system: 0,
                         grades: [grade("\(prefix)g5", "2-", "Vokabeltest", 3)], finalGrade: nil),
        ]
        copy.absences = [
            Absence(id: "\(prefix)a1", date: SchoolCalendar.addDays(-8, to: today), from: nil, until: nil, excused: true,
                    reason: "Erkältung", awaitingExcuse: false),
            Absence(id: "\(prefix)a2", date: SchoolCalendar.addDays(-2, to: today), from: "11:40", until: "13:15", excused: false,
                    reason: nil, awaitingExcuse: true),
        ]
        copy.exemptions = [
            Exemption(id: "\(prefix)x1", startDate: SchoolCalendar.addDays(14, to: today), endDate: SchoolCalendar.addDays(14, to: today),
                      comment: "Hochzeit in der Familie", feedback: nil, granted: nil),
        ]
        copy.invoices = [
            Invoice(id: "\(prefix)r1", number: "2026-114", date: SchoolCalendar.addDays(-4, to: today),
                    dueDate: SchoolCalendar.addDays(10, to: today), sum: 38.5, paidSum: 0, paid: false,
                    items: ["Wandertag Bus: 8,50 €", "Kopiergeld: 30,00 €"]),
        ]
        copy.alldayOffers = [
            AlldayOffer(id: "o1", name: "Hausaufgabenbetreuung", weekday: 1, startTime: "13:15", endTime: "15:00"),
            AlldayOffer(id: "o2", name: "Fußball-AG", weekday: 3, startTime: "14:00", endTime: "15:30"),
        ]
        copy.alldayNotes = [AlldayNote(id: "n1", date: today, message: "Am Freitag endet die Betreuung ausnahmsweise um 14 Uhr.")]
        copy.parentTalks = [
            ParentTalkRound(id: "p1", label: "Elternsprechtag Herbst",
                            start: SchoolCalendar.addDays(9, to: today) + "T15:00:00.000Z", end: SchoolCalendar.addDays(9, to: today) + "T19:00:00.000Z",
                            inscriptionStart: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-86400)),
                            inscriptionEnd: ISO8601DateFormatter().string(from: .now.addingTimeInterval(86400 * 5)),
                            appointments: [ParentTalkAppointment(id: "pa1", start: SchoolCalendar.addDays(9, to: today) + "T15:30:00.000Z",
                                                                 end: nil, cancelled: false, teacher: "Frau Hofmann")]),
        ]
        return copy
    }
}

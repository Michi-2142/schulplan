import Foundation

enum LessonState: String, Codable, Hashable, Sendable {
    case regular
    case substitution
    case cancelled
    case roomChange
    case added
}

struct Lesson: Codable, Hashable, Identifiable, Sendable {
    /// Stabiler Schlüssel: Datum | Stunde | ursprüngliches Fach. Grundlage der Änderungserkennung.
    var id: String
    /// `yyyy-MM-dd`
    var date: String
    var hour: String
    var hourSort: Int
    var start: String?
    var end: String?
    var subject: String
    var subjectAbbr: String?
    var teacher: String?
    var room: String?
    var state: LessonState
    var originalSubject: String?
    var originalTeacher: String?
    var originalRoom: String?
    var comment: String?

    /// Alles, was sich ändern kann. Unterscheidet sich der Fingerabdruck, wird benachrichtigt.
    var fingerprint: String {
        [state.rawValue, subject, teacher ?? "", room ?? "", comment ?? ""].joined(separator: "|")
    }

    var timeRange: String? {
        switch (start, end) {
        case let (start?, end?): "\(start)–\(end)"
        case let (start?, nil): start
        default: nil
        }
    }

    var hourLabel: String { hour.isEmpty ? "–" : hour }
}

struct Homework: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var subject: String
    /// Datum, an dem die Aufgabe gestellt wurde bzw. fällig ist (`yyyy-MM-dd`).
    var date: String
    var due: String?
    var text: String
    var teacher: String?
}

struct Exam: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var subject: String
    var date: String
    var start: String?
    var end: String?
    var type: String?
    var comment: String?
}

struct Student: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var firstname: String
    var lastname: String
    var className: String?
    /// Das Original-Objekt der API — wird unverändert als `student`-Parameter zurückgeschickt.
    var raw: JSONValue

    var displayName: String {
        [firstname, lastname].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct Snapshot: Codable, Sendable {
    var studentId: String
    var fetchedAt: Date
    var rangeStart: String
    var rangeEnd: String
    var lessons: [Lesson]
    var homework: [Homework]
    var exams: [Exam]
    /// Optional, damit ältere gespeicherte Stände weiter lesbar sind.
    var threads: [MessageThread]?
    var letters: [Letter]?
    var tiles: [Tile]?
    var events: [SchoolEvent]?
    var modules: [SchoolModule]?
    var grades: [GradeSubject]?
    var absences: [Absence]?
    var exemptions: [Exemption]?
    var invoices: [Invoice]?
    var alldayOffers: [AlldayOffer]?
    var alldayNotes: [AlldayNote]?
    var parentTalks: [ParentTalkRound]?
    /// Module, die beim letzten Abruf fehlgeschlagen sind (z. B. nicht freigeschaltet).
    var failedModules: [String] = []
}

struct ChangeEvent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cancelled, substitution, roomChange, added, restored, changed, newExam, newHomework, newMessage, newLetter, tileChanged, newEvent, eventChanged,
            newGrade, newAbsence, exemptionDecided, newInvoice, alldayNote, parentTalk
    }

    var id = UUID()
    var kind: Kind
    var detectedAt: Date
    /// Datum der betroffenen Stunde / Arbeit (`yyyy-MM-dd`)
    var date: String?
    var title: String
    var body: String
    /// Vorname(n) des Kindes – nur gesetzt, wenn das Konto mehrere Kinder hat.
    var student: String?

    /// Titel mit Kind davor, z. B. „Mia · Entfall · Mathematik“.
    var displayTitle: String { student.map { "\($0) · \(title)" } ?? title }
}

// MARK: - Nachrichten

struct MessageThread: Codable, Hashable, Identifiable, Sendable {
    /// `threadId` – wird für `send-message` gebraucht.
    var id: String
    /// Id der Subscription – Schlüssel für Nachrichten abrufen / gelesen markieren.
    var subscriptionId: String
    var subject: String
    var sender: String
    var recipients: String?
    /// ISO-Zeitstempel, wie von der API geliefert
    var lastMessageAt: String?
    var unreadCount: Int
    var preview: String?

    var lastMessageDate: Date? { lastMessageAt.flatMap(ISODate.parse) }
}

struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var text: String
    var sender: String
    var sentAt: String?
    var isOwn: Bool
    var attachments: [StoredFile] = []

    var sentDate: Date? { sentAt.flatMap(ISODate.parse) }
}

enum ISODate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - Elternbriefe, Pinnwand, Termine

struct Letter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var sender: String
    var sentAt: String?
    var answerDeadline: String?
    /// Id des StudentLetterStatus – wird für `letters/confirm` gebraucht.
    var statusId: String?
    var confirmed: Bool
    var questionCount: Int

    var sentDate: Date? { sentAt.flatMap(ISODate.parseFlexible) }
    var needsAction: Bool { !confirmed && statusId != nil }
}

struct LetterDetail: Hashable, Sendable {
    var text: String
    var attachments: [StoredFile]
}

struct Tile: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var content: String
    var pinned: Bool
    var order: Int

    /// Erkennt geänderten Inhalt ohne den ganzen Text zu vergleichen.
    var contentHash: String { Parsers.shortHash(title + "|" + content) }
}

struct SchoolEvent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var start: String
    var end: String?
    var allDay: Bool
    var location: String?
    var details: String?
    var category: String?
    var colorHex: String?
    var isHoliday: Bool

    var startDate: Date? { ISODate.parseFlexible(start) }
    var endDate: Date? { end.flatMap(ISODate.parseFlexible) }

    /// Lokaler Kalendertag des Beginns (`yyyy-MM-dd`).
    var day: String { start.count == 10 ? start : (startDate.map(SchoolCalendar.iso) ?? String(start.prefix(10))) }

    /// Letzter Tag (inklusive). Ganztägige Enden zeigen meist auf Mitternacht des Folgetags.
    var lastDay: String {
        guard let end else { return day }
        var last = end.count == 10 ? end : (endDate.map(SchoolCalendar.iso) ?? day)
        if allDay, last > day, endDate.map({ SchoolCalendar.calendar.component(.hour, from: $0) == 0 }) ?? (end.count == 10) {
            last = SchoolCalendar.addDays(-1, to: last)
        }
        return max(last, day)
    }

    func covers(_ date: String) -> Bool { date >= day && date <= lastDay }

    var timeLabel: String? {
        guard !allDay, let startDate else { return nil }
        let start = startDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
        guard let endDate else { return start }
        return "\(start)–\(endDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))"
    }

    /// Fingerabdruck für „Termin verschoben / geändert“.
    var fingerprint: String { [title, start, end ?? "", location ?? ""].joined(separator: "|") }
}

struct SchoolModule: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var label: String
}

extension ISODate {
    /// Akzeptiert `yyyy-MM-dd` und ISO-Zeitstempel.
    static func parseFlexible(_ string: String) -> Date? {
        string.count == 10 ? SchoolCalendar.date(string) : parse(string)
    }
}

// MARK: - Noten

struct Grade: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var value: String
    var numeric: Double?
    var weight: Double
    var type: String?
    var date: String?
    var comment: String?
}

struct GradeSubject: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var subject: String
    var abbreviation: String?
    /// 0 = Noten 1–6, 1 = Punkte 0–15
    var system: Int
    var grades: [Grade]
    var finalGrade: String?

    var average: Double? {
        let usable = grades.filter { $0.numeric != nil }
        guard !usable.isEmpty else { return nil }
        let weight = usable.reduce(0) { $0 + max($1.weight, 0.0001) }
        return usable.reduce(0) { $0 + ($1.numeric ?? 0) * max($1.weight, 0.0001) } / weight
    }
}

// MARK: - Fehlzeiten & Beurlaubung

struct Absence: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var date: String
    var from: String?
    var until: String?
    var excused: Bool
    var reason: String?
    /// Krankmeldung ohne Attest-Typ: Schule wartet noch auf Entschuldigung.
    var awaitingExcuse: Bool
}

struct Exemption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var startDate: String
    var endDate: String
    var comment: String?
    var feedback: String?
    /// nil = noch nicht entschieden
    var granted: Bool?
}

// MARK: - Rechnungen, Ganztag, Elternsprechtag

struct Invoice: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var number: String?
    var date: String?
    var dueDate: String?
    var sum: Double?
    var paidSum: Double?
    var paid: Bool
    var items: [String]
}

struct AlldayOffer: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    /// 0 = Sonntag … 6 = Samstag (JavaScript-Zählung)
    var weekday: Int?
    var startTime: String?
    var endTime: String?
}

struct AlldayNote: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var date: String?
    var message: String
}

struct ParentTalkAppointment: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var start: String?
    var end: String?
    var cancelled: Bool
    var teacher: String?
}

struct ParentTalkRound: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var start: String?
    var end: String?
    var inscriptionStart: String?
    var inscriptionEnd: String?
    var appointments: [ParentTalkAppointment]

    var isOpenForBooking: Bool {
        guard let from = inscriptionStart.flatMap(ISODate.parseFlexible),
              let to = inscriptionEnd.flatMap(ISODate.parseFlexible) else { return false }
        return (from...to).contains(.now)
    }
}

// MARK: - Dateien, Dokumente, Wahlen (nur bei Bedarf geladen)

/// Verschlüsselte Schulmanager-Datei. Der Deskriptor ist ein 7er-Array
/// `[institutionId, scope, id, key, type, size, name]` – der AES-Schlüssel steckt darin.
struct StoredFile: Codable, Hashable, Identifiable, Sendable {
    var id: String { name + "|" + (descriptor.string ?? "") }
    var name: String
    var descriptor: JSONValue
}

struct DocumentFolder: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

struct SchoolDocument: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var file: StoredFile?
    var htmlText: String?
    var updatedAt: String?
}

struct Elective: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var raw: JSONValue
}

struct Election: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String?
    var start: String?
    var end: String?
    var priorities: Int?
    var finalized: Bool
    var subElectionId: String?
    var electives: [Elective]

    var isOpen: Bool {
        guard !finalized else { return false }
        let now = Date.now
        if let start = start.flatMap(ISODate.parseFlexible), now < start { return false }
        if let end = end.flatMap(ISODate.parseFlexible), now > end { return false }
        return true
    }
}

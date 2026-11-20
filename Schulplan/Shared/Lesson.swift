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

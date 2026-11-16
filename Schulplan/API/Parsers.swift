import CryptoKit
import Foundation

/// Übersetzt die Rohdaten der API in die App-Modelle. Bewusst tolerant: fehlende Felder führen
/// zu Platzhaltern, nicht zu Abbrüchen.
enum Parsers {
    // MARK: Stundenplan

    private struct Info {
        var subject: String?
        var abbr: String?
        var teacher: String?
        var room: String?
    }

    private static func info(_ json: JSONValue?) -> Info? {
        guard let json else { return nil }
        let subjectObject = json["subject"]
        let subject = json["subjectLabel"]?.string
            ?? subjectObject?["name"]?.string
            ?? subjectObject?["longName"]?.string
            ?? subjectObject?.string
            ?? subjectObject?["abbreviation"]?.string
        let abbr = subjectObject?["abbreviation"]?.string ?? subjectObject?["shortName"]?.string
        let teachers = (json["teachers"]?.array ?? []).compactMap { teacher -> String? in
            teacher["abbreviation"]?.string ?? teacher["lastname"]?.string
        }
        let room = json["room"]?["name"]?.string ?? json["room"]?.string
        let result = Info(
            subject: subject,
            abbr: abbr,
            teacher: teachers.isEmpty ? nil : teachers.joined(separator: ", "),
            room: room
        )
        if result.subject == nil, result.teacher == nil, result.room == nil { return nil }
        return result
    }

    static func normalizeHour(_ value: JSONValue?) -> String {
        guard let raw = value?.string else { return "" }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    static func lessons(from data: JSONValue?, classHours: JSONValue?) -> [Lesson] {
        var hoursById: [String: JSONValue] = [:]
        for hour in classHours?.array ?? [] {
            if let id = hour["id"]?.string { hoursById[id] = hour }
        }

        var lessons: [Lesson] = []
        for raw in data?.array ?? [] {
            guard let date = (raw["date"]?.string ?? raw["start"]?.string).map({ String($0.prefix(10)) }) else { continue }

            let lessonHour = raw["classHour"]
            let hour = lessonHour?["id"]?.string.flatMap { hoursById[$0] } ?? lessonHour
            let number = normalizeHour(lessonHour?["number"] ?? hour?["number"])
            let (start, end) = times(of: hour, date: date)

            let actual = info(raw["actualLesson"])
            let original = info(raw["originalLessons"]?[0] ?? raw["originalLesson"])
            guard let shown = actual ?? original else { continue }

            let cancelled = raw["isCancelled"]?.bool == true || (actual == nil && original != nil)
            let isNew = raw["isNew"]?.bool == true && original == nil
            let subjectChanged = original != nil && actual != nil && original?.subject != actual?.subject
            let teacherChanged = original != nil && actual != nil && original?.teacher != actual?.teacher
            let roomChanged = original?.room != nil && actual != nil && original?.room != actual?.room

            let state: LessonState =
                if cancelled { .cancelled }
                else if isNew { .added }
                else if raw["isSubstitution"]?.bool == true || subjectChanged || teacherChanged { .substitution }
                else if roomChanged { .roomChange }
                else { .regular }

            let comment = raw["comment"]?.string
                ?? raw["actualLesson"]?["comment"]?.string
                ?? raw["substitutionText"]?.string
            let keySubject = original?.subject ?? shown.subject ?? "?"

            lessons.append(Lesson(
                id: "\(date)|\(number)|\(keySubject)",
                date: date,
                hour: number,
                hourSort: Int(number.prefix { $0.isNumber }) ?? 99,
                start: start,
                end: end,
                subject: shown.subject ?? "Unterricht",
                subjectAbbr: shown.abbr,
                teacher: shown.teacher,
                room: shown.room,
                state: state,
                originalSubject: state == .regular ? nil : original?.subject,
                originalTeacher: state == .regular ? nil : original?.teacher,
                originalRoom: state == .regular ? nil : original?.room,
                comment: comment
            ))
        }
        return deduplicated(lessons).sorted {
            ($0.date, $0.hourSort, $0.subject) < ($1.date, $1.hourSort, $1.subject)
        }
    }

    /// `fromByDay`/`untilByDay` sind nach JavaScript-Wochentagen indiziert (0 = Sonntag).
    private static func times(of hour: JSONValue?, date: String) -> (String?, String?) {
        let jsDay = SchoolCalendar.isoWeekday(date) % 7
        let from = hour?["fromByDay"]?[jsDay]?.string ?? hour?["from"]?.string
        let until = hour?["untilByDay"]?[jsDay]?.string ?? hour?["until"]?.string
        return (from.map { String($0.prefix(5)) }, until.map { String($0.prefix(5)) })
    }

    private static func deduplicated(_ lessons: [Lesson]) -> [Lesson] {
        var counts: [String: Int] = [:]
        return lessons.map { lesson in
            var copy = lesson
            let count = counts[lesson.id, default: 0]
            counts[lesson.id] = count + 1
            if count > 0 { copy.id += "#\(count + 1)" }
            return copy
        }
    }

    // MARK: Hausaufgaben

    static func homework(from data: JSONValue?) -> [Homework] {
        (data?.array ?? []).compactMap { raw in
            guard let text = raw["homework"]?.string ?? raw["text"]?.string else { return nil }
            let subject = raw["subject"]?["name"]?.string ?? raw["subject"]?.string ?? "Fach"
            let date = (raw["date"]?.string).map { String($0.prefix(10)) } ?? SchoolCalendar.today
            let due = (raw["homeworkDueDate"]?.string ?? raw["dueDate"]?.string).map { String($0.prefix(10)) }
            return Homework(
                id: "hw-" + shortHash("\(date)|\(subject)|\(text)"),
                subject: subject,
                date: date,
                due: due,
                text: text,
                teacher: raw["teacher"]?["abbreviation"]?.string ?? raw["teacher"]?["lastname"]?.string
            )
        }
        .sorted { ($0.due ?? $0.date) > ($1.due ?? $1.date) }
    }

    // MARK: Klassenarbeiten

    static func exams(from data: JSONValue?) -> [Exam] {
        (data?.array ?? []).compactMap { raw in
            guard let date = raw["date"]?.string.map({ String($0.prefix(10)) }) else { return nil }
            let subject = raw["subject"]?["name"]?.string
                ?? raw["course"]?["subject"]?["name"]?.string
                ?? raw["course"]?["name"]?.string
                ?? raw["subject"]?.string
                ?? "Leistungsnachweis"
            let start = raw["startTime"]?.string ?? raw["startClassHour"]?["from"]?.string ?? raw["classHour"]?["from"]?.string
            let end = raw["endTime"]?.string ?? raw["endClassHour"]?["until"]?.string ?? raw["classHour"]?["until"]?.string
            return Exam(
                id: raw["id"]?.string ?? "exam-" + shortHash("\(date)|\(subject)"),
                subject: subject,
                date: date,
                start: start.map { String($0.prefix(5)) },
                end: end.map { String($0.prefix(5)) },
                type: raw["type"]?["name"]?.string ?? raw["typeName"]?.string,
                comment: raw["comment"]?.string
            )
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: Nachrichten

    static func threads(from data: JSONValue?) -> [MessageThread] {
        (data?.array ?? []).compactMap { raw -> MessageThread? in
            guard raw["isArchived"]?.bool != true,
                  let subscriptionId = raw["id"]?.string,
                  let threadId = raw["threadId"]?.string ?? raw["thread"]?["id"]?.string else { return nil }
            let thread = raw["thread"]
            return MessageThread(
                id: threadId,
                subscriptionId: subscriptionId,
                subject: thread?["subject"]?.string ?? "Nachricht",
                sender: thread?["senderString"]?.string ?? personName(thread?["sender"]) ?? "",
                recipients: thread?["recipientString"]?.string,
                lastMessageAt: thread?["lastMessageTimestamp"]?.string ?? thread?["lastMessage"]?["createdAt"]?.string,
                unreadCount: raw["unreadCount"]?.int ?? 0,
                preview: thread?["lastMessage"]?["text"]?.string.map(plainText)
            )
        }
        .sorted { ($0.lastMessageAt ?? "") > ($1.lastMessageAt ?? "") }
    }

    /// Antwort ist je nach Version eine Liste oder `{messages: [...]}`.
    /// Eigene Nachrichten erkennt man daran, dass `sender` fehlt.
    static func messages(from data: JSONValue?) -> [ChatMessage] {
        let list = data?.array ?? data?["messages"]?.array ?? []
        return list.compactMap { raw -> ChatMessage? in
            guard let id = raw["id"]?.string else { return nil }
            let sender = raw["sender"]
            let isOwn = raw["isOwn"]?.bool ?? (sender == nil)
            let attachments = (raw["attachments"]?.array ?? []).map { attachment in
                storedFile(attachment["file"], fallbackName: attachment["filename"]?.string ?? attachment["name"]?.string)
            }
            return ChatMessage(
                id: id,
                text: plainText(raw["text"]?.string ?? ""),
                sender: isOwn ? "Ich" : (personName(sender) ?? raw["senderString"]?.string ?? "Unbekannt"),
                sentAt: raw["createdAt"]?.string,
                isOwn: isOwn,
                attachments: attachments
            )
        }
        .sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
    }

    private static func personName(_ json: JSONValue?) -> String? {
        guard let json else { return nil }
        let name = [json["firstname"]?.string, json["lastname"]?.string].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// Datei-Deskriptor (JSON-String oder Array) samt Namen für Anzeige und Download.
    static func storedFile(_ json: JSONValue?, fallbackName: String? = nil) -> StoredFile {
        StoredFile(name: fallbackName ?? storedFileName(json) ?? "Anhang", descriptor: json ?? .null)
    }

    /// Datei-Deskriptoren kommen als JSON-String eines 7er-Arrays; der Name steht an Position 6.
    static func descriptorArray(_ json: JSONValue?) -> [JSONValue]? {
        if let array = json?.array, array.count >= 7 { return array }
        guard let text = json?.string, let data = text.data(using: .utf8),
              let parsed = try? JSONValue.decode(data), let array = parsed.array, array.count >= 7 else { return nil }
        return array
    }

    private static func storedFileName(_ json: JSONValue?) -> String? {
        if let name = json?[6]?.string { return name }
        guard let text = json?.string, let data = text.data(using: .utf8),
              let parsed = try? JSONValue.decode(data) else { return json?["name"]?.string }
        return parsed[6]?.string ?? parsed["name"]?.string
    }

    /// Manche Nachrichten enthalten einfaches HTML – für die Anzeige in reinen Text wandeln.
    static func plainText(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = text
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Elternbriefe

    /// Bestätigt ist ein Brief, sobald alle StudentLetterStatus einen `readTimestamp` haben.
    static func letters(from data: JSONValue?, studentId: String?) -> [Letter] {
        (data?.array ?? []).compactMap { raw -> Letter? in
            guard let id = raw["id"]?.string else { return nil }
            var statuses = raw["studentStatuses"]?.array ?? []
            // Bei mehreren Kindern nur den Status des gewählten Kindes betrachten.
            if let studentId, statuses.contains(where: { $0["studentId"]?.string == studentId }) {
                statuses = statuses.filter { $0["studentId"]?.string == studentId }
            }
            let confirmed = !statuses.isEmpty && statuses.allSatisfy { $0["readTimestamp"] != nil }
            return Letter(
                id: id,
                title: raw["title"]?.string ?? raw["subject"]?.string ?? "Elternbrief",
                sender: raw["senderName"]?.string ?? raw["createdBy"]?.string ?? personName(raw["sender"]) ?? "Schule",
                sentAt: raw["sentDate"]?.string ?? raw["createdAt"]?.string,
                answerDeadline: raw["answerDeadline"]?.string,
                statusId: statuses.first?["id"]?.string,
                confirmed: statuses.isEmpty ? true : confirmed,
                questionCount: raw["questions"]?.array?.count ?? 0
            )
        }
        .sorted { ($0.sentAt ?? "") > ($1.sentAt ?? "") }
    }

    static func letterDetail(from data: JSONValue?) -> LetterDetail? {
        let raw = data?.array?.first ?? data
        guard let raw, raw.object != nil else { return nil }
        let attachments = (raw["attachments"]?.array ?? [])
            .filter { $0["inline"]?.bool != true }
            .map { storedFile($0["file"], fallbackName: $0["filename"]?.string) }
        return LetterDetail(text: plainText(raw["text"]?.string ?? ""), attachments: attachments)
    }

    // MARK: Pinnwand

    static func tiles(from data: JSONValue?) -> [Tile] {
        (data?.array ?? []).compactMap { raw -> Tile? in
            guard let id = raw["id"]?.string else { return nil }
            let content = plainText(raw["content"]?.string ?? raw["text"]?.string ?? "")
            let title = raw["title"]?.string ?? ""
            guard !content.isEmpty || !title.isEmpty else { return nil }
            return Tile(id: id, title: title.isEmpty ? "Aushang" : title, content: content,
                        pinned: raw["displayOnTop"]?.bool ?? false, order: raw["order"]?.int ?? 0)
        }
        .sorted { ($0.pinned ? 0 : 1, $0.order) < ($1.pinned ? 0 : 1, $1.order) }
    }

    // MARK: Termine

    static func events(from data: JSONValue?, categories: JSONValue?) -> [SchoolEvent] {
        var categoryById: [String: JSONValue] = [:]
        for category in categories?.array ?? [] {
            if let id = category["id"]?.string { categoryById[id] = category }
        }
        let list = (data?["nonRecurringEvents"]?.array ?? []) + (data?["recurringEvents"]?.array ?? []) + (data?.array ?? [])
        var seen = Set<String>()
        return list.compactMap { raw -> SchoolEvent? in
            guard let start = raw["start"]?.string ?? raw["startDate"]?.string else { return nil }
            let baseId = raw["id"]?.string ?? shortHash(start + (raw["summary"]?.string ?? ""))
            // Wiederkehrende Termine teilen sich die Id – mit dem Beginn eindeutig machen.
            let id = "\(baseId)@\(start)"
            guard seen.insert(id).inserted else { return nil }
            let categoryId = raw["categoryId"]?.string ?? raw["category"]?["id"]?.string
            let category = categoryId.flatMap { categoryById[$0] } ?? raw["category"]
            return SchoolEvent(
                id: id,
                title: raw["summary"]?.string ?? raw["title"]?.string ?? "Termin",
                start: start,
                end: raw["end"]?.string ?? raw["endDate"]?.string,
                allDay: raw["allDay"]?.bool ?? (start.count == 10),
                location: raw["location"]?.string,
                details: raw["description"]?.string.map(plainText),
                category: category?["name"]?.string,
                colorHex: category?["color"]?.string,
                isHoliday: categoryId == "-1"
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: Module

    static func modules(from data: JSONValue?) -> [SchoolModule] {
        (data?.array ?? []).compactMap { raw in
            guard let name = raw["name"]?.string ?? raw.string else { return nil }
            return SchoolModule(name: name, label: raw["label"]?.string ?? raw["title"]?.string ?? name)
        }
    }

    // MARK: Noten

    /// Notenwerte kommen als `"<system>~<wert>"`, z. B. `"0~2-"`. System 0 = Noten, 1 = Punkte.
    static func decodeGrade(_ value: JSONValue?, system fallback: Int) -> (text: String, numeric: Double?) {
        guard let raw = value?.string ?? value?["value"]?.string else { return ("", nil) }
        var system = fallback
        var text = raw
        if let tilde = raw.firstIndex(of: "~") {
            system = Int(raw[..<tilde]) ?? fallback
            text = String(raw[raw.index(after: tilde)...])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if system == 1, let points = Int(text), (0...15).contains(points) { return (text, Double(points)) }
        guard let first = text.first, let base = Int(String(first)), (1...6).contains(base) else {
            return (text, Double(text.replacingOccurrences(of: ",", with: ".")))
        }
        let modifier = text.dropFirst().trimmingCharacters(in: .whitespaces)
        let numeric = Double(base) + (modifier == "+" ? -0.3 : modifier == "-" ? 0.3 : 0)
        return (text, modifier.isEmpty || modifier == "+" || modifier == "-" ? numeric : nil)
    }

    static func grades(from data: JSONValue?) -> [GradeSubject] {
        var subjects: [String: JSONValue] = [:]
        for subject in data?["subjects"]?.array ?? [] {
            if let id = subject["id"]?.string { subjects[id] = subject }
        }
        let finals = data?["finalGrades"]?.array ?? []
        return (data?["courses"]?.array ?? []).compactMap { course -> GradeSubject? in
            guard let id = course["id"]?.string else { return nil }
            let subject = course["subjectId"]?.string.flatMap { subjects[$0] } ?? course["subject"]
            let system = course["gradingPreset"]?["gradingSystem"]?.int ?? 0
            let grades = (course["grades"]?.array ?? []).compactMap { raw -> Grade? in
                let decoded = decodeGrade(raw["value"] ?? raw["grade"], system: system)
                guard !decoded.text.isEmpty else { return nil }
                return Grade(
                    id: raw["id"]?.string ?? shortHash("\(id)|\(decoded.text)|\(raw["date"]?.string ?? "")"),
                    value: decoded.text, numeric: decoded.numeric,
                    weight: raw["weight"].flatMap { Double($0.string ?? "") } ?? 1,
                    type: raw["gradeType"]?["name"]?.string ?? raw["type"]?.string,
                    date: (raw["date"]?.string ?? raw["createdAt"]?.string).map { String($0.prefix(10)) },
                    comment: raw["comment"]?.string
                )
            }
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
            let final = finals.first { $0["courseId"]?.string == id }.flatMap { decodeGrade($0["value"] ?? $0["grade"], system: system).text }
                ?? course["finalGrade"].map { decodeGrade($0["value"] ?? $0, system: system).text }
            guard !grades.isEmpty || (final?.isEmpty == false) else { return nil }
            return GradeSubject(
                id: id,
                subject: subject?["name"]?.string ?? course["name"]?.string ?? "Fach",
                abbreviation: subject?["abbreviation"]?.string,
                system: system, grades: grades,
                finalGrade: final?.isEmpty == false ? final : nil
            )
        }
        .sorted { $0.subject < $1.subject }
    }

    // MARK: Fehlzeiten & Beurlaubung

    static func absences(from data: JSONValue?) -> [Absence] {
        (data?.array ?? []).compactMap { raw -> Absence? in
            guard let id = raw["id"]?.string, let date = raw["date"]?.string.map({ String($0.prefix(10)) }) else { return nil }
            let sickNote = raw["sickNote"]
            let hasCertificate = sickNote?["certificateType"] != nil
            // Regel des offiziellen Clients: Krankmeldung ohne Attest-Typ entschuldigt nicht, Beurlaubung immer.
            let excused = raw["exemptionRequest"] != nil || hasCertificate || raw["excused"]?.bool == true
            return Absence(
                id: id, date: date,
                from: raw["from"]?.string.map { String($0.prefix(5)) },
                until: raw["until"]?.string.map { String($0.prefix(5)) },
                excused: excused, reason: raw["comment"]?.string ?? raw["reason"]?.string,
                awaitingExcuse: !excused
            )
        }
        .sorted { $0.date > $1.date }
    }

    static func exemptions(from data: JSONValue?) -> [Exemption] {
        (data?.array ?? []).compactMap { raw -> Exemption? in
            guard let id = raw["id"]?.string, let start = raw["startDate"]?.string else { return nil }
            return Exemption(
                id: id, startDate: String(start.prefix(10)),
                endDate: String((raw["endDate"]?.string ?? start).prefix(10)),
                comment: raw["comment"]?.string, feedback: raw["feedback"]?.string,
                granted: raw["granted"]?.bool
            )
        }
        .sorted { $0.startDate > $1.startDate }
    }

    // MARK: Rechnungen

    static func amount(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if case .double(let number) = value { return number }
        if case .int(let number) = value { return Double(number) }
        return value.string.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func invoices(from data: JSONValue?, items: JSONValue?, itemNames: JSONValue?) -> [Invoice] {
        var names: [String: String] = [:]
        for item in itemNames?.array ?? [] {
            if let id = item["id"]?.string { names[id] = item["name"]?.string }
        }
        let allItems = items?.array ?? []
        return (data?.array ?? []).compactMap { raw -> Invoice? in
            guard let id = raw["id"]?.string else { return nil }
            let general = raw["generalInvoice"]
            let related = allItems.filter { $0["invoiceId"]?.string == id }.map { item -> String in
                let name = item["generalItemId"]?.string.flatMap { names[$0] } ?? "Beitrag"
                guard let value = amount(item["amount"]) else { return name }
                return "\(name): \(value.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))))"
            }
            return Invoice(
                id: id, number: general?["number"]?.string,
                date: general?["date"]?.string.map { String($0.prefix(10)) },
                dueDate: general?["dueDate"]?.string.map { String($0.prefix(10)) },
                sum: amount(raw["sum"]), paidSum: amount(raw["paidSum"]),
                paid: raw["paid"]?.bool ?? false, items: related
            )
        }
    }

    // MARK: Ganztag

    static func alldayOffers(from data: JSONValue?) -> [AlldayOffer] {
        (data?.array ?? []).compactMap { raw -> AlldayOffer? in
            guard let id = raw["id"]?.string else { return nil }
            return AlldayOffer(
                id: id,
                name: raw["name"]?.string ?? raw["offer"]?["name"]?.string ?? raw["title"]?.string ?? "Ganztagsangebot",
                weekday: raw["weekday"]?.int,
                startTime: raw["startTime"]?.string.map { String($0.prefix(5)) },
                endTime: raw["endTime"]?.string.map { String($0.prefix(5)) }
            )
        }
        .sorted { (($0.weekday ?? 9) + 6) % 7 < (($1.weekday ?? 9) + 6) % 7 }
    }

    static func alldayNotes(from data: JSONValue?) -> [AlldayNote] {
        (data?.array ?? []).compactMap { raw -> AlldayNote? in
            guard let message = raw["message"]?.string ?? raw["text"]?.string else { return nil }
            let date = (raw["date"]?.string ?? raw["createdAt"]?.string).map { String($0.prefix(10)) }
            return AlldayNote(id: raw["id"]?.string ?? shortHash(message + (date ?? "")), date: date, message: plainText(message))
        }
        .sorted { ($0.date ?? "") > ($1.date ?? "") }
    }

    // MARK: Elternsprechtag

    static func parentTalks(rounds: JSONValue?, appointments: JSONValue?) -> [ParentTalkRound] {
        let allAppointments = appointments?.array ?? []
        return (rounds?.array ?? []).compactMap { raw -> ParentTalkRound? in
            guard let id = raw["id"]?.string else { return nil }
            let mine = allAppointments.filter { $0["roundId"]?.string == id }.map { appointment in
                let teacher = appointment["teacher"]
                let teacherName = [teacher?["firstname"]?.string, teacher?["lastname"]?.string].compactMap { $0 }.joined(separator: " ")
                return ParentTalkAppointment(
                    id: appointment["id"]?.string ?? UUID().uuidString,
                    start: appointment["start"]?.string, end: appointment["end"]?.string,
                    cancelled: appointment["cancelled"]?.bool ?? false,
                    teacher: teacherName.isEmpty ? teacher?["abbreviation"]?.string : teacherName
                )
            }
            .sorted { ($0.start ?? "") < ($1.start ?? "") }
            return ParentTalkRound(
                id: id, label: raw["label"]?.string ?? raw["name"]?.string ?? "Elternsprechtag",
                start: raw["start"]?.string, end: raw["end"]?.string,
                inscriptionStart: raw["inscriptionStart"]?.string, inscriptionEnd: raw["inscriptionEnd"]?.string,
                appointments: mine
            )
        }
    }

    // MARK: Dokumente

    static func folderContents(from data: JSONValue?) -> (folders: [DocumentFolder], documents: [SchoolDocument]) {
        let folders = (data?["subFolders"]?.array ?? data?["folders"]?.array ?? []).compactMap { raw -> DocumentFolder? in
            guard let id = raw["id"]?.string else { return nil }
            return DocumentFolder(id: id, name: raw["name"]?.string ?? "Ordner")
        }
        let documents = (data?["documents"]?.array ?? []).compactMap { raw -> SchoolDocument? in
            guard let id = raw["id"]?.string else { return nil }
            let name = raw["name"]?.string ?? raw["title"]?.string ?? "Dokument"
            let file = raw["file"].map { storedFile($0, fallbackName: storedFileName($0) ?? name) }
            return SchoolDocument(id: id, name: name, file: file,
                                  htmlText: raw["content"]?.string.map(plainText),
                                  updatedAt: raw["updatedAt"]?.string)
        }
        return (folders.sorted { $0.name < $1.name }, documents.sorted { $0.name < $1.name })
    }

    // MARK: Wahlen

    static func elections(from data: JSONValue?, electives: JSONValue?) -> [Election] {
        let all = electives?.array ?? []
        return (data?.array ?? []).compactMap { raw -> Election? in
            guard let id = raw["id"]?.string else { return nil }
            let mine = all.filter { $0["electionId"]?.string == id }
            return Election(
                id: id, name: raw["name"]?.string ?? "Wahl",
                description: raw["description"]?.string.map(plainText),
                start: raw["start"]?.string, end: raw["end"]?.string,
                priorities: raw["prioritiesPerStudent"]?.int,
                finalized: raw["finalized"]?.bool ?? false,
                subElectionId: raw["useSubElections"]?.bool == true ? mine.first?["electionId"]?.string : nil,
                electives: mine.compactMap { elective in
                    guard let electiveId = elective["id"]?.string else { return nil }
                    return Elective(id: electiveId, name: elective["name"]?.string ?? "Wahlfach", raw: elective)
                }
            )
        }
    }

    static func shortHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

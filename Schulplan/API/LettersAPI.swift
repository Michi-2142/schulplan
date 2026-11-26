import Foundation

/// Elternbriefe: Text nachladen und Kenntnisnahme bestätigen.
enum LettersAPI {
    private static var isDemo: Bool { SessionStore.shared.isDemo }

    /// Wie die Web-App: `letters/get-letter-for-reading` mit `{letterId}` liefert Text, Anhänge und Status.
    /// Das ORM-Gateway (`poqa`) ist nur noch Rückfall – für Elternkonten ist es meist gesperrt.
    static func detail(for letter: Letter) async throws -> LetterDetail {
        if isDemo { return DemoData.letterDetail(letter) }
        let letterId: JSONValue = Int(letter.id).map { .int($0) } ?? .string(letter.id)
        let result = try await SchulmanagerAPI.shared.call([
            APICall(module: "letters", endpoint: "get-letter-for-reading", parameters: ["letterId": letterId]),
        ])
        if let first = result.first, first.ok, let detail = Parsers.letterDetail(from: first.data) {
            return detail
        }

        let action: JSONValue = [
            "model": "modules/letters/letter", "action": "findByPk", "instanceId": letterId,
            "parameters": [["include": [["association": "attachments", "required": false]]]],
        ]
        for module in ["letters", "main"] {
            let fallback = try await SchulmanagerAPI.shared.call([
                APICall(module: module, endpoint: "poqa", parameters: ["action": action]),
            ])
            if let first = fallback.first, first.ok, let detail = Parsers.letterDetail(from: first.data) {
                return detail
            }
        }
        throw SMError.server("Der Brieftext konnte nicht geladen werden (Status \(result.first?.status ?? 0)). Öffne ihn bei Bedarf im Browser.")
    }

    static func confirm(_ letter: Letter) async throws {
        guard let statusId = letter.statusId else { return }
        if isDemo { return }
        let result = try await SchulmanagerAPI.shared.call([
            APICall(module: "letters", endpoint: "confirm", parameters: [
                "studentLetterStatus": ["id": .string(statusId)],
                "formData": [:],
            ]),
        ])
        guard let first = result.first, first.ok else {
            throw SMError.server("Bestätigung fehlgeschlagen (Status \(result.first?.status ?? 0)).")
        }
    }

    /// Antworten auf die Fragen eines Briefs speichern – wie `submitFormData` der Web-App.
    /// Das bestätigt den Brief zugleich.
    static func submitAnswers(status: LetterStatus, formData: [String: JSONValue]) async throws {
        if isDemo { return }
        let result = try await SchulmanagerAPI.shared.call([
            APICall(module: "letters", endpoint: "confirm", parameters: [
                "studentLetterStatus": status.raw,
                "formData": .object(formData),
            ]),
        ])
        guard let first = result.first, first.ok else {
            throw SMError.server("Antworten konnten nicht gespeichert werden (Status \(result.first?.status ?? 0)).")
        }
    }
}

import CryptoKit
import Foundation

/// ORM-Gateway `poqa` („perform object query action“). Modellpfade sind kebab-case,
/// `parameters` ist ein Array mit den Sequelize-Optionen als erstem Element.
enum Poqa {
    static func call(model: String, action: String = "findAll", instanceId: JSONValue? = nil,
                     options: JSONValue = [:], module: String) -> [APICall] {
        var actionObject: [String: JSONValue] = [
            "model": .string(model), "action": .string(action), "parameters": [options],
        ]
        if let instanceId { actionObject["instanceId"] = instanceId }
        // Je nach Version hängt `poqa` am Fachmodul oder am Hauptmodul.
        return [module, "main"].map { APICall(module: $0, endpoint: "poqa", parameters: ["action": .object(actionObject)]) }
    }

    /// Erstes erfolgreiches Ergebnis aus den beiden Varianten.
    static func first(_ results: ArraySlice<APIResult>) -> APIResult? {
        results.first { $0.ok }
    }

    static func numericId(_ id: String) -> JSONValue { Int(id).map { .int($0) } ?? .string(id) }
}

/// Aufrufe für Module, die nicht laufend abgeglichen werden (Formulare, Ordner, Wahlen, Dateien).
enum ModulesAPI {
    private static var isDemo: Bool { SessionStore.shared.isDemo }
    private static var api: SchulmanagerAPI { .shared }

    private static func single(_ call: APICall, error message: String) async throws -> JSONValue? {
        let result = try await api.call([call])
        guard let first = result.first, first.ok else {
            throw SMError.server("\(message) (Status \(result.first?.status ?? 0)).")
        }
        return first.data
    }

    // MARK: Krankmeldung & Beurlaubung

    /// Kind muss verschachtelt übergeben werden (`{student: {id}}`) – ein flaches `studentId` endet mit 500.
    static func sendSickNote(studentId: String, start: String, end: String, startTime: String?, comment: String?) async throws {
        if isDemo { return }
        _ = try await single(APICall(module: "sick", endpoint: "create-sick-note", parameters: [
            "sickNote": [
                "student": ["id": Poqa.numericId(studentId)],
                "startDate": .string(start), "endDate": .string(end),
                "startTime": JSONValue(startTime), "comment": JSONValue(comment?.isEmpty == true ? nil : comment),
            ],
        ]), error: "Krankmeldung wurde nicht gesendet")
    }

    static func requestExemption(studentId: String, start: String, end: String, startTime: String?, endTime: String?,
                                 comment: String) async throws {
        if isDemo { return }
        _ = try await single(APICall(module: "exemptions", endpoint: "request-exemption", parameters: [
            "exemptionRequest": [
                "student": ["id": Poqa.numericId(studentId)],
                "startDate": .string(start), "endDate": .string(end),
                "startTime": JSONValue(startTime), "endTime": JSONValue(endTime), "comment": .string(comment),
            ],
        ]), error: "Antrag wurde nicht gesendet")
    }

    // MARK: Dokumente

    static func documentRoot() async throws -> DocumentFolder? {
        if isDemo { return DocumentFolder(id: "root", name: "Dokumente") }
        let data = try await single(APICall(module: "documents", endpoint: "get-root-folder", parameters: [:]),
                                    error: "Dokumente nicht verfügbar")
        guard let id = data?["id"]?.string else { return nil }
        return DocumentFolder(id: id, name: data?["name"]?.string ?? "Dokumente")
    }

    static func folder(_ folder: DocumentFolder) async throws -> (folders: [DocumentFolder], documents: [SchoolDocument]) {
        if isDemo { return DemoData.folder(folder.id) }
        let data = try await single(APICall(module: "documents", endpoint: "get-folder-contents",
                                            parameters: ["folderId": Poqa.numericId(folder.id)]),
                                    error: "Ordner konnte nicht geladen werden")
        return Parsers.folderContents(from: data)
    }

    // MARK: Wahlen

    static func elections() async throws -> [Election] {
        if isDemo { return DemoData.elections() }
        let results = try await api.call(
            Poqa.call(model: "modules/electives/election", options: ["order": [["end", "DESC"]]], module: "electives")
                + Poqa.call(model: "modules/electives/sub-election", options: ["where": ["electionId": ["$ne": nil]]],
                            module: "electives")
        )
        guard let elections = Poqa.first(results[0..<2]) else { throw SMError.server("Wahlen nicht verfügbar.") }
        return Parsers.elections(from: elections.data, electives: Poqa.first(results[2..<4])?.data)
    }

    /// `priorities` ist nach Rang indiziert und enthält die ganzen Wahlobjekte.
    /// Schlüssel ist die Sub-Election-Id oder der Text `"null"`.
    static func savePriorities(_ election: Election, ranked: [Elective], studentId: String) async throws {
        if isDemo { return }
        _ = try await single(APICall(module: "electives", endpoint: "save-priorities", parameters: [
            "priorities": .object([election.subElectionId ?? "null": .array(ranked.map(\.raw))]),
            "election": ["id": Poqa.numericId(election.id)],
            "student": ["id": Poqa.numericId(studentId)],
        ]), error: "Wahl wurde nicht gespeichert")
    }
}

// MARK: - Dateien

/// Lädt Anhänge und Dokumente vom Storage-Host der Schule.
enum FileDownloader {
    nonisolated(unsafe) private static var storageHost: String?

    /// Wie die Web-App: `<storage>/download-file/<base64(JSON des Deskriptors)>`. Der Server entschlüsselt
    /// selbst (der Schlüssel steckt im Deskriptor) und liefert die Datei im Klartext.
    static func download(_ file: StoredFile) async throws -> URL {
        if SessionStore.shared.isDemo { return try demoFile(file) }
        guard var parts = Parsers.descriptorArray(file.descriptor) else {
            throw SMError.server("Diese Datei kann die App nicht öffnen.")
        }
        // Die Web-App wandelt die Schul-Id in eine Zahl um (`i[0]*1`) und serialisiert kompakt.
        if let institution = parts[0].string.flatMap(Int.init) { parts[0] = .int(institution) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let descriptor = try encoder.encode(JSONValue.array(parts)).base64EncodedString()

        let host = try await remoteStorageHost()
        guard let url = URL(string: "\(host)/download-file/\(descriptor)") else {
            throw SMError.server("Ungültige Datei-Adresse.")
        }
        var request = URLRequest(url: url)
        if let token = try? await SchulmanagerAPI.shared.validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, !data.isEmpty else {
            throw SMError.server("Download fehlgeschlagen (HTTP \(status)).")
        }
        // Rückfall, falls doch verschlüsselt ausgeliefert wird: AES-GCM wie im Web-Client (12 Byte IV vorne).
        let key = parts[3].string.flatMap { Data(base64Encoded: $0) }
        let plain = looksLikeFile(data) ? data : (decryptGCM(data, key: key) ?? data)
        return try save(plain, name: file.name)
    }

    private static func remoteStorageHost() async throws -> String {
        if let storageHost { return storageHost }
        let result = try? await SchulmanagerAPI.shared.call([APICall(module: "main", endpoint: "get-remote-storage-url", parameters: [:])])
        let host = result?.first?.data?.string ?? "https://storage.schulmanager-online.de"
        storageHost = host.hasSuffix("/") ? String(host.dropLast()) : host
        return storageHost!
    }

    /// Format des Web-Clients: 12 Byte IV, danach Ciphertext mit 16 Byte Tag.
    static func decryptGCM(_ data: Data, key: Data?) -> Data? {
        guard let key, data.count > 28,
              let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: data.prefix(12)),
                                               ciphertext: data.dropFirst(12).dropLast(16),
                                               tag: data.suffix(16)) else { return nil }
        return try? AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    private static func looksLikeFile(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x25, 0x50, 0x44, 0x46], [0x89, 0x50, 0x4E, 0x47], [0xFF, 0xD8, 0xFF], [0x47, 0x49, 0x46, 0x38],
            [0x50, 0x4B, 0x03, 0x04], [0xD0, 0xCF, 0x11, 0xE0], [0x52, 0x49, 0x46, 0x46], [0x49, 0x44, 0x33],
        ]
        let head = [UInt8](data.prefix(8))
        if signatures.contains(where: { head.starts(with: $0) }) { return true }
        if head.count >= 8, head[4...7] == [0x66, 0x74, 0x79, 0x70] { return true } // MP4/HEIC "ftyp"
        let text = String(decoding: data.prefix(200), as: UTF8.self).lowercased()
        return text.hasPrefix("<!doctype") || text.hasPrefix("<html") || text.hasPrefix("<?xml")
    }

    private static func save(_ data: Data, name: String) throws -> URL {
        let safe = name.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Anhaenge", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safe.isEmpty ? "Datei" : safe)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func demoFile(_ file: StoredFile) throws -> URL {
        let text = "Beispieldatei „\(file.name)“\n\nIm Demo-Modus gibt es keine echten Dateien. Mit deinem Konto öffnet sich hier das Original."
        return try save(Data(text.utf8), name: (file.name as NSString).deletingPathExtension + ".txt")
    }
}

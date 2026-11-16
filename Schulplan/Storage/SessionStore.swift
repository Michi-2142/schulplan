import Foundation

struct Credentials: Codable, Sendable {
    var emailOrUsername: String
    var password: String
    var userId: JSONValue?
    var institutionId: JSONValue?
}

/// Persistenter Zustand außerhalb der UI: Zugangsdaten (Keychain), Nutzer, Schnappschuss, Verlauf.
/// Alle Zugriffe sind synchron und klein, deshalb reicht ein Lock statt eines Actors.
final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore()

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Schulplan", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Keychain

    var credentials: Credentials? {
        get { Keychain.getCodable(Credentials.self, for: "credentials") }
        set { Keychain.setCodable(newValue, for: "credentials") }
    }

    /// `userDevice` aus dem Login — erlaubt neue Tokens ohne Passwort.
    var device: JSONValue? {
        get { Keychain.getCodable(JSONValue.self, for: "device") }
        set { Keychain.setCodable(newValue, for: "device") }
    }

    // MARK: Nutzer

    var user: JSONValue? {
        get { read(JSONValue.self, "user.json") }
        set { write(newValue, "user.json") }
    }

    var students: [Student] {
        get { read([Student].self, "students.json") ?? [] }
        set { write(newValue, "students.json") }
    }

    var selectedStudentId: String? {
        get { defaults.string(forKey: "selectedStudentId") }
        set { defaults.set(newValue, forKey: "selectedStudentId") }
    }

    var selectedStudent: Student? {
        let all = activeStudents
        return all.first { $0.id == selectedStudentId } ?? all.first
    }

    var isDemo: Bool {
        get { defaults.bool(forKey: "demoMode") }
        set { defaults.set(newValue, forKey: "demoMode") }
    }

    var isLoggedIn: Bool { isDemo || (credentials != nil && !students.isEmpty) }

    /// Alle Kinder, die abgeglichen werden (im Demo-Modus die Beispielkinder).
    var activeStudents: [Student] { isDemo ? DemoData.students : students }

    // MARK: Daten

    /// Stand je Kind. Ältere Versionen hatten nur eine `snapshot.json` – die wird weiter gelesen.
    func snapshot(for studentId: String) -> Snapshot? {
        if let snapshot = read(Snapshot.self, "snapshot-\(studentId).json") { return snapshot }
        if let legacy = read(Snapshot.self, "snapshot.json"), legacy.studentId == studentId { return legacy }
        return nil
    }

    func save(_ snapshot: Snapshot) {
        write(snapshot, "snapshot-\(snapshot.studentId).json")
    }

    func removeAllSnapshots() {
        lock.withLock {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files where file.hasPrefix("snapshot") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    var history: [ChangeEvent] {
        get { read([ChangeEvent].self, "history.json") ?? [] }
        set { write(Array(newValue.prefix(300)), "history.json") }
    }

    var lastBackgroundRun: Date? {
        get { defaults.object(forKey: "lastBackgroundRun") as? Date }
        set { defaults.set(newValue, forKey: "lastBackgroundRun") }
    }

    func clearAll() {
        credentials = nil
        device = nil
        lock.withLock {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        selectedStudentId = nil
        isDemo = false
        lastBackgroundRun = nil
    }

    // MARK: Dateien

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        lock.withLock {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    private func write<T: Encodable>(_ value: T?, _ name: String) {
        lock.withLock {
            let url = directory.appendingPathComponent(name)
            guard let value else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(value) else { return }
            // Bewusst ohne `.complete`: der Hintergrund-Abruf muss auch bei gesperrtem Gerät schreiben.
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

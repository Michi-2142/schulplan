import CommonCrypto
import Foundation

enum SMError: LocalizedError, Equatable {
    case invalidCredentials
    case needsLogin
    case http(Int)
    case network(String)
    case server(String)
    case unsupportedAccount

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Benutzername oder Passwort ist falsch."
        case .needsLogin: "Anmeldung abgelaufen. Bitte melde dich neu an."
        case .http(let code) where code == 429: "Zu viele Anfragen. Bitte gleich nochmal versuchen."
        case .http(let code) where code == 503: "Schulmanager wird gerade gewartet."
        case .http(let code): "Schulmanager antwortet mit Fehler \(code)."
        case .network(let message): "Keine Verbindung: \(message)"
        case .server(let message): message
        case .unsupportedAccount: "Für dieses Konto wurde kein Schüler gefunden (Lehrerkonten werden nicht unterstützt)."
        }
    }
}

enum LoginOutcome: Sendable {
    case success(students: [Student])
    case chooseAccount([AccountChoice])
    case twoFactor
}

struct AccountChoice: Identifiable, Hashable, Sendable {
    var id: String { "\(userId.string ?? "")-\(institutionId.string ?? "")" }
    var userId: JSONValue
    var institutionId: JSONValue
    var label: String
}

struct APICall: Sendable {
    var module: String
    var endpoint: String
    var parameters: JSONValue?

    var json: JSONValue {
        var dict: [String: JSONValue] = ["moduleName": .string(module), "endpointName": .string(endpoint)]
        if let parameters { dict["parameters"] = parameters }
        return .object(dict)
    }
}

struct APIResult: Sendable {
    var status: Int
    var data: JSONValue?
    var ok: Bool { (200..<300).contains(status) }
}

/// Inoffizieller Client für die interne JSON-API von Schulmanager Online.
///
/// Rekonstruiert aus mehreren Community-Projekten (Home-Assistant-Integration, schulmanager-mcp, Schulflow):
/// - `POST /api/get-salt` → Salt, `POST /api/login` mit PBKDF2-SHA512-Hash → JWT + `userDevice`
/// - `POST /api/login-with-user-device` → frisches JWT ohne Passwort
/// - `POST /api/calls` → Batch aus `{moduleName, endpointName, parameters}`, Ergebnisse positionsgebunden
/// - `x-new-bearer-token` rotiert das JWT bei fast jedem Aufruf
actor SchulmanagerAPI {
    static let shared = SchulmanagerAPI()

    private let base = URL(string: "https://login.schulmanager-online.de")!
    private let session: URLSession
    private let store = SessionStore.shared
    private var token: String?
    private var bundleVersion = "0000000000"
    private var triedBundleDiscovery = false
    private var lastRequestAt: Date = .distantPast

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Schulplan-iOS/1.0 (inoffizieller privater Client)",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "de-DE,de;q=0.9",
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Anmeldung

    func login(_ credentials: Credentials, twoFactorCode: String? = nil) async throws -> LoginOutcome {
        let saltResponse = try await post("/api/get-salt", body: [
            "emailOrUsername": .string(credentials.emailOrUsername),
            "mobileApp": true,
            "institutionId": credentials.institutionId ?? .null,
        ], auth: false)
        let salt = saltResponse.string ?? saltResponse["salt"]?.string
        let hash = salt.flatMap { Self.pbkdf2(password: credentials.password, salt: $0) }

        let response: JSONValue
        do {
            response = try await post("/api/login", body: [
                "emailOrUsername": .string(credentials.emailOrUsername),
                "password": .string(credentials.password),
                "hash": JSONValue(hash),
                "mobileApp": true,
                "twoFactorCode": JSONValue(twoFactorCode),
                "userId": credentials.userId ?? .null,
                "institutionId": credentials.institutionId ?? .null,
            ], auth: false)
        } catch SMError.http(let code) where code == 401 || code == 403 {
            throw SMError.invalidCredentials
        }

        if let accounts = response["multipleAccounts"]?.array, !accounts.isEmpty {
            return .chooseAccount(accounts.compactMap { account in
                guard let userId = account["userId"] ?? account["id"] else { return nil }
                let name = [account["firstname"]?.string, account["lastname"]?.string].compactMap { $0 }.joined(separator: " ")
                let school = account["institutionName"]?.string ?? account["institution"]?["name"]?.string
                return AccountChoice(
                    userId: userId,
                    institutionId: account["institutionId"] ?? account["institution"]?["id"] ?? .null,
                    label: [name, school].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                )
            })
        }
        if response["requireTwoFactorEmailCode"]?.bool == true || response["requireTOTP"]?.bool == true {
            return .twoFactor
        }
        guard let jwt = response["jwt"]?.string ?? response["token"]?.string, let user = response["user"] else {
            throw SMError.invalidCredentials
        }

        let students = Self.students(from: user)
        guard !students.isEmpty else { throw SMError.unsupportedAccount }

        token = jwt
        store.credentials = credentials
        store.device = response["userDevice"]
        store.user = user
        store.students = students
        if store.selectedStudent == nil || !students.contains(where: { $0.id == store.selectedStudentId }) {
            store.selectedStudentId = students.first?.id
        }
        return .success(students: students)
    }

    func logout() async {
        if let device = store.device {
            _ = try? await post("/api/delete-user-device", body: ["device": device], auth: true)
        }
        token = nil
    }

    /// Sorgt für ein gültiges JWT: zuerst Gerätelogin, dann gespeicherte Zugangsdaten.
    private func reauthenticate() async throws {
        token = nil
        if let device = store.device {
            if let response = try? await post("/api/login-with-user-device",
                                              body: ["device": device, "reason": "app-launch"], auth: false),
               let jwt = response["jwt"]?.string {
                token = jwt
                if let user = response["user"] { refreshStudents(from: user) }
                return
            }
        }
        guard let credentials = store.credentials else { throw SMError.needsLogin }
        switch try await login(credentials) {
        case .success: return
        case .chooseAccount, .twoFactor: throw SMError.needsLogin
        }
    }

    private func refreshStudents(from user: JSONValue) {
        let students = Self.students(from: user)
        guard !students.isEmpty else { return }
        store.user = user
        store.students = students
    }

    private func ensureToken() async throws {
        if let token {
            // Ohne lesbares `exp` vertrauen wir dem Token, bis der Server 401 meldet.
            guard let expiry = Self.expiry(of: token) else { return }
            if expiry.timeIntervalSinceNow > 60 { return }
        }
        try await reauthenticate()
    }

    /// Gültiges JWT, z. B. für Datei-Downloads am Storage-Host.
    func validToken() async throws -> String {
        try await ensureToken()
        guard let token else { throw SMError.needsLogin }
        return token
    }

    // MARK: - Batch-Aufrufe

    func call(_ calls: [APICall]) async throws -> [APIResult] {
        try await ensureToken()
        do {
            return try await batchWithReauth(calls)
        } catch SMError.http(400) {
            // 1. Evtl. neue `bundleVersion` auf der Webseite – einmal nachschlagen.
            if !triedBundleDiscovery {
                triedBundleDiscovery = true
                if let version = await discoverBundleVersion() {
                    bundleVersion = version
                    if let results = try? await batchWithReauth(calls) { return results }
                }
            }
            // 2. Ein einzelnes unbekanntes Modul darf nicht den ganzen Abruf (inkl. Stundenplan) kippen.
            guard calls.count > 1 else { throw SMError.http(400) }
            var results: [APIResult] = []
            for call in calls {
                let single = try? await batchWithReauth([call])
                results.append(single?.first ?? APIResult(status: 400, data: nil))
            }
            return results
        }
    }

    private func batchWithReauth(_ calls: [APICall]) async throws -> [APIResult] {
        do {
            return try await performBatch(calls)
        } catch SMError.http(401) {
            try await reauthenticate()
            return try await performBatch(calls)
        }
    }

    private func performBatch(_ calls: [APICall]) async throws -> [APIResult] {
        let body: JSONValue = [
            "bundleVersion": .string(bundleVersion),
            "requests": .array(calls.map(\.json)),
        ]
        let response = try await post("/api/calls", body: body, auth: true)
        let results = response["results"]?.array ?? []
        if results.contains(where: { $0["status"]?.int == 401 }) { throw SMError.http(401) }
        return calls.indices.map { index in
            guard let result = results[safe: index] else { return APIResult(status: 0, data: nil) }
            return APIResult(status: result["status"]?.int ?? 0, data: result["data"])
        }
    }

    // MARK: - HTTP

    private func post(_ path: String, body: JSONValue, auth: Bool) async throws -> JSONValue {
        // Fair Use: nie schneller als ein Request pro Sekunde.
        let wait = 1.0 - Date.now.timeIntervalSince(lastRequestAt)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        lastRequestAt = .now

        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if auth, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try body.encoded()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SMError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SMError.network("Ungültige Antwort") }
        if let rotated = http.value(forHTTPHeaderField: "x-new-bearer-token"), !rotated.isEmpty { token = rotated }
        guard (200..<300).contains(http.statusCode) else { throw SMError.http(http.statusCode) }
        guard !data.isEmpty else { return .null }
        if let json = try? JSONValue.decode(data) { return json }
        return .string(String(decoding: data, as: UTF8.self))
    }

    private func discoverBundleVersion() async -> String? {
        guard let (data, _) = try? await session.data(from: base) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let scripts = html.matches(of: /(?:src|href)="([^"]+\.js)"/).map { String($0.output.1) }
        for script in scripts {
            guard let url = URL(string: script, relativeTo: base),
                  let (jsData, _) = try? await session.data(from: url) else { continue }
            let js = String(decoding: jsData, as: UTF8.self)
            if let match = js.firstMatch(of: /bundleVersion[\s\S]{0,120}?["']([a-f0-9]{10})["']/) {
                return String(match.output.1)
            }
        }
        return nil
    }

    // MARK: - Helfer

    static func pbkdf2(password: String, salt: String) -> String? {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        var derived = [UInt8](repeating: 0, count: 512)
        let status = passwordBytes.withUnsafeBytes { passwordPointer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordPointer.baseAddress?.assumingMemoryBound(to: CChar.self), passwordBytes.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 99_999,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { return nil }
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONValue.decode(data),
              let exp = json["exp"]?.int else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(exp))
    }

    /// Schülerkonten: `associatedStudent`. Elternkonten: `associatedParents[].student`.
    static func students(from user: JSONValue) -> [Student] {
        var raw: [JSONValue] = []
        if let student = user["associatedStudent"] { raw.append(student) }
        raw += user["associatedStudents"]?.array ?? []
        raw += (user["associatedParents"]?.array ?? []).compactMap { $0["student"] }

        var seen = Set<String>()
        return raw.compactMap { json in
            guard let id = json["id"]?.string, seen.insert(id).inserted else { return nil }
            return Student(
                id: id,
                firstname: json["firstname"]?.string ?? "",
                lastname: json["lastname"]?.string ?? "",
                className: json["class"]?["name"]?.string ?? json["className"]?.string,
                raw: json
            )
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

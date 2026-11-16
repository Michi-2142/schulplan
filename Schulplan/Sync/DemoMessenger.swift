import Foundation

/// Unterhaltungen für den Demo-Modus. Hält die Nachrichten im Speicher;
/// gelegentlich schreibt „die Schule“ zurück, damit man Mitteilungen sieht.
final class DemoMessenger: @unchecked Sendable {
    static let shared = DemoMessenger()

    private let lock = NSLock()
    private var conversations: [String: [ChatMessage]]
    private var meta: [String: (subject: String, sender: String)]

    private init() {
        func ago(_ minutes: Double) -> String { ISO8601DateFormatter().string(from: .now.addingTimeInterval(-minutes * 60)) }
        meta = [
            "s1": ("Wandertag am Freitag", "Frau Hofmann"),
            "s2": ("Mathe-Schulaufgabe", "Herr Karl"),
            "s3": ("Elternbeirat: Weihnachtsbasar", "Elternbeirat 7b"),
        ]
        conversations = [
            "s1": [
                ChatMessage(id: "m1", text: "Liebe Eltern, am Freitag findet unser Wandertag statt. Treffpunkt ist um 8:00 Uhr am Haupteingang. Bitte an feste Schuhe und Brotzeit denken.", sender: "Frau Hofmann", sentAt: ago(60 * 26), isOwn: false),
                ChatMessage(id: "m2", text: "Danke für die Info! Wann sind die Kinder ungefähr zurück?", sender: "Ich", sentAt: ago(60 * 25), isOwn: true),
                ChatMessage(id: "m3", text: "Wir sind gegen 13:30 Uhr wieder an der Schule.", sender: "Frau Hofmann", sentAt: ago(40), isOwn: false),
            ],
            "s2": [
                ChatMessage(id: "m4", text: "Guten Tag, die Schulaufgabe wird um eine Woche verschoben. Das Übungsblatt ist im Dokumentenbereich.", sender: "Herr Karl", sentAt: ago(60 * 50), isOwn: false, attachments: [StoredFile(name: "Übungsblatt_Funktionen.pdf", descriptor: .null)]),
            ],
            "s3": [
                ChatMessage(id: "m5", text: "Wer kann am 5.12. einen Kuchen für den Basar backen? Bitte kurz hier antworten.", sender: "Elternbeirat 7b", sentAt: ago(60 * 72), isOwn: false),
                ChatMessage(id: "m6", text: "Wir bringen einen Marmorkuchen mit.", sender: "Ich", sentAt: ago(60 * 70), isOwn: true),
            ],
        ]
    }

    func messages(for subscriptionId: String) -> [ChatMessage] {
        lock.withLock { conversations[subscriptionId] ?? [] }
    }

    func append(_ text: String, to subscriptionId: String) {
        lock.withLock {
            conversations[subscriptionId, default: []].append(ChatMessage(
                id: UUID().uuidString, text: text, sender: "Ich",
                sentAt: ISO8601DateFormatter().string(from: .now), isOwn: true
            ))
        }
    }

    /// Schreibt ab und zu eine Antwort der Lehrkraft (für den Demo-Abgleich).
    func maybeReceive() {
        guard Int.random(in: 0..<3) == 0, let id = ["s1", "s2", "s3"].randomElement() else { return }
        let replies = ["Vielen Dank für die Rückmeldung!", "Kurze Erinnerung: Bitte das Formular bis Mittwoch abgeben.",
                       "Morgen entfällt die 6. Stunde, die Kinder dürfen früher gehen."]
        lock.withLock {
            conversations[id, default: []].append(ChatMessage(
                id: UUID().uuidString, text: replies.randomElement()!, sender: meta[id]?.sender ?? "Schule",
                sentAt: ISO8601DateFormatter().string(from: .now), isOwn: false
            ))
        }
    }

    /// Thread-Liste wie von `get-subscriptions`. `read` = vom Nutzer schon geöffnete Threads.
    func threads(previous: [MessageThread]?) -> [MessageThread] {
        lock.withLock {
            meta.keys.sorted().map { id in
                let messages = conversations[id] ?? []
                let last = messages.last
                let old = previous?.first { $0.subscriptionId == id }
                var unread = old?.unreadCount ?? (id == "s1" ? 1 : 0)
                if let old, let last, !last.isOwn, (last.sentAt ?? "") > (old.lastMessageAt ?? "") { unread += 1 }
                return MessageThread(
                    id: "t-\(id)", subscriptionId: id, subject: meta[id]!.subject, sender: meta[id]!.sender,
                    recipients: "Eltern der Klasse 7b", lastMessageAt: last?.sentAt, unreadCount: unread,
                    preview: last.map { ($0.isOwn ? "Du: " : "") + $0.text }
                )
            }
            .sorted { ($0.lastMessageAt ?? "") > ($1.lastMessageAt ?? "") }
        }
    }
}

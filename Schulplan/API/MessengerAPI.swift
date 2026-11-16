import Foundation

/// Messenger-Aufrufe, die nicht zum regelmäßigen Abgleich gehören (Chat öffnen, antworten).
/// Ids gehen als **Strings** an die API – Zahlen oder Objekte beantwortet sie mit 500.
enum MessengerAPI {
    private static var isDemo: Bool { SessionStore.shared.isDemo }

    static func messages(for thread: MessageThread) async throws -> [ChatMessage] {
        if isDemo { return DemoMessenger.shared.messages(for: thread.subscriptionId) }
        let result = try await SchulmanagerAPI.shared.call([
            APICall(module: "messenger", endpoint: "get-messages-by-subscription", parameters: [
                "subscriptionId": .string(thread.subscriptionId), "loadAll": true,
            ]),
        ])
        guard let first = result.first, first.ok else {
            throw SMError.server("Nachrichten konnten nicht geladen werden (Status \(result.first?.status ?? 0)).")
        }
        return Parsers.messages(from: first.data)
    }

    static func markRead(_ thread: MessageThread) async {
        if isDemo { return }
        _ = try? await SchulmanagerAPI.shared.call([
            APICall(module: "messenger", endpoint: "set-subscription-read", parameters: [
                "subscription": ["id": .string(thread.subscriptionId)],
            ]),
        ])
    }

    static func send(_ text: String, in thread: MessageThread) async throws {
        if isDemo {
            DemoMessenger.shared.append(text, to: thread.subscriptionId)
            return
        }
        let result = try await SchulmanagerAPI.shared.call([
            APICall(module: "messenger", endpoint: "send-message", parameters: [
                "thread": ["id": .string(thread.id)], "text": .string(text),
            ]),
        ])
        guard let first = result.first, first.ok else {
            throw SMError.server("Nachricht wurde nicht gesendet (Status \(result.first?.status ?? 0)).")
        }
    }
}

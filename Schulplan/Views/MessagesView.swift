import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var debugThread: MessageThread?

    private var threads: [MessageThread] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.threads }
        return model.threads.filter {
            $0.subject.localizedCaseInsensitiveContains(query)
                || $0.sender.localizedCaseInsensitiveContains(query)
                || ($0.preview ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Screen(title: "Nachrichten",
               subtitle: model.unreadMessages > 0 ? "\(model.unreadMessages) ungelesen" : nil) {
            LazyVStack(spacing: 10) {
                if model.snapshot?.failedModules.contains("Nachrichten") == true, model.threads.isEmpty {
                    EmptyStateCard(icon: "bubble.left.and.exclamationmark.bubble.right", title: "Nachrichten nicht verfügbar",
                                   message: "Der Messenger ist für dein Konto oder deine Schule nicht freigeschaltet.")
                } else if threads.isEmpty {
                    EmptyStateCard(icon: "bubble.left.and.bubble.right", title: search.isEmpty ? "Keine Nachrichten" : "Nichts gefunden",
                                   message: search.isEmpty ? "Sobald dir eine Lehrkraft schreibt, erscheint die Unterhaltung hier." : nil)
                } else {
                    ForEach(threads) { thread in
                        NavigationLink(value: thread) {
                            ThreadRow(thread: thread)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: MessageThread.self) { thread in
            ChatView(thread: thread)
        }
        #if DEBUG
        .navigationDestination(isPresented: Binding(
            get: { debugThread != nil }, set: { if !$0 { debugThread = nil } }
        )) {
            if let debugThread { ChatView(thread: debugThread) }
        }
        .task {
            // Für Screenshots im Simulator: `-openThread <subscriptionId>`
            try? await Task.sleep(for: .seconds(1.5))
            if let id = UserDefaults.standard.string(forKey: "openThread") {
                debugThread = model.threads.first { $0.subscriptionId == id }
            }
        }
        #endif
    }
}

struct ThreadRow: View {
    let thread: MessageThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: thread.sender.isEmpty ? thread.subject : thread.sender)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.sender.isEmpty ? "Schule" : thread.sender)
                        .font(.subheadline.weight(thread.unreadCount > 0 ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let date = thread.lastMessageDate {
                        Text(MessageTime.short(date))
                            .font(.caption)
                            .foregroundStyle(thread.unreadCount > 0 ? Color.accentColor : .secondary)
                    }
                }
                Text(thread.subject)
                    .font(.subheadline.weight(thread.unreadCount > 0 ? .semibold : .regular))
                    .lineLimit(1)
                HStack(alignment: .top) {
                    Text(thread.preview ?? " ")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: .capsule)
                    }
                }
            }
        }
        .padding(14)
        .contentShape(.rect)
        .glassCard(tint: thread.unreadCount > 0 ? .accentColor : nil, cornerRadius: 22, interactive: true)
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.count >= 2 ? [words.first!, words.last!].compactMap(\.first) : Array(words.first?.prefix(2) ?? "")
        return String(letters).uppercased()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SubjectColor.color(for: name).gradient, in: .circle)
    }
}

enum MessageTime {
    /// „14:32“ heute, „gestern“, „Mo“ diese Woche, sonst „12.11.“
    static func short(_ date: Date) -> String {
        let calendar = SchoolCalendar.calendar
        if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))) }
        if calendar.isDateInYesterday(date) { return "gestern" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 6 {
            return SchoolCalendar.shortWeekday(SchoolCalendar.iso(date))
        }
        return SchoolCalendar.dayMonth(SchoolCalendar.iso(date))
    }
}

// MARK: - Chat

struct ChatView: View {
    @Environment(AppModel.self) private var model
    let thread: MessageThread

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    header
                    if isLoading, messages.isEmpty {
                        ProgressView().padding(.top, 40)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if showsDay(at: index), let date = message.sentDate {
                            Text(dayLabel(date))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                                .padding(.top, 10)
                        }
                        MessageBubble(message: message, showSender: showsSender(at: index))
                            .id(message.id)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background { AppBackground() }
            .safeAreaInset(edge: .bottom) { composer }
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .navigationTitle(thread.sender.isEmpty ? thread.subject : thread.sender)
        .navigationSubtitle(thread.sender.isEmpty ? "" : thread.subject)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(markRead: true) }
        .task {
            // Solange der Chat offen ist, jede Minute auf Antworten prüfen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await load(markRead: false)
            }
        }
        .refreshable { await load(markRead: false) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Avatar(name: thread.sender.isEmpty ? thread.subject : thread.sender, size: 56)
            Text(thread.subject).font(.headline).multilineTextAlignment(.center)
            if let recipients = thread.recipients {
                Text("An: \(recipients)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Nachricht", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            Button {
                Task { await send() }
            } label: {
                Group {
                    if isSending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") }
                }
                .font(.body.weight(.bold))
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func showsDay(at index: Int) -> Bool {
        guard let date = messages[index].sentDate else { return false }
        guard index > 0, let previous = messages[index - 1].sentDate else { return true }
        return !SchoolCalendar.calendar.isDate(date, inSameDayAs: previous)
    }

    private func showsSender(at index: Int) -> Bool {
        let message = messages[index]
        guard !message.isOwn else { return false }
        return index == 0 || messages[index - 1].sender != message.sender || showsDay(at: index)
    }

    private func dayLabel(_ date: Date) -> String {
        let iso = SchoolCalendar.iso(date)
        if iso == SchoolCalendar.today { return "Heute" }
        if iso == SchoolCalendar.addDays(-1, to: SchoolCalendar.today) { return "Gestern" }
        return "\(SchoolCalendar.longWeekday(iso)), \(SchoolCalendar.dayMonth(iso))"
    }

    private func load(markRead: Bool) async {
        do {
            let loaded = try await MessengerAPI.messages(for: thread)
            if loaded != messages { withAnimation(.smooth) { messages = loaded } }
            error = nil
            if markRead { await model.markRead(thread) }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        // Sofort anzeigen, bei Fehler wieder entfernen.
        let pending = ChatMessage(id: "pending-\(UUID())", text: text, sender: "Ich",
                                  sentAt: ISO8601DateFormatter().string(from: .now), isOwn: true)
        withAnimation(.smooth) { messages.append(pending) }
        draft = ""
        do {
            try await MessengerAPI.send(text, in: thread)
            model.didSend(text, in: thread)
            await load(markRead: false)
        } catch {
            withAnimation { messages.removeAll { $0.id == pending.id } }
            draft = text
            self.error = error.localizedDescription
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let showSender: Bool

    var body: some View {
        HStack {
            if message.isOwn { Spacer(minLength: 50) }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 3) {
                if showSender {
                    Text(message.sender)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SubjectColor.color(for: message.sender))
                        .padding(.horizontal, 6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(message.isOwn ? .white : .primary)
                        .textSelection(.enabled)
                    ForEach(message.attachments) { AttachmentButton(file: $0, onDark: message.isOwn) }
                    if let date = message.sentDate {
                        Text(date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))
                            .font(.caption2)
                            .foregroundStyle(message.isOwn ? .white.opacity(0.75) : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(message.isOwn ? .regular.tint(.accentColor) : .regular, in: .rect(cornerRadius: 20))
                .opacity(message.id.hasPrefix("pending-") ? 0.6 : 1)
            }
            if !message.isOwn { Spacer(minLength: 50) }
        }
    }
}

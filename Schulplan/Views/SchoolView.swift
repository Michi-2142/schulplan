import SwiftUI

enum SchoolPage: Hashable {
    case letters, tiles, events, homework, exams
    case grades, absences, exemptions, parentTalks, documents, allday, elections, invoices
}

/// Weitere Bereiche – nur sichtbar, wenn die Schule das Modul aktiv hat (oder schon Daten da sind).
private struct ExtraModule: Identifiable {
    let page: SchoolPage
    let key: String
    let title: String
    let icon: String
    let color: Color
    var id: String { key }
}

struct SchoolView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showSickNote = false
    @State private var debugPage: String?

    private static let extras: [ExtraModule] = [
        ExtraModule(page: .grades, key: "grades", title: "Noten", icon: "star.fill", color: .indigo),
        ExtraModule(page: .absences, key: "absences", title: "Fehlzeiten & Krankmeldung", icon: "cross.case.fill", color: .orange),
        ExtraModule(page: .exemptions, key: "exemptions", title: "Beurlaubung", icon: "calendar.badge.plus", color: .green),
        ExtraModule(page: .parentTalks, key: "parenttalks", title: "Elternsprechtag", icon: "person.2.fill", color: .purple),
        ExtraModule(page: .documents, key: "documents", title: "Dokumente", icon: "folder.fill", color: .blue),
        ExtraModule(page: .allday, key: "allday", title: "Ganztag", icon: "figure.and.child.holdinghands", color: .teal),
        ExtraModule(page: .elections, key: "electives", title: "Wahlen", icon: "checklist", color: .mint),
        ExtraModule(page: .invoices, key: "invoices", title: "Rechnungen", icon: "eurosign.circle.fill", color: .brown),
    ]

    private func isAvailable(_ module: ExtraModule) -> Bool {
        guard let modules = model.snapshot?.modules, !modules.isEmpty else { return model.isDemo }
        let active = Set(modules.map(\.name))
        let aliases = SyncService.moduleAliases[module.key] ?? [module.key]
        return aliases.contains(where: active.contains)
    }

    private var canReportSick: Bool {
        guard let modules = model.snapshot?.modules else { return model.isDemo }
        return modules.contains { $0.name == "sick" } || model.isDemo
    }

    private func detail(for module: ExtraModule) -> String? {
        let snapshot = model.snapshot
        switch module.page {
        case .grades:
            let count = snapshot?.grades?.reduce(0) { $0 + $1.grades.count } ?? 0
            return count > 0 ? "\(count) Noten" : nil
        case .absences:
            let open = snapshot?.absences?.filter { !$0.excused }.count ?? 0
            return open > 0 ? "\(open) unentschuldigt" : nil
        case .exemptions:
            let open = snapshot?.exemptions?.filter { $0.granted == nil }.count ?? 0
            return open > 0 ? "\(open) offen" : nil
        case .parentTalks:
            return snapshot?.parentTalks?.contains(where: \.isOpenForBooking) == true ? "Anmeldung offen" : nil
        case .invoices:
            let open = snapshot?.invoices?.filter { !$0.paid }.count ?? 0
            return open > 0 ? "\(open) offen" : nil
        case .allday:
            return snapshot?.alldayNotes?.first.map { _ in "Neue Mitteilungen" }
        default:
            return nil
        }
    }

    @ViewBuilder
    private var extraModules: some View {
        let available = Self.extras.filter(isAvailable)
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Weitere Bereiche")
                if canReportSick {
                    Button { showSickNote = true } label: {
                        Label("Kind krankmelden", systemImage: "cross.case.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .controlSize(.large)
                }
                VStack(spacing: 0) {
                    ForEach(available) { module in
                        NavigationLink(value: module.page) {
                            HStack(spacing: 12) {
                                Image(systemName: module.icon).foregroundStyle(module.color).frame(width: 26)
                                Text(module.title).font(.subheadline.weight(.medium))
                                Spacer()
                                if let detail = detail(for: module) {
                                    Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if module.id != available.last?.id { Divider().padding(.leading, 54) }
                    }
                }
                .glassCard(cornerRadius: 20)
            }
            .padding(.top, 6)
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Screen(title: "Schule", subtitle: model.selectedStudent?.className.map { "Klasse \($0)" }) {
            VStack(spacing: 14) {
                if model.openLetters > 0 {
                    NavigationLink(value: SchoolPage.letters) {
                        Label("\(model.openLetters) Elternbrief\(model.openLetters == 1 ? "" : "e") warten auf deine Bestätigung",
                              systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCard(tint: .orange, cornerRadius: 18, interactive: true)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    tile(.letters, icon: "envelope.open.fill", color: .orange, title: "Elternbriefe",
                         value: model.openLetters > 0 ? "\(model.openLetters) offen" : "\(model.letters.count)",
                         detail: model.letters.first?.title, highlighted: model.openLetters > 0)
                    tile(.tiles, icon: "pin.fill", color: .pink, title: "Pinnwand",
                         value: "\(model.tiles.count)", detail: model.tiles.first?.title)
                    tile(.events, icon: "calendar", color: .red, title: "Termine",
                         value: model.upcomingEvents.first.map { SchoolCalendar.relativeLabel($0.day) } ?? "–",
                         detail: model.upcomingEvents.first?.title)
                    tile(.homework, icon: "book.closed.fill", color: .teal, title: "Hausaufgaben",
                         value: model.openHomeworkCount > 0 ? "\(model.openHomeworkCount) offen" : "erledigt",
                         detail: nil, highlighted: model.openHomeworkCount > 0)
                    tile(.exams, icon: "doc.text.fill", color: .indigo, title: "Arbeiten",
                         value: nextExamLabel, detail: nextExam?.subject)
                    Button {
                        if let url = URL(string: "https://login.schulmanager-online.de/") { openURL(url) }
                    } label: {
                        cardContent(icon: "safari.fill", color: .blue, title: "Im Browser", value: "Öffnen",
                                    detail: "Alles, was die App noch nicht kann")
                    }
                    .buttonStyle(.plain)
                }

                extraModules

                ModulesSection()
            }
        }
        .sheet(isPresented: $showSickNote) { SickNoteForm() }
        .navigationDestination(for: SchoolPage.self) { page in
            switch page {
            case .letters: LettersView()
            case .tiles: TilesView()
            case .events: EventsView()
            case .homework: TasksView(section: .homework)
            case .exams: TasksView(section: .exams)
            case .grades: GradesView()
            case .absences: AbsencesView()
            case .exemptions: ExemptionsView()
            case .parentTalks: ParentTalksView()
            case .documents: DocumentsView()
            case .allday: AlldayView()
            case .elections: ElectionsView()
            case .invoices: InvoicesView()
            }
        }
        .navigationDestination(for: Letter.self) { LetterDetailView(letter: $0) }
        #if DEBUG
        // Für Screenshots im Simulator: `-openPage grades`
        .navigationDestination(isPresented: Binding(get: { debugPage != nil }, set: { if !$0 { debugPage = nil } })) {
            switch debugPage {
            case "grades": GradesView()
            case "absences": AbsencesView()
            case "documents": DocumentsView()
            case "elections": ElectionsView()
            case "parenttalks": ParentTalksView()
            case "letter": if let letter = model.letters.first(where: { $0.id == "l1" }) { LetterDetailView(letter: letter) }
            case "tiles": TilesView()
            default: EmptyView()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            debugPage = UserDefaults.standard.string(forKey: "openPage")
        }
        #endif
    }

    private var nextExam: Exam? { model.snapshot?.exams.first { $0.date >= SchoolCalendar.today } }

    private var nextExamLabel: String {
        guard let exam = nextExam else { return "keine" }
        return SchoolCalendar.relativeLabel(exam.date)
    }

    private func tile(_ page: SchoolPage, icon: String, color: Color, title: String, value: String,
                      detail: String?, highlighted: Bool = false) -> some View {
        NavigationLink(value: page) {
            cardContent(icon: icon, color: color, title: title, value: value, detail: detail, highlighted: highlighted)
        }
        .buttonStyle(.plain)
    }

    private func cardContent(icon: String, color: Color, title: String, value: String, detail: String?,
                             highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(14)
        .contentShape(.rect)
        .glassCard(tint: highlighted ? color : nil, cornerRadius: 24, interactive: true)
    }
}

// MARK: - Module

struct ModulesSection: View {
    @Environment(AppModel.self) private var model

    /// Module, die die App abbildet. Namen wie in `main/get-active-modules`.
    private static let supported: [String: String] = [
        "schedules": "Stundenplan", "classbook": "Klassenbuch / Hausaufgaben", "exams": "Leistungsnachweise",
        "messenger": "Nachrichten", "letters": "Elternbriefe", "calendar": "Termine", "dashboard": "Pinnwand",
        "grades": "Noten", "sick": "Krankmeldung", "exemptions": "Beurlaubung", "parenttalks": "Elternsprechtag",
        "documents": "Dokumente", "allday": "Ganztag", "electives": "Wahlen", "invoicing": "Rechnungen",
        "invoices": "Rechnungen", "payments": "Zahlungen", "absences": "Fehlzeiten",
    ]
    private static let known: [String: String] = [
        "grades": "Noten", "sick": "Krankmeldung", "exemptions": "Beurlaubung", "parenttalks": "Elternsprechtag",
        "documents": "Dokumente", "electives": "Wahlen", "allday": "Ganztag", "invoices": "Zahlungen",
        "payments": "Zahlungen", "meals": "Speiseplan", "mealplan": "Speiseplan", "lending": "Ausleihe",
        "absences": "Fehlzeiten", "surveys": "Umfragen", "consultations": "Sprechstunden", "learning": "Lernplattform",
    ]

    var body: some View {
        if let modules = model.snapshot?.modules, !modules.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Module deiner Schule", trailing: "\(modules.count)")
                VStack(spacing: 0) {
                    ForEach(sorted(modules)) { module in
                        let inApp = Self.supported[module.name] != nil
                        HStack {
                            Image(systemName: inApp ? "checkmark.circle.fill" : "safari")
                                .foregroundStyle(inApp ? Color.green : .secondary)
                                .frame(width: 24)
                            Text(label(for: module))
                            Spacer()
                            Text(inApp ? "In der App" : "Nur im Web")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        if module.id != sorted(modules).last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .glassCard(cornerRadius: 20)
                Text("„Nur im Web“ heißt: Infos aus diesem Bereich bekommst du noch nicht per Mitteilung. Sag Bescheid, dann baue ich es ein.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 8)
        }
    }

    private func label(for module: SchoolModule) -> String {
        if module.label != module.name { return module.label }
        return Self.supported[module.name] ?? Self.known[module.name] ?? module.name
    }

    private func sorted(_ modules: [SchoolModule]) -> [SchoolModule] {
        modules.sorted {
            let a = Self.supported[$0.name] == nil ? 1 : 0, b = Self.supported[$1.name] == nil ? 1 : 0
            return (a, label(for: $0)) < (b, label(for: $1))
        }
    }
}

// MARK: - Elternbriefe

struct LettersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Elternbriefe", subtitle: model.openLetters > 0 ? "\(model.openLetters) unbestätigt" : nil, showsSettings: false) {
            LazyVStack(spacing: 10) {
                if model.letters.isEmpty {
                    EmptyStateCard(icon: "envelope.open", title: model.snapshot?.failedModules.contains("Elternbriefe") == true
                                   ? "Elternbriefe nicht verfügbar" : "Keine Elternbriefe")
                }
                ForEach(model.letters) { letter in
                    NavigationLink(value: letter) { LetterRow(letter: letter) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LetterRow: View {
    let letter: Letter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: letter.needsAction ? "envelope.badge.fill" : "envelope.open")
                .font(.title3)
                .foregroundStyle(letter.needsAction ? Color.orange : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.title)
                    .font(.subheadline.weight(letter.needsAction ? .bold : .semibold))
                    .multilineTextAlignment(.leading)
                Text([letter.sender, letter.sentDate.map { MessageTime.short($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if letter.needsAction {
                    Label(deadlineText ?? "Bestätigung ausstehend", systemImage: "hand.raised.fill")
                        .labelStyle(CompactLabelStyle())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(.rect)
        .glassCard(tint: letter.needsAction ? .orange : nil, cornerRadius: 20, interactive: true)
    }

    private var deadlineText: String? {
        letter.answerDeadline.flatMap(ISODate.parseFlexible).map { "Rückmeldung bis \(SchoolCalendar.dayMonth(SchoolCalendar.iso($0)))" }
    }
}

struct LetterDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let letter: Letter

    @State private var detail: LetterDetail?
    @State private var error: String?
    @State private var isConfirming = false

    /// Aktueller Stand aus dem Modell (z. B. nach Bestätigung).
    private var current: Letter { model.letters.first { $0.id == letter.id } ?? letter }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.title).font(.title2.bold())
                    Text([current.sender, current.sentDate.map {
                        $0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
                    }].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if current.needsAction { confirmCard }

                Group {
                    if let detail {
                        VStack(alignment: .leading, spacing: 12) {
                            if detail.text.isEmpty {
                                Text("Kein Text.").foregroundStyle(.secondary)
                            } else {
                                RichText(html: detail.html.isEmpty ? detail.text : detail.html)
                            }
                            ForEach(detail.attachments) { AttachmentButton(file: $0) }
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .glassCard()

                if detail?.attachments.isEmpty == false || error != nil {
                    openInBrowser
                }
            }
            .padding(16)
        }
        .background { AppBackground() }
        .navigationTitle("Elternbrief")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await LettersAPI.detail(for: letter) } catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if current.questionCount > 0 {
                Label("Dieser Brief enthält \(current.questionCount) Frage\(current.questionCount == 1 ? "" : "n"). Beantworte sie bitte im Browser.",
                      systemImage: "questionmark.bubble.fill")
                    .font(.subheadline)
                openInBrowser
            } else {
                Text("Die Schule bittet um Kenntnisnahme.").font(.subheadline)
                Button {
                    Task {
                        isConfirming = true
                        defer { isConfirming = false }
                        do { try await model.confirm(current) } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Group {
                        if isConfirming { ProgressView() } else { Label("Gelesen bestätigen", systemImage: "checkmark.seal.fill") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .controlSize(.large)
            }
        }
        .padding(16)
        .glassCard(tint: .orange)
    }

    private var openInBrowser: some View {
        Button {
            if let url = URL(string: "https://login.schulmanager-online.de/#/modules/letters/view") { openURL(url) }
        } label: {
            Label("Im Browser öffnen", systemImage: "safari")
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Pinnwand

struct TilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Pinnwand", showsSettings: false) {
            LazyVStack(spacing: 12) {
                if model.tiles.isEmpty {
                    EmptyStateCard(icon: "pin", title: "Keine Aushänge")
                }
                ForEach(model.tiles) { tile in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(tile.title).font(.headline)
                            Spacer()
                            if tile.pinned { Image(systemName: "pin.fill").foregroundStyle(.pink) }
                        }
                        RichText(html: tile.html ?? tile.content, font: .subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(tint: tile.pinned ? .pink : nil)
                }
            }
        }
    }
}

// MARK: - Termine

struct EventsView: View {
    @Environment(AppModel.self) private var model
    @State private var showHolidays = true

    private var grouped: [(month: String, events: [SchoolEvent])] {
        let events = model.upcomingEvents.filter { showHolidays || !$0.isHoliday }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        let groups = Dictionary(grouping: events) { String($0.day.prefix(7)) }
        return groups.keys.sorted().map { key in
            let title = SchoolCalendar.date(key + "-01").map(formatter.string) ?? key
            return (title, groups[key] ?? [])
        }
    }

    var body: some View {
        Screen(title: "Termine", showsSettings: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                Toggle("Ferien & Feiertage", isOn: $showHolidays.animation())
                    .font(.subheadline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                if grouped.isEmpty {
                    EmptyStateCard(icon: "calendar", title: "Keine Termine")
                }
                ForEach(grouped, id: \.month) { group in
                    SectionHeader(title: group.month)
                    ForEach(group.events) { EventRow(event: $0) }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: SchoolEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(SchoolCalendar.shortWeekday(event.day)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(SchoolCalendar.dayNumber(event.day)).font(.title2.bold().monospacedDigit())
            }
            .frame(width: 44)
            .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                if let details = event.details, !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(tint: event.isHoliday ? .green : nil, cornerRadius: 18)
    }

    private var color: Color { event.isHoliday ? .green : (event.colorHex.flatMap(Color.init(hex:)) ?? .red) }

    private var subtitle: String {
        var parts: [String] = []
        if event.lastDay != event.day {
            parts.append("bis \(SchoolCalendar.shortWeekday(event.lastDay)) \(SchoolCalendar.dayMonth(event.lastDay))")
        }
        parts.append(event.timeLabel ?? "ganztägig")
        if let location = event.location { parts.append(location) }
        if let category = event.category { parts.append(category) }
        return parts.joined(separator: " · ")
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255, green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }
}

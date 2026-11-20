import QuickLook
import SwiftUI

private let german = Locale(identifier: "de_DE")

private func dateLabel(_ iso: String?) -> String? {
    guard let iso, let date = ISODate.parseFlexible(iso) else { return nil }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(german))
}

private func dateTimeLabel(_ iso: String?) -> String? {
    guard let iso, let date = ISODate.parseFlexible(iso) else { return nil }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(german))
}

// MARK: - Anhänge

/// Lädt einen Anhang, entschlüsselt ihn und zeigt ihn in der Vorschau (Teilen/Sichern inklusive).
struct AttachmentButton: View {
    let file: StoredFile
    var onDark = false

    @State private var isLoading = false
    @State private var previewURL: URL?
    @State private var error: String?

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            HStack(spacing: 6) {
                if isLoading { ProgressView().controlSize(.small) } else { Image(systemName: icon) }
                Text(file.name).lineLimit(1)
                if error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(onDark ? Color.white : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onChange(of: previewURL) { _, url in
            guard let url else { return }
            DocumentPreview.present(url) { previewURL = nil }
        }
        .alert("Anhang", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var icon: String {
        switch (file.name as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif": "photo"
        case "doc", "docx", "odt", "txt": "doc.text"
        case "xls", "xlsx", "ods", "csv": "tablecells"
        default: "paperclip"
        }
    }

    private func open() async {
        isLoading = true
        defer { isLoading = false }
        do {
            previewURL = try await FileDownloader.download(file)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Zeigt Dokumente in einer eigenen, vollflächigen QuickLook-Vorschau mit deckendem Hintergrund.
/// SwiftUIs `.quickLookPreview` präsentiert transparent, sodass der Farbverlauf der App durchscheint.
@MainActor
private final class DocumentPreview: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private static var current: DocumentPreview?

    private let url: URL
    private let onDismiss: () -> Void

    private init(url: URL, onDismiss: @escaping () -> Void) {
        self.url = url
        self.onDismiss = onDismiss
    }

    static func present(_ url: URL, onDismiss: @escaping () -> Void) {
        guard let presenter = topViewController() else { onDismiss(); return }
        let preview = DocumentPreview(url: url, onDismiss: onDismiss)
        current = preview

        let controller = QLPreviewController()
        controller.dataSource = preview
        controller.delegate = preview
        controller.modalPresentationStyle = .fullScreen
        controller.view.backgroundColor = .systemBackground
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        MainActor.assumeIsolated { url as NSURL }
    }

    nonisolated func previewControllerDidDismiss(_ controller: QLPreviewController) {
        MainActor.assumeIsolated {
            onDismiss()
            if Self.current === self { Self.current = nil }
        }
    }
}

// MARK: - Noten

struct GradesView: View {
    @Environment(AppModel.self) private var model

    private var subjects: [GradeSubject] { model.snapshot?.grades ?? [] }

    var body: some View {
        Screen(title: "Noten", subtitle: overallLabel, showsSettings: false) {
            LazyVStack(spacing: 10) {
                if subjects.isEmpty {
                    EmptyStateCard(icon: "star", title: "Keine Noten",
                                   message: "Entweder gibt es noch keine Noten oder die Schule gibt sie für Eltern nicht frei.")
                }
                ForEach(subjects) { subject in
                    NavigationLink(value: subject) { GradeSubjectRow(subject: subject) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: GradeSubject.self) { GradeDetailView(subject: $0) }
    }

    private var overallLabel: String? {
        let averages = subjects.compactMap(\.average)
        guard !averages.isEmpty, subjects.allSatisfy({ $0.system == subjects.first?.system }) else { return nil }
        let mean = averages.reduce(0, +) / Double(averages.count)
        return "Ø aller Fächer " + mean.formatted(.number.precision(.fractionLength(2)).locale(german))
    }
}

struct GradeSubjectRow: View {
    let subject: GradeSubject

    var body: some View {
        HStack(spacing: 14) {
            Text(subject.average.map { $0.formatted(.number.precision(.fractionLength(subject.system == 1 ? 1 : 2)).locale(german)) } ?? "–")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(gradeColor(subject.average, system: subject.system))
                .frame(width: 64, height: 48)
                .glassEffect(.regular.tint(gradeColor(subject.average, system: subject.system).opacity(0.2)), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.subject).font(.headline)
                Text(subject.grades.prefix(8).map(\.value).joined(separator: "  "))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let final = subject.finalGrade {
                VStack(spacing: 0) {
                    Text(final).font(.headline)
                    Text("Zeugnis").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .contentShape(.rect)
        .glassCard(cornerRadius: 20, interactive: true)
    }
}

func gradeColor(_ value: Double?, system: Int) -> Color {
    guard let value else { return .secondary }
    let normalized = system == 1 ? (17 - value) / 3 : value // Punkte grob auf Notenskala
    switch normalized {
    case ..<2.5: return .green
    case ..<3.5: return .teal
    case ..<4.5: return .orange
    default: return .red
    }
}

struct GradeDetailView: View {
    let subject: GradeSubject

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(subject.grades) { grade in
                    HStack(spacing: 14) {
                        Text(grade.value)
                            .font(.title3.bold())
                            .foregroundStyle(gradeColor(grade.numeric, system: subject.system))
                            .frame(width: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(grade.type ?? "Note").font(.subheadline.weight(.semibold))
                            Text([dateLabel(grade.date), grade.weight != 1 ? "Gewicht \(grade.weight.formatted(.number.locale(german)))" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if let comment = grade.comment {
                                Text(comment).font(.caption).foregroundStyle(.secondary).italic()
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 18)
                }
            }
            .padding(16)
        }
        .background { AppBackground() }
        .navigationTitle(subject.subject)
        .navigationSubtitle(subject.average.map { "Ø " + $0.formatted(.number.precision(.fractionLength(2)).locale(german)) } ?? "")
    }
}

// MARK: - Fehlzeiten & Krankmeldung

struct AbsencesView: View {
    @Environment(AppModel.self) private var model
    @State private var showSickNote = false

    private var absences: [Absence] { model.snapshot?.absences ?? [] }

    var body: some View {
        Screen(title: "Fehlzeiten", subtitle: summary, showsSettings: false) {
            LazyVStack(spacing: 10) {
                Button {
                    showSickNote = true
                } label: {
                    Label("Kind krankmelden", systemImage: "cross.case.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .controlSize(.large)

                if absences.isEmpty {
                    EmptyStateCard(icon: "checkmark.circle", title: "Keine Fehlzeiten")
                }
                ForEach(absences) { absence in
                    HStack(spacing: 12) {
                        Image(systemName: absence.excused ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(absence.excused ? Color.green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateLabel(absence.date) ?? absence.date).font(.subheadline.weight(.semibold))
                            Text([absence.from.map { "\($0)–\(absence.until ?? "")" } ?? "ganztägig", absence.reason]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(absence.excused ? "entschuldigt" : "offen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(absence.excused ? Color.secondary : Color.orange)
                    }
                    .padding(12)
                    .glassCard(tint: absence.excused ? nil : .orange, cornerRadius: 18)
                }
            }
        }
        .sheet(isPresented: $showSickNote) { SickNoteForm() }
    }

    private var summary: String? {
        guard !absences.isEmpty else { return nil }
        let open = absences.filter { !$0.excused }.count
        return "\(absences.count) Einträge" + (open > 0 ? " · \(open) unentschuldigt" : "")
    }
}

struct SickNoteForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var partial = false
    @State private var startTime = Date.now
    @State private var comment = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if let student = model.selectedStudent {
                    Section { LabeledContent("Kind", value: student.displayName) }
                }
                Section {
                    DatePicker("Von", selection: $start, displayedComponents: .date)
                    DatePicker("Bis", selection: $end, in: start..., displayedComponents: .date)
                    Toggle("Erst ab einer Uhrzeit (z. B. mittags abgeholt)", isOn: $partial)
                    if partial { DatePicker("Ab", selection: $startTime, displayedComponents: .hourAndMinute) }
                }
                Section("Hinweis an die Schule (optional)") {
                    TextField("z. B. Fieber", text: $comment, axis: .vertical).lineLimit(2...5)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Krankmeldung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden", systemImage: "paperplane.fill") { Task { await send() } }
                        .disabled(isSending)
                }
            }
            .alert("Krankmeldung gesendet", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Die Schule hat die Krankmeldung erhalten.")
            }
        }
        .presentationDetents([.large])
        .onChange(of: start) { _, value in if end < value { end = value } }
    }

    private func send() async {
        guard let student = model.selectedStudent else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await ModulesAPI.sendSickNote(
                studentId: student.id, start: SchoolCalendar.iso(start), end: SchoolCalendar.iso(end),
                startTime: partial ? startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : nil,
                comment: comment
            )
            sent = true
            Task { await model.refresh() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Beurlaubung

struct ExemptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var showForm = false

    private var exemptions: [Exemption] { model.snapshot?.exemptions ?? [] }

    var body: some View {
        Screen(title: "Beurlaubung", showsSettings: false) {
            LazyVStack(spacing: 10) {
                Button {
                    showForm = true
                } label: {
                    Label("Beurlaubung beantragen", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                if exemptions.isEmpty {
                    EmptyStateCard(icon: "calendar.badge.checkmark", title: "Keine Anträge")
                }
                ForEach(exemptions) { exemption in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(dateLabel(exemption.startDate) ?? "") – \(dateLabel(exemption.endDate) ?? "")")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            StateBadge(text: status(exemption).text, icon: status(exemption).icon, color: status(exemption).color)
                        }
                        if let comment = exemption.comment { Text(comment).font(.footnote).foregroundStyle(.secondary) }
                        if let feedback = exemption.feedback {
                            Text("Schule: \(feedback)").font(.footnote.weight(.medium))
                        }
                    }
                    .padding(14)
                    .glassCard(tint: status(exemption).color, cornerRadius: 20)
                }
            }
        }
        .sheet(isPresented: $showForm) { ExemptionForm() }
    }

    private func status(_ exemption: Exemption) -> (text: String, icon: String, color: Color) {
        switch exemption.granted {
        case true?: ("Genehmigt", "checkmark.seal.fill", .green)
        case false?: ("Abgelehnt", "xmark.seal.fill", .red)
        case nil: ("Offen", "hourglass", .orange)
        }
    }
}

struct ExemptionForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var withTimes = false
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var reason = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Von", selection: $start, displayedComponents: .date)
                    DatePicker("Bis", selection: $end, in: start..., displayedComponents: .date)
                    Toggle("Nur einzelne Stunden", isOn: $withTimes)
                    if withTimes {
                        DatePicker("Ab", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("Bis", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Begründung (Pflicht)") {
                    TextField("z. B. Familienfeier, Arzttermin", text: $reason, axis: .vertical).lineLimit(2...6)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Beurlaubung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden", systemImage: "paperplane.fill") { Task { await send() } }
                        .disabled(isSending || reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Antrag gesendet", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Du bekommst eine Mitteilung, sobald die Schule entschieden hat.")
            }
        }
        .onChange(of: start) { _, value in if end < value { end = value } }
    }

    private func send() async {
        guard let student = model.selectedStudent else { return }
        let time = { (date: Date) in date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        isSending = true
        defer { isSending = false }
        do {
            try await ModulesAPI.requestExemption(
                studentId: student.id, start: SchoolCalendar.iso(start), end: SchoolCalendar.iso(end),
                startTime: withTimes ? time(startTime) : nil, endTime: withTimes ? time(endTime) : nil,
                comment: reason
            )
            sent = true
            Task { await model.refresh() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Elternsprechtag

struct ParentTalksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var rounds: [ParentTalkRound] { model.snapshot?.parentTalks ?? [] }

    var body: some View {
        Screen(title: "Elternsprechtag", showsSettings: false) {
            LazyVStack(spacing: 12) {
                if rounds.isEmpty {
                    EmptyStateCard(icon: "person.2", title: "Kein Elternsprechtag geplant")
                }
                ForEach(rounds) { round in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(round.label).font(.headline)
                            Spacer()
                            if round.isOpenForBooking {
                                StateBadge(text: "Anmeldung offen", icon: "checkmark.circle.fill", color: .green)
                            }
                        }
                        if let start = dateTimeLabel(round.start) {
                            Label(start + (round.end.flatMap { ISODate.parseFlexible($0) }.map {
                                "–" + $0.formatted(.dateTime.hour().minute().locale(german))
                            } ?? ""), systemImage: "calendar")
                            .font(.subheadline)
                        }
                        if let until = dateTimeLabel(round.inscriptionEnd) {
                            Label("Anmeldung bis \(until)", systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary)
                        }
                        let booked = round.appointments.filter { !$0.cancelled }
                        if !booked.isEmpty {
                            Divider()
                            Text("Deine Termine").font(.subheadline.weight(.semibold))
                            ForEach(booked) { appointment in
                                Label("\(dateTimeLabel(appointment.start) ?? "") · \(appointment.teacher ?? "Lehrkraft")",
                                      systemImage: "person.fill")
                                    .font(.subheadline)
                            }
                        }
                        if round.isOpenForBooking {
                            Button {
                                if let url = URL(string: "https://login.schulmanager-online.de/#/modules/parenttalks") { openURL(url) }
                            } label: {
                                Label("Termine buchen", systemImage: "safari")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(16)
                    .glassCard(tint: round.isOpenForBooking ? .green : nil)
                }
                Text("Das Buchen läuft noch über den Browser: Die Lehrerliste für freie Termine ist in der Schnittstelle nicht dokumentiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dokumente

struct DocumentsView: View {
    var folder: DocumentFolder?

    @State private var current: DocumentFolder?
    @State private var folders: [DocumentFolder] = []
    @State private var documents: [SchoolDocument] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var textDocument: SchoolDocument?

    var body: some View {
        Screen(title: current?.name ?? folder?.name ?? "Dokumente", showsSettings: false) {
            LazyVStack(spacing: 8) {
                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if let error {
                    EmptyStateCard(icon: "folder.badge.questionmark", title: "Dokumente nicht verfügbar", message: error)
                } else if folders.isEmpty, documents.isEmpty {
                    EmptyStateCard(icon: "folder", title: "Leerer Ordner")
                }
                ForEach(folders) { sub in
                    NavigationLink(value: sub) {
                        row(icon: "folder.fill", color: .blue, title: sub.name, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(documents) { document in
                    if let file = document.file {
                        HStack {
                            AttachmentButton(file: StoredFile(name: document.name.contains(".") ? document.name : file.name,
                                                              descriptor: file.descriptor))
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 18)
                    } else {
                        Button { textDocument = document } label: {
                            row(icon: "doc.plaintext", color: .secondary, title: document.name, chevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: DocumentFolder.self) { DocumentsView(folder: $0) }
        .sheet(item: $textDocument) { document in
            NavigationStack {
                ScrollView { Text(document.htmlText ?? "").padding().textSelection(.enabled) }
                    .navigationTitle(document.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
    }

    private func row(icon: String, color: Color, title: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
            Spacer()
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(14)
        .contentShape(.rect)
        .glassCard(cornerRadius: 18, interactive: true)
    }

    private func load() async {
        guard folders.isEmpty, documents.isEmpty else { return }
        do {
            let target: DocumentFolder?
            if let folder { target = folder } else { target = try await ModulesAPI.documentRoot() }
            guard let target else { isLoading = false; return }
            current = target
            let contents = try await ModulesAPI.folder(target)
            folders = contents.folders
            documents = contents.documents
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Ganztag

struct AlldayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Ganztag", showsSettings: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                let offers = model.snapshot?.alldayOffers ?? []
                let notes = model.snapshot?.alldayNotes ?? []
                if offers.isEmpty, notes.isEmpty {
                    EmptyStateCard(icon: "figure.and.child.holdinghands", title: "Keine Ganztagsangebote")
                }
                if !notes.isEmpty {
                    SectionHeader(title: "Mitteilungen")
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = dateLabel(note.date) { Text(date).font(.caption).foregroundStyle(.secondary) }
                            Text(note.message).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(tint: .teal, cornerRadius: 18)
                    }
                }
                if !offers.isEmpty {
                    SectionHeader(title: "Angebote")
                    ForEach(offers) { offer in
                        HStack {
                            Text(offer.weekday.map { ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][$0 % 7] } ?? "–")
                                .font(.headline).frame(width: 36)
                            VStack(alignment: .leading) {
                                Text(offer.name).font(.subheadline.weight(.semibold))
                                if let start = offer.startTime {
                                    Text("\(start)–\(offer.endTime ?? "")").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 18)
                    }
                }
            }
        }
    }
}

// MARK: - Rechnungen

struct InvoicesView: View {
    @Environment(AppModel.self) private var model

    private var invoices: [Invoice] { model.snapshot?.invoices ?? [] }

    var body: some View {
        Screen(title: "Rechnungen", subtitle: openLabel, showsSettings: false) {
            LazyVStack(spacing: 10) {
                if invoices.isEmpty {
                    EmptyStateCard(icon: "eurosign.circle", title: "Keine Rechnungen")
                }
                ForEach(invoices) { invoice in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(invoice.number.map { "Rechnung \($0)" } ?? "Rechnung").font(.headline)
                            Spacer()
                            Text(euro(invoice.sum)).font(.headline.monospacedDigit())
                        }
                        Text([dateLabel(invoice.date), invoice.dueDate.flatMap(dateLabel).map { "fällig \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(invoice.items, id: \.self) { Text($0).font(.footnote) }
                        StateBadge(text: invoice.paid ? "Bezahlt" : "Offen",
                                   icon: invoice.paid ? "checkmark.circle.fill" : "clock.fill",
                                   color: invoice.paid ? .green : .orange)
                    }
                    .padding(14)
                    .glassCard(tint: invoice.paid ? nil : .orange, cornerRadius: 20)
                }
            }
        }
    }

    private var openLabel: String? {
        let open = invoices.filter { !$0.paid }.compactMap { ($0.sum ?? 0) - ($0.paidSum ?? 0) }.reduce(0, +)
        return open > 0 ? "Offen: \(euro(open))" : nil
    }

    private func euro(_ value: Double?) -> String {
        value.map { $0.formatted(.currency(code: "EUR").locale(german)) } ?? "–"
    }
}

// MARK: - Wahlen

struct ElectionsView: View {
    @State private var elections: [Election] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Screen(title: "Wahlen", showsSettings: false) {
            LazyVStack(spacing: 10) {
                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if let error {
                    EmptyStateCard(icon: "checklist", title: "Wahlen nicht verfügbar", message: error)
                } else if elections.isEmpty {
                    EmptyStateCard(icon: "checklist", title: "Keine Wahlen")
                }
                ForEach(elections) { election in
                    NavigationLink(value: election) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(election.name).font(.headline)
                                Text(election.end.flatMap(dateLabel).map { "bis \($0)" } ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StateBadge(text: election.isOpen ? "Offen" : "Beendet",
                                       icon: election.isOpen ? "pencil" : "lock.fill",
                                       color: election.isOpen ? .green : .secondary)
                        }
                        .padding(14)
                        .contentShape(.rect)
                        .glassCard(cornerRadius: 20, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: Election.self) { ElectionRankingView(election: $0) }
        .task {
            do { elections = try await ModulesAPI.elections() } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

struct ElectionRankingView: View {
    @Environment(AppModel.self) private var model
    let election: Election
    @State private var ranked: [Elective] = []
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        List {
            if let description = election.description {
                Section { Text(description).font(.subheadline) }
            }
            Section {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, elective in
                    HStack {
                        Text("\(index + 1).").font(.headline.monospacedDigit()).frame(width: 30)
                        Text(elective.name)
                        if let limit = election.priorities, index >= limit {
                            Spacer()
                            Text("zählt nicht").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { ranked.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Reihenfolge = Priorität")
            } footer: {
                Text(election.isOpen ? "Zum Sortieren gedrückt halten und ziehen." : "Diese Wahl ist abgeschlossen.")
            }
            if let message { Section { Text(message) } }
        }
        .environment(\.editMode, .constant(election.isOpen ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle(election.name)
        .toolbar {
            if election.isOpen {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", systemImage: "checkmark") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .onAppear { if ranked.isEmpty { ranked = election.electives } }
    }

    private func save() async {
        guard let student = model.selectedStudent else { return }
        isSaving = true
        defer { isSaving = false }
        let limit = election.priorities ?? ranked.count
        do {
            try await ModulesAPI.savePriorities(election, ranked: Array(ranked.prefix(limit)), studentId: student.id)
            message = "Gespeichert."
        } catch {
            message = error.localizedDescription
        }
    }
}

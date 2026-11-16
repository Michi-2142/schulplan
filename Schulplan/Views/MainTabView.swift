import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Heute", systemImage: "sun.max.fill", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Woche", systemImage: "calendar", value: AppTab.week) {
                NavigationStack { WeekView() }
            }
            Tab("Neues", systemImage: "bell.badge.fill", value: AppTab.changes) {
                NavigationStack { ChangesView() }
            }
            .badge(model.upcomingChanges.count + model.openLetters)
            Tab("Nachrichten", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.messages) {
                NavigationStack { MessagesView() }
            }
            .badge(model.unreadMessages)
            Tab("Schule", systemImage: "building.columns.fill", value: AppTab.school) {
                NavigationStack { SchoolView() }
            }
            .badge(model.openLetters + model.openHomeworkCount)
        }
        // Tab-Leiste bleibt immer sichtbar.
        .tabBarMinimizeBehavior(.never)
    }
}

/// Stand der Daten oben neben dem Kind. Antippen zeigt Details und aktualisiert.
struct SyncStatusButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if let fetched = model.snapshot?.fetchedAt {
                Text("Zuletzt aktualisiert \(fetched.formatted(.dateTime.weekday().hour().minute().locale(Locale(identifier: "de_DE"))))")
            }
            if let error = model.errorMessage {
                Text(error)
            }
            Button("Jetzt aktualisieren", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .disabled(model.isRefreshing)
        } label: {
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                HStack(spacing: 5) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: model.errorMessage == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                            .foregroundStyle(model.errorMessage == nil ? Color.green : Color.orange)
                    }
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }
        }
        .accessibilityLabel("Aktualisierungsstatus")
    }

    private var label: String {
        if model.isRefreshing { return "Lädt …" }
        if model.errorMessage != nil { return "Fehler" }
        guard let fetched = model.snapshot?.fetchedAt else { return "–" }
        if Date.now.timeIntervalSince(fetched) < 60 { return "gerade eben" }
        return fetched.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(Locale(identifier: "de_DE")))
    }
}

/// Gemeinsamer Rahmen für alle Tabs: Hintergrund, Titel, Pull-to-Refresh. Liegt in einem NavigationStack.
struct Screen<Content: View>: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    let title: String
    var subtitle: String?
    var showsSettings = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .refreshable { await model.refresh() }
        .navigationTitle(title)
        .navigationSubtitle(fullSubtitle)
        .toolbar {
            if showsSettings {
                ToolbarItem(placement: .topBarLeading) {
                    StudentSwitcher(showSettings: $showSettings)
                }
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusButton()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig", systemImage: "checkmark") { showSettings = false }
                        }
                    }
            }
        }
    }
}

extension Screen {
    /// Bei mehreren Kindern steht das Kind immer mit im Untertitel: „Mia · Dienstag, 17.11.“
    fileprivate var fullSubtitle: String {
        guard showsSettings, model.hasSeveralStudents, let name = model.selectedStudent?.firstname else { return subtitle ?? "" }
        guard let subtitle, !subtitle.isEmpty else { return name }
        return "\(name) · \(subtitle)"
    }
}

/// Kind-Auswahl oben links in jedem Tab: zeigt, für wen die Daten gerade gelten, und öffnet die Einstellungen.
struct StudentSwitcher: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    private var othersNeedAttention: Bool {
        model.students.contains { $0.id != model.selectedStudent?.id && model.attentionCount(for: $0) > 0 }
    }

    var body: some View {
        Menu {
            if model.hasSeveralStudents {
                Section("Anzeigen für") {
                    ForEach(model.students) { student in
                        Button {
                            Task { await model.selectStudent(student.id) }
                        } label: {
                            let count = model.attentionCount(for: student)
                            Label {
                                Text(student.displayName)
                                Text([student.className.map { "Klasse \($0)" }, count > 0 ? "\(count) neu" : nil]
                                    .compactMap { $0 }.joined(separator: " · "))
                            } icon: {
                                Image(systemName: student.id == model.selectedStudent?.id ? "checkmark.circle.fill" : "person.crop.circle")
                            }
                        }
                    }
                }
            }
            Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
        } label: {
            if let student = model.selectedStudent {
                HStack(spacing: 6) {
                    StudentAvatar(student: student, size: 26)
                        .overlay(alignment: .topTrailing) {
                            if othersNeedAttention {
                                Circle().fill(.red).stroke(.white, lineWidth: 1.5).frame(width: 10, height: 10).offset(x: 3, y: -3)
                            }
                        }
                    Text(student.firstname.isEmpty ? student.displayName : student.firstname)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if model.hasSeveralStudents {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 4)
            } else {
                Image(systemName: "gearshape")
            }
        }
        .accessibilityLabel("Kind wechseln und Einstellungen")
    }
}

/// Farbiger Kreis mit Initiale – jedes Kind behält seine Farbe überall in der App.
struct StudentAvatar: View {
    @Environment(AppModel.self) private var model
    let student: Student
    var size: CGFloat = 28

    var body: some View {
        Text(String(student.firstname.prefix(1)).uppercased())
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(StudentColor.color(for: student, in: model.students).gradient, in: .circle)
    }
}

enum StudentColor {
    /// Nach Reihenfolge vergeben, damit Geschwister klar unterscheidbare Farben haben.
    private static let palette: [Color] = [.indigo, .orange, .teal, .pink, .green, .purple]

    static func color(for student: Student, in students: [Student]) -> Color {
        palette[(students.firstIndex { $0.id == student.id } ?? 0) % palette.count]
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .glassCard()
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

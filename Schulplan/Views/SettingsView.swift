import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage("notifySchedule") private var notifySchedule = true
    @AppStorage("notifyExams") private var notifyExams = true
    @AppStorage("notifyHomework") private var notifyHomework = false
    @AppStorage("notifyMessages") private var notifyMessages = true
    @AppStorage("notifyLetters") private var notifyLetters = true
    @AppStorage("notifyTiles") private var notifyTiles = true
    @AppStorage("notifyEvents") private var notifyEvents = true
    @AppStorage("notifyGrades") private var notifyGrades = true
    @AppStorage("notifyAdministration") private var notifyAdministration = true
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var backgroundStatus: UIBackgroundRefreshStatus = .available
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section("Konto") {
                if model.students.count > 1 {
                    Picker("Kind", selection: Binding(
                        get: { model.selectedStudentId ?? "" },
                        set: { id in Task { await model.selectStudent(id) } }
                    )) {
                        ForEach(model.students) { Text($0.displayName).tag($0.id) }
                    }
                } else if let student = model.selectedStudent {
                    LabeledContent("Schüler:in", value: student.displayName)
                }
                if let className = model.selectedStudent?.className {
                    LabeledContent("Klasse", value: className)
                }
                if model.isDemo {
                    Label("Demo-Modus: Jede Aktualisierung ändert eine zufällige Stunde.", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if authorization == .denied {
                    Button("Mitteilungen in den Einstellungen erlauben", systemImage: "bell.slash.fill") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .foregroundStyle(.red)
                }
                Toggle("Stundenplan-Änderungen", systemImage: "calendar.badge.exclamationmark", isOn: $notifySchedule)
                Toggle("Neue Nachrichten", systemImage: "bubble.left.and.bubble.right", isOn: $notifyMessages)
                Toggle("Elternbriefe", systemImage: "envelope", isOn: $notifyLetters)
                Toggle("Pinnwand", systemImage: "pin", isOn: $notifyTiles)
                Toggle("Neue & geänderte Termine", systemImage: "calendar", isOn: $notifyEvents)
                Toggle("Neue Noten", systemImage: "star", isOn: $notifyGrades)
                Toggle("Fehlzeiten, Beurlaubung, Rechnungen, Ganztag, Elternsprechtag", systemImage: "tray.full", isOn: $notifyAdministration)
                Toggle("Neue Arbeiten", systemImage: "doc.text", isOn: $notifyExams)
                Toggle("Neue Hausaufgaben", systemImage: "book.closed", isOn: $notifyHomework)
                Button("Testmitteilung senden", systemImage: "paperplane") {
                    Task {
                        if await NotificationManager.requestAuthorization() { await NotificationManager.sendTest() }
                        await loadStatus()
                    }
                }
            } header: {
                Text("Mitteilungen")
            } footer: {
                Text("Ausfälle und Vertretungen für heute und morgen sowie neue Elternbriefe sind als zeitkritisch markiert.")
            }

            Section {
                LabeledContent("Hintergrundaktualisierung", value: backgroundLabel)
                if let fetched = model.snapshot?.fetchedAt {
                    LabeledContent("Letzter Abruf") { Text(fetched, format: .dateTime.weekday().hour().minute()) }
                }
                if let background = SessionStore.shared.lastBackgroundRun {
                    LabeledContent("Letzter Hintergrundlauf") { Text(background, format: .relative(presentation: .named)) }
                }
                if let failed = model.snapshot?.failedModules, !failed.isEmpty {
                    LabeledContent("Nicht verfügbar", value: failed.joined(separator: ", "))
                }
            } header: {
                Text("Aktualisierung")
            } footer: {
                Text("iOS entscheidet selbst, wie oft die App im Hintergrund prüfen darf (meist alle 15–60 Minuten, öfter, wenn du die App regelmäßig öffnest). Hintergrundaktualisierung und Stromsparmodus beeinflussen das. Schließe die App nicht aus dem App-Umschalter, sonst prüft iOS nicht mehr im Hintergrund.")
            }

            Section {
                Button(model.isDemo ? "Demo beenden" : "Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLogout = true
                }
            } footer: {
                Text("Inoffizieller Client für Schulmanager Online. Ruft die Daten über dieselbe Schnittstelle ab wie die Web-App.")
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
        .presentationBackground(.clear)
        .confirmationDialog("Wirklich abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.logout() } }
        } message: {
            Text("Zugangsdaten, Stundenplan und Verlauf werden von diesem Gerät gelöscht.")
        }
    }

    private var backgroundLabel: String {
        switch backgroundStatus {
        case .available: "Aktiv"
        case .denied: "Deaktiviert"
        case .restricted: "Eingeschränkt"
        @unknown default: "Unbekannt"
        }
    }

    private func loadStatus() async {
        authorization = await NotificationManager.status()
        backgroundStatus = UIApplication.shared.backgroundRefreshStatus
    }
}

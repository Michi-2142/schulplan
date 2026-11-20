import SwiftUI
import UserNotifications

@main
struct SchulplanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .onReceive(NotificationCenter.default.publisher(for: .openTab)) { note in
                    switch note.object as? String {
                    case "messages": model.selectedTab = .messages
                    case "school": model.selectedTab = .school
                    default: model.selectedTab = .changes
                    }
                }
                // Tipp auf ein Widget: schulplan://today bzw. schulplan://changes, optional ?student=<id>
                .onOpenURL { url in
                    guard url.scheme == "schulplan" else { return }
                    let studentId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "student" }?.value
                    Task {
                        if let studentId, model.students.contains(where: { $0.id == studentId }) {
                            await model.selectStudent(studentId)
                        }
                        model.selectedTab = url.host == "changes" ? .changes : .today
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.refreshIfStale() }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

extension Notification.Name {
    static let openTab = Notification.Name("openTab")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Mitteilungen auch anzeigen, wenn die App gerade offen ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let tab = response.notification.request.content.userInfo["tab"] as? String
        await MainActor.run { NotificationCenter.default.post(name: .openTab, object: tab) }
    }
}

import BackgroundTasks
import Foundation

/// iOS entscheidet selbst, wann die App im Hintergrund laufen darf. Wir fragen frühestens
/// alle 15 Minuten an; tatsächlich hängt der Takt von Nutzung, Akku und Netz ab.
enum BackgroundRefresh {
    static let identifier = "de.codeunity.Schulplan.refresh"

    static func schedule() {
        guard SessionStore.shared.isLoggedIn else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Nachts und am Wochenende seltener anfragen – spart Akku und schont den Server.
    private static var interval: TimeInterval {
        let calendar = SchoolCalendar.calendar
        let hour = calendar.component(.hour, from: .now)
        let weekday = calendar.component(.weekday, from: .now)
        if hour >= 22 || hour < 5 { return 60 * 60 }
        if weekday == 7 { return 60 * 60 } // Samstag
        return 15 * 60
    }

    static func run() async {
        schedule()
        SessionStore.shared.lastBackgroundRun = .now
        _ = try? await SyncService.shared.sync(notify: true)
    }
}

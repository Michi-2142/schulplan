import SwiftUI
import WidgetKit

@main
struct SchulplanWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ChangesWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.todayKind, intent: SelectStudentIntent.self, provider: PlanProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "schulplan://today\(entry.deepLinkQuery)"))
        }
        .configurationDisplayName("Stundenplan")
        .description("Die laufende und nächste Stunde und der Tagesplan – Änderungen farbig markiert.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct ChangesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.changesKind, intent: SelectStudentIntent.self, provider: PlanProvider()) { entry in
            ChangesWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "schulplan://changes\(entry.deepLinkQuery)"))
        }
        .configurationDisplayName("Planänderungen")
        .description("Ausfälle, Vertretungen und Raumänderungen der nächsten Tage.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

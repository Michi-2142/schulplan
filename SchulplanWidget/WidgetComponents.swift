import SwiftUI
import WidgetKit

/// Weicher Verlauf in den Farben des App-Hintergrunds.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.13, green: 0.07, blue: 0.24)]
                : [Color(red: 0.93, green: 0.95, blue: 1.00), Color(red: 0.97, green: 0.93, blue: 0.99)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Kopfzeile: Tag (+ Kind) links, optionaler Hinweis rechts.
struct WidgetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
                .widgetAccentable()
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            trailing
        }
        .lineLimit(1)
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Kleiner farbiger Zähler, z. B. „⚠︎ 2“.
struct CountBadge: View {
    let count: Int
    var icon = "exclamationmark.triangle.fill"
    var color: Color = .orange

    var body: some View {
        Label("\(count)", systemImage: icon)
            .labelStyle(TightLabelStyle())
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: .capsule)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

extension Lesson {
    var accent: Color { state == .regular ? SubjectColor.color(for: subject) : state.color }
}

/// Eine Zeile im Tagesplan.
struct LessonRow: View {
    let lesson: Lesson
    var isCurrent = false
    var showsTime = false
    var showsDetails = false
    var compact = false

    private var isCancelled: Bool { lesson.state == .cancelled }

    var body: some View {
        HStack(spacing: 6) {
            Text(lesson.hourLabel)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 15, alignment: .trailing)
            if showsTime {
                Text(lesson.start ?? "")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
            RoundedRectangle(cornerRadius: 1.5)
                .fill(lesson.accent.gradient)
                .frame(width: 3)
                .padding(.vertical, 1)
                .widgetAccentable()
            Text(compact ? lesson.shortSubject : lesson.subject)
                .font(.caption.weight(isCurrent ? .bold : .semibold))
                .strikethrough(isCancelled, color: .red)
                .foregroundStyle(isCancelled ? .secondary : .primary)
                .layoutPriority(1)
            if showsDetails, let note = lesson.changeNote {
                Text(note)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(lesson.state.color)
            } else if showsDetails, let teacher = lesson.teacher {
                Text(teacher)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if lesson.state != .regular {
                Image(systemName: lesson.state.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(lesson.state.color)
                    .widgetAccentable()
            }
            if let room = lesson.room, !isCancelled {
                Text(room)
                    .font(.caption2.weight(lesson.state == .roomChange ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(lesson.state == .roomChange ? AnyShapeStyle(LessonState.roomChange.color) : AnyShapeStyle(.secondary))
            }
        }
        .lineLimit(1)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, isCurrent ? 4 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.14))
            }
        }
        .padding(.horizontal, isCurrent ? -4 : 0)
    }
}

/// Laufende bzw. nächste Stunde, groß.
struct CurrentLessonBlock: View {
    let plan: DayPlan
    var large = false

    var body: some View {
        if let lesson = plan.current {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption(for: lesson))
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(plan.currentIsRunning ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
                Text(lesson.subject)
                    .font(large ? .title2.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(lesson.accent)
                    .lineLimit(large ? 1 : 2)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(details(for: lesson))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = lesson.changeNote {
                    Label(note, systemImage: lesson.state.icon)
                        .labelStyle(TightLabelStyle())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(lesson.state.color)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .widgetAccentable()
                Text(plan.day == nil ? "Schulfrei" : "Alles fällt aus")
                    .font(.headline)
            }
        }
    }

    private func caption(for lesson: Lesson) -> String {
        if plan.currentIsRunning {
            return lesson.end.map { "Jetzt · bis \($0)" } ?? "Jetzt"
        }
        if plan.day == plan.today {
            return "Danach · \(lesson.hourLabel). Std"
        }
        return "\(plan.dayLabel) · \(lesson.hourLabel). Std"
    }

    private func details(for lesson: Lesson) -> String {
        let time = plan.currentIsRunning ? nil : lesson.timeRange
        return [time, lesson.room.map { "Raum \($0)" }, lesson.teacher].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Leerer Zustand vor dem ersten Abruf.
struct NotSignedInView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "graduationcap.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text("Öffne Schulplan und melde dich an.")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// „Stand 07:12“ – damit man sieht, wenn die Daten älter sind.
struct FreshnessLabel: View {
    let student: WidgetStudent
    let now: Date

    var body: some View {
        let stale = now.timeIntervalSince(student.fetchedAt) > 6 * 3600
        Label {
            Text("Stand \(student.fetchedAt.formatted(stale ? .dateTime.day().month().hour().minute() : .dateTime.hour().minute()))")
        } icon: {
            Image(systemName: stale ? "exclamationmark.arrow.circlepath" : "arrow.clockwise")
        }
        .labelStyle(TightLabelStyle())
        .font(.caption2)
        .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
        .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

extension String {
    /// „Mo 17.11.“ → kurze Tagesangabe für Listen.
    var dayChipLabel: String { SchoolCalendar.shortWeekday(self) + " " + SchoolCalendar.dayMonth(self) }
}

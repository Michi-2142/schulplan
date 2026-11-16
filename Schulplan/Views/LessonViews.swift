import SwiftUI

struct LessonCard: View {
    let lesson: Lesson
    var isNow = false

    private var accent: Color { lesson.state == .regular ? SubjectColor.color(for: lesson.subject) : lesson.state.color }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(lesson.hourLabel)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(accent)
                if let start = lesson.start {
                    Text(start).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 46)

            Capsule()
                .fill(accent.gradient)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(lesson.subject)
                        .font(.headline)
                        .strikethrough(lesson.state == .cancelled, color: .red)
                        .foregroundStyle(lesson.state == .cancelled ? .secondary : .primary)
                    Spacer(minLength: 6)
                    if isNow {
                        StateBadge(text: "Jetzt", icon: "dot.radiowaves.left.and.right", color: .green)
                    }
                    if lesson.state != .regular {
                        StateBadge(text: lesson.state.label, icon: lesson.state.icon, color: lesson.state.color)
                    }
                }

                HStack(spacing: 14) {
                    if let teacher = lesson.teacher {
                        Label(teacher, systemImage: "person.fill")
                    }
                    if let room = lesson.room {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(lesson.state == .roomChange ? lesson.state.color : .secondary)
                            .fontWeight(lesson.state == .roomChange ? .semibold : .regular)
                    }
                    if let end = lesson.end {
                        Label("bis \(end)", systemImage: "clock")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())

                if let original = originalLine {
                    Text(original)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(lesson.state.color)
                }
                if let comment = lesson.comment {
                    Text(comment)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: lesson.state == .regular ? (isNow ? .green : nil) : lesson.state.color)
    }

    private var originalLine: String? {
        switch lesson.state {
        case .substitution:
            let parts = [lesson.originalSubject, lesson.originalTeacher.map { "bei \($0)" }].compactMap { $0 }
            return parts.isEmpty ? nil : "statt " + parts.joined(separator: " ")
        case .roomChange:
            return lesson.originalRoom.map { "statt Raum \($0)" }
        case .cancelled:
            return lesson.teacher == nil ? lesson.originalTeacher.map { "bei \($0)" } : nil
        default:
            return nil
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

struct StateBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .labelStyle(CompactLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color.opacity(0.18)), in: .capsule)
    }
}

/// Detailansicht einer Stunde (aus der Wochenübersicht).
struct LessonDetailSheet: View {
    let lesson: Lesson

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LessonCard(lesson: lesson)
                    VStack(alignment: .leading, spacing: 12) {
                        row("Datum", "\(SchoolCalendar.longWeekday(lesson.date)), \(SchoolCalendar.dayMonth(lesson.date))")
                        row("Stunde", "\(lesson.hourLabel). Stunde")
                        if let time = lesson.timeRange { row("Zeit", time) }
                        row("Fach", lesson.subject)
                        if let teacher = lesson.teacher { row("Lehrkraft", teacher) }
                        if let room = lesson.room { row("Raum", room) }
                        if lesson.state != .regular {
                            Divider()
                            row("Status", lesson.state.label)
                            if let value = lesson.originalSubject { row("Ursprünglich", value) }
                            if let value = lesson.originalTeacher { row("Ursprüngl. Lehrkraft", value) }
                            if let value = lesson.originalRoom { row("Ursprüngl. Raum", value) }
                        }
                        if let comment = lesson.comment { row("Hinweis", comment) }
                    }
                    .padding(18)
                    .glassCard()
                }
                .padding()
            }
            .navigationTitle(lesson.subject)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

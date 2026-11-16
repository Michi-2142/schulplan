import SwiftUI

struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var weekOffset = 0
    @State private var detail: Lesson?

    private var weekStart: String { SchoolCalendar.addDays(7 * weekOffset, to: SchoolCalendar.schoolWeekStart()) }
    private var days: [String] { SchoolCalendar.schoolDays(from: weekStart) }

    private var weekLessons: [Lesson] {
        let range = Set(days)
        return model.lessons.filter { range.contains($0.date) }
    }

    /// Stundennummern der Woche, sortiert („1“, „2“, … „8“).
    private var hours: [(label: String, sort: Int)] {
        var seen: [String: Int] = [:]
        for lesson in weekLessons { seen[lesson.hour] = lesson.hourSort }
        return seen.map { ($0.key, $0.value) }.sorted { ($0.sort, $0.label) < ($1.sort, $1.label) }
    }

    var body: some View {
        Screen(title: weekOffset == 0 ? "Diese Woche" : "Nächste Woche",
               subtitle: "\(SchoolCalendar.dayMonth(days.first ?? "")) – \(SchoolCalendar.dayMonth(days.last ?? ""))") {
            VStack(spacing: 16) {
                if weekLessons.isEmpty {
                    EmptyStateCard(icon: "calendar.badge.exclamationmark", title: "Kein Stundenplan",
                                   message: "Für diese Woche liegen keine Stunden vor.")
                } else {
                    grid
                    legend
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Vorherige Woche", systemImage: "chevron.left") { withAnimation(.smooth) { weekOffset = 0 } }
                    .disabled(weekOffset == 0)
                Button("Nächste Woche", systemImage: "chevron.right") { withAnimation(.smooth) { weekOffset = 1 } }
                    .disabled(weekOffset == 1)
            }
        }
        .sheet(item: $detail) { lesson in
            LessonDetailSheet(lesson: lesson)
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 22, height: 1)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(SchoolCalendar.shortWeekday(day)).font(.caption.weight(.bold))
                        Text(SchoolCalendar.dayMonth(day)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(day == SchoolCalendar.today ? Color.accentColor : .primary)
                    .glassEffect(day == SchoolCalendar.today ? .regular.tint(.accentColor.opacity(0.25)) : .regular,
                                 in: .rect(cornerRadius: 12))
                }
            }
            ForEach(hours, id: \.label) { hour in
                GridRow {
                    Text(hour.label)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    ForEach(days, id: \.self) { day in
                        cell(weekLessons.filter { $0.date == day && $0.hour == hour.label })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ lessons: [Lesson]) -> some View {
        if let lesson = lessons.first(where: { $0.state != .regular }) ?? lessons.first {
            let color = lesson.state == .regular ? SubjectColor.color(for: lesson.subject) : lesson.state.color
            Button {
                detail = lesson
            } label: {
                VStack(spacing: 1) {
                    Text(lesson.subjectAbbr ?? String(lesson.subject.prefix(4)))
                        .font(.caption.weight(.bold))
                        .strikethrough(lesson.state == .cancelled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(lesson.room ?? " ")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if lessons.count > 1 {
                        Text("+\(lessons.count - 1)").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(lesson.state == .cancelled ? .secondary : .primary)
                .overlay(alignment: .topTrailing) {
                    if lesson.state != .regular {
                        Circle().fill(lesson.state.color).frame(width: 7, height: 7).padding(4)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(color.opacity(lesson.state == .regular ? 0.18 : 0.38)).interactive(),
                         in: .rect(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([LessonState.cancelled, .substitution, .roomChange, .added], id: \.self) { state in
                HStack(spacing: 4) {
                    Circle().fill(state.color).frame(width: 8, height: 8)
                    Text(state.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

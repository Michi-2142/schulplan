import SwiftUI

struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var weekOffset = 0
    @State private var detail: WeekCellDetail?

    private var weekStart: String { SchoolCalendar.addDays(7 * weekOffset, to: SchoolCalendar.schoolWeekStart()) }
    private var days: [String] { SchoolCalendar.schoolDays(from: weekStart) }

    private var weekLessons: [Lesson] {
        let range = Set(days)
        return model.lessons.filter { range.contains($0.date) }
    }

    private var weekExams: [Exam] {
        let range = Set(days)
        return (model.snapshot?.exams ?? []).filter { range.contains($0.date) }
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
                if !weekExams.isEmpty {
                    examList
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
        .sheet(item: $detail) { detail in
            if !detail.lessons.isEmpty {
                LessonDetailSheet(lessons: detail.lessons, exams: detail.exams)
            } else {
                ExamDetailSheet(exams: detail.exams)
            }
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
                    .overlay(alignment: .topTrailing) {
                        if weekExams.contains(where: { $0.date == day }) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.examColor)
                                .padding(4)
                        }
                    }
                }
            }
            ForEach(hours, id: \.label) { hour in
                GridRow {
                    Text(hour.label)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    ForEach(days, id: \.self) { day in
                        let lessons = weekLessons.filter { $0.date == day && $0.hour == hour.label }
                        cell(lessons, exams: exams(day: day, hour: hour.sort, lessons: lessons))
                    }
                }
            }
        }
    }

    /// Arbeiten in dieser Stunde – über die Stundennummer oder, falls die fehlt, über die Stunden selbst.
    private func exams(day: String, hour: Int, lessons: [Lesson]) -> [Exam] {
        weekExams.filter { exam in
            guard exam.date == day else { return false }
            if let start = exam.startHour { return (start...max(start, exam.endHour ?? start)).contains(hour) }
            return lessons.contains { exam.covers($0) }
        }
    }

    @ViewBuilder
    private func cell(_ lessons: [Lesson], exams: [Exam]) -> some View {
        // Hauptstunde: eine stattfindende (geänderte vor regulärer) – Entfall nur, wenn nichts anderes stattfindet.
        // Sonst würde eine entfallene Parallelstunde (z. B. „E-T“) die ganze Zelle als Entfall zeigen.
        let active = lessons.filter { $0.state != .cancelled }
        let cancelledOthers = active.isEmpty ? [] : lessons.filter { $0.state == .cancelled }
        if let lesson = active.first(where: { $0.state != .regular }) ?? active.first ?? lessons.first {
            let color = lesson.state == .regular ? SubjectColor.color(for: lesson.subject) : lesson.state.color
            Button {
                detail = WeekCellDetail(lessons: orderedForDetail(lessons), exams: exams)
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
                    if let gone = cancelledOthers.first {
                        Text(gone.subjectAbbr ?? String(gone.subject.prefix(4)))
                            .font(.system(size: 9, weight: .semibold))
                            .strikethrough(color: .red)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    let more = lessons.count - 1 - cancelledOthers.count
                    if more > 0 {
                        Text("+\(more)").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(lesson.state == .cancelled ? .secondary : .primary)
                .overlay(alignment: .topTrailing) {
                    if lesson.state != .regular || !cancelledOthers.isEmpty {
                        Circle().fill(lesson.state == .regular ? LessonState.cancelled.color : lesson.state.color).frame(width: 7, height: 7).padding(4)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !exams.isEmpty { examBadge }
                }
                .overlay {
                    if !exams.isEmpty {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.examColor, lineWidth: 1.5)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(color.opacity(lesson.state == .regular ? 0.18 : 0.38)).interactive(),
                         in: .rect(cornerRadius: 12))
        } else if let exam = exams.first {
            Button {
                detail = WeekCellDetail(lessons: [], exams: exams)
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "doc.text.fill").font(.caption)
                    Text(String(exam.subject.prefix(4)))
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Color.examColor)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.examColor.opacity(0.25)).interactive(), in: .rect(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
    }

    /// Stattfindende Stunden zuerst, entfallene danach.
    private func orderedForDetail(_ lessons: [Lesson]) -> [Lesson] {
        lessons.filter { $0.state != .cancelled } + lessons.filter { $0.state == .cancelled }
    }

    private var examBadge: some View {
        Image(systemName: "doc.text.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(Color.examColor, in: .circle)
            .padding(3)
    }

    /// Alle Arbeiten der Woche mit Anmerkungen – auch solche ohne Stundenangabe.
    private var examList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Arbeiten in dieser Woche", systemImage: "doc.text.fill")
                .font(.headline)
                .foregroundStyle(Color.examColor)
                .padding(.horizontal, 4)
            ForEach(weekExams) { exam in
                Button {
                    detail = WeekCellDetail(lessons: [], exams: [exam])
                } label: {
                    ExamCard(exam: exam)
                }
                .buttonStyle(.plain)
            }
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

/// Inhalt des Detail-Sheets: eine Stunde und/oder die Arbeiten darin.
struct WeekCellDetail: Identifiable {
    let lessons: [Lesson]
    let exams: [Exam]

    var id: String { lessons.isEmpty ? exams.map(\.id).joined(separator: ",") : lessons.map(\.id).joined(separator: ",") }
}

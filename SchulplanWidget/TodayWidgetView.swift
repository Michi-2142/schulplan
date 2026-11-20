import SwiftUI
import WidgetKit

struct TodayWidgetView: View {
    let entry: PlanEntry
    /// Nur für Vorschauen außerhalb von WidgetKit.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var plan: DayPlan { entry.plan }
    private var name: String? { entry.showsName ? entry.student?.name : nil }

    var body: some View {
        if entry.isEmpty {
            switch family {
            case .accessoryInline: Text("Schulplan: nicht angemeldet")
            case .accessoryCircular, .accessoryRectangular: Image(systemName: "graduationcap.fill").font(.title2)
            default: NotSignedInView()
            }
        } else {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .systemLarge: large
            case .systemExtraLarge: extraLarge
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    // MARK: Home-Bildschirm

    private var header: some View {
        WidgetHeader(title: plan.dayLabel, subtitle: name) {
            if plan.changesOnDay > 0 { CountBadge(count: plan.changesOnDay) }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)
            CurrentLessonBlock(plan: plan)
            Spacer(minLength: 6)
            smallFooter
        }
    }

    @ViewBuilder
    private var smallFooter: some View {
        let remaining = remainingLessons
        if let last = plan.lessons.last(where: { $0.state != .cancelled }), let end = last.end {
            Text(remaining > 0 ? "noch \(remaining) Std · bis \(end)" : "Schluss \(end)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Stunden nach der angezeigten (ohne Ausfälle).
    private var remainingLessons: Int {
        guard let current = plan.current else { return 0 }
        return plan.lessons.filter { $0.hourSort > current.hourSort && $0.state != .cancelled }.count
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 6)
                CurrentLessonBlock(plan: plan)
                Spacer(minLength: 6)
                smallFooter
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            lessonList(maxRows: 7, compact: true, showsTime: false, showsDetails: false)
                .frame(maxWidth: .infinity)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if plan.day == plan.today {
                CurrentLessonBlock(plan: plan, large: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.opacity(0.45), in: .rect(cornerRadius: 14))
            }
            lessonList(maxRows: plan.day == plan.today ? 7 : 9, compact: false, showsTime: true, showsDetails: true)
            Spacer(minLength: 0)
            footer(maxChanges: 2)
        }
    }

    private var extraLarge: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                header
                CurrentLessonBlock(plan: plan, large: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.opacity(0.45), in: .rect(cornerRadius: 14))
                lessonList(maxRows: 10, compact: false, showsTime: true, showsDetails: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Demnächst")
                ChangesList(plan: plan, maxRows: 7, excludeDay: plan.day)
                Spacer(minLength: 0)
                ExamsList(exams: entry.student?.exams ?? [], today: plan.today, maxRows: 3)
                StatusRow(student: entry.student)
                if let student = entry.student { FreshnessLabel(student: student, now: entry.date) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func lessonList(maxRows: Int, compact: Bool, showsTime: Bool, showsDetails: Bool) -> some View {
        let lessons = Array(plan.lessons.prefix(maxRows))
        let hidden = plan.lessons.count - lessons.count
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(lessons) { lesson in
                LessonRow(
                    lesson: lesson,
                    isCurrent: plan.currentIsRunning && lesson.id == plan.current?.id,
                    showsTime: showsTime,
                    showsDetails: showsDetails,
                    compact: compact
                )
                .frame(maxHeight: compact ? 17 : 22)
            }
            if hidden > 0 {
                Text("+ \(hidden) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 21)
            }
            if lessons.isEmpty {
                Text("Keine Stunden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Änderungen an anderen Tagen + nächste Arbeit + Stand.
    private func footer(maxChanges: Int) -> some View {
        let otherChanges = plan.changes.filter { $0.date != plan.day }
        let exam = entry.student?.exams.first { $0.date >= plan.today }
        return VStack(alignment: .leading, spacing: 3) {
            Divider().padding(.bottom, 2)
            ForEach(otherChanges.prefix(maxChanges)) { lesson in
                ChangeLine(lesson: lesson, today: plan.today)
            }
            if let exam {
                Label {
                    Text("\(exam.type ?? "Arbeit") \(exam.subject) · \(SchoolCalendar.relativeLabel(exam.date, from: plan.today))")
                } icon: {
                    Image(systemName: "doc.text.fill").foregroundStyle(.pink)
                }
                .labelStyle(TightLabelStyle())
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            }
            HStack {
                StatusRow(student: entry.student)
                Spacer(minLength: 4)
                if let student = entry.student { FreshnessLabel(student: student, now: entry.date) }
            }
        }
    }

    // MARK: Sperrbildschirm

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let lesson = plan.current {
                VStack(spacing: -1) {
                    Text(plan.currentIsRunning ? "jetzt" : "\(lesson.hourLabel).")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(lesson.shortSubject)
                        .font(.system(size: 15, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                    if let room = lesson.room {
                        Text(room).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                }
                .padding(4)
            } else {
                Image(systemName: "sun.max.fill").font(.title3)
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let lesson = plan.current {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(plan.currentIsRunning ? "Jetzt" : "\(plan.day == plan.today ? "" : plan.dayLabel + " · ")\(lesson.hourLabel). Std")
                    if !plan.currentIsRunning, let start = lesson.start { Text(start) }
                    Spacer(minLength: 0)
                    if plan.changesOnDay > 0 {
                        Label("\(plan.changesOnDay)", systemImage: "exclamationmark.triangle.fill").labelStyle(TightLabelStyle())
                    }
                }
                .font(.caption.weight(.semibold))
                .widgetAccentable()
                Text(lesson.subject)
                    .font(.headline)
                    .lineLimit(1)
                Text(lesson.changeNote ?? [lesson.room.map { "Raum \($0)" }, lesson.teacher].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading) {
                Text("Schulplan").font(.caption.weight(.semibold)).widgetAccentable()
                Text("Heute kein Unterricht mehr").font(.headline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let lesson = plan.current {
            let prefix = plan.currentIsRunning ? "Jetzt" : "\(lesson.hourLabel). Std"
            let suffix = lesson.state == .regular ? lesson.room.map { " · \($0)" } ?? "" : " · \(lesson.state.label)"
            Label("\(prefix) \(lesson.subject)\(suffix)", systemImage: lesson.state == .regular ? "book.closed" : lesson.state.icon)
        } else {
            Label("Schulfrei", systemImage: "sun.max")
        }
    }
}

/// Briefe, Hausaufgaben, Nachrichten als kleine Zähler.
struct StatusRow: View {
    let student: WidgetStudent?

    var body: some View {
        if let student {
            HStack(spacing: 8) {
                if student.openHomework > 0 { item("\(student.openHomework)", "book.closed.fill", .teal) }
                if student.openLetters > 0 { item("\(student.openLetters)", "envelope.badge.fill", .orange) }
                if student.unreadMessages > 0 { item("\(student.unreadMessages)", "bubble.left.fill", .blue) }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
        }
    }

    private func item(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(TightLabelStyle())
            .foregroundStyle(color)
    }
}

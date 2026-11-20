import SwiftUI
import WidgetKit

struct ChangesWidgetView: View {
    let entry: PlanEntry
    /// Nur für Vorschauen außerhalb von WidgetKit.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var plan: DayPlan { entry.plan }
    private var changes: [Lesson] { plan.changes }
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

    private var title: String { changes.count == 1 ? "1 Änderung" : "\(changes.count) Änderungen" }

    // MARK: Home-Bildschirm

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Änderungen", subtitle: name)
            Spacer(minLength: 4)
            if changes.isEmpty {
                AllClearView()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(changes.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                        .widgetAccentable()
                    Text(changes.count == 1 ? "Änderung" : "Änderungen")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(changes.prefix(2)) { lesson in
                        ChangeLine(lesson: lesson, today: plan.today, compact: true)
                    }
                }
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: changes.isEmpty ? "Planänderungen" : title, subtitle: name) {
                if let student = entry.student { FreshnessLabel(student: student, now: entry.date) }
            }
            if changes.isEmpty {
                AllClearView(horizontal: true)
            } else {
                ChangesList(plan: plan, maxRows: 4, grouped: false)
            }
            Spacer(minLength: 0)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: changes.isEmpty ? "Planänderungen" : title, subtitle: name)
            if changes.isEmpty {
                AllClearView(horizontal: true)
            } else {
                ChangesList(plan: plan, maxRows: 9)
            }
            Spacer(minLength: 0)
            ExamsList(exams: entry.student?.exams ?? [], today: plan.today, maxRows: 2)
            HStack {
                StatusRow(student: entry.student)
                Spacer(minLength: 4)
                if let student = entry.student { FreshnessLabel(student: student, now: entry.date) }
            }
        }
    }

    private var extraLarge: some View {
        let days = Array(Set(changes.map(\.date))).sorted()
        let split = changes.count > 9 ? max(1, days.count / 2) : days.count
        let left = changes.filter { days.prefix(split).contains($0.date) }
        let right = changes.filter { !days.prefix(split).contains($0.date) }
        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: changes.isEmpty ? "Planänderungen" : title, subtitle: name) {
                if let student = entry.student { FreshnessLabel(student: student, now: entry.date) }
            }
            if changes.isEmpty {
                AllClearView(horizontal: true)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ChangesList(plan: plan, lessons: left, maxRows: 11)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 10) {
                        if !right.isEmpty { ChangesList(plan: plan, lessons: right, maxRows: 7) }
                        Spacer(minLength: 0)
                        ExamsList(exams: entry.student?.exams ?? [], today: plan.today, maxRows: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            StatusRow(student: entry.student)
        }
    }

    // MARK: Sperrbildschirm

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: changes.isEmpty ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .widgetAccentable()
                Text(changes.isEmpty ? "OK" : "\(changes.count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let first = changes.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: first.state.icon)
                    Text("\(SchoolCalendar.relativeLabel(first.date, from: plan.today)) · \(first.hourLabel). Std")
                    Spacer(minLength: 0)
                    if changes.count > 1 { Text("+\(changes.count - 1)") }
                }
                .font(.caption.weight(.semibold))
                .widgetAccentable()
                Text("\(first.state.label): \(first.subject)")
                    .font(.headline)
                    .lineLimit(1)
                // „fällt aus“ stünde doppelt neben „Entfall“ – dann lieber Lehrkraft bzw. Hinweis zeigen.
                let note = first.state == .cancelled ? (first.comment ?? first.teacher ?? first.originalTeacher) : first.changeNote
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Label("Planänderungen", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text("Alles nach Plan").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let first = changes.first {
            Label("\(first.state.label) \(first.shortSubject) · \(SchoolCalendar.relativeLabel(first.date, from: plan.today)) \(first.hourLabel). Std",
                  systemImage: first.state.icon)
        } else {
            Label("Keine Planänderungen", systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Bausteine

struct AllClearView: View {
    var horizontal = false

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        layout {
            Image(systemName: "checkmark.seal.fill")
                .font(horizontal ? .title : .largeTitle)
                .foregroundStyle(.green)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Alles nach Plan").font(.headline)
                Text("Keine Ausfälle oder Vertretungen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: horizontal ? nil : .infinity, alignment: .leading)
    }
}

/// Einzeilige Änderung: Symbol, Tag, Stunde, Fach, Hinweis.
struct ChangeLine: View {
    let lesson: Lesson
    let today: String
    var compact = false
    var showsDay = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: lesson.state.icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(lesson.state.color)
                .frame(width: 14)
                .widgetAccentable()
            if showsDay {
                Text(compact && lesson.date > SchoolCalendar.addDays(1, to: today)
                     ? SchoolCalendar.shortWeekday(lesson.date)
                     : SchoolCalendar.relativeLabel(lesson.date, from: today))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(lesson.hourLabel).")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Text(compact ? lesson.shortSubject : lesson.subject)
                .font(.caption.weight(.semibold))
                .strikethrough(lesson.state == .cancelled, color: .red)
                .layoutPriority(1)
            if !compact, let note = lesson.changeNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(lesson.state.color)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

/// Änderungen, nach Tag gruppiert.
struct ChangesList: View {
    let plan: DayPlan
    var lessons: [Lesson]? = nil
    let maxRows: Int
    var grouped = true
    /// Tag, der schon an anderer Stelle vollständig zu sehen ist.
    var excludeDay: String? = nil

    private var items: [Lesson] { (lessons ?? plan.changes).filter { $0.date != excludeDay } }

    var body: some View {
        let shown = Array(items.prefix(maxRows))
        let hidden = items.count - shown.count
        VStack(alignment: .leading, spacing: 4) {
            if grouped {
                ForEach(days(of: shown), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(SchoolCalendar.relativeLabel(day, from: plan.today))\(day == plan.today || day == SchoolCalendar.addDays(1, to: plan.today) ? " · " + SchoolCalendar.dayMonth(day) : "")")
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        ForEach(shown.filter { $0.date == day }) { lesson in
                            ChangeLine(lesson: lesson, today: plan.today, showsDay: false)
                        }
                    }
                }
            } else {
                ForEach(shown) { lesson in
                    ChangeLine(lesson: lesson, today: plan.today)
                }
            }
            if hidden > 0 {
                Text("+ \(hidden) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Label("Keine weiteren Änderungen", systemImage: "checkmark.circle.fill")
                    .labelStyle(TightLabelStyle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func days(of lessons: [Lesson]) -> [String] {
        var seen: [String] = []
        for lesson in lessons where !seen.contains(lesson.date) { seen.append(lesson.date) }
        return seen
    }
}

/// Nächste Schulaufgaben / Tests.
struct ExamsList: View {
    let exams: [WidgetExam]
    let today: String
    let maxRows: Int

    var body: some View {
        let upcoming = exams.filter { $0.date >= today }.prefix(maxRows)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Arbeiten")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                ForEach(Array(upcoming)) { exam in
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                            .frame(width: 14)
                        Text(SchoolCalendar.relativeLabel(exam.date, from: today))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text([exam.type, exam.subject].compactMap { $0 }.joined(separator: " "))
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                }
            }
        }
    }
}

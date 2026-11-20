import SwiftUI

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section
    @State private var showDone = false

    init(section: Section = .homework) {
        _section = State(initialValue: section)
    }

    enum Section: String, CaseIterable, Identifiable {
        case homework = "Hausaufgaben"
        case exams = "Arbeiten"
        var id: String { rawValue }
    }

    var body: some View {
        Screen(title: section.rawValue, showsSettings: false) {
            VStack(spacing: 14) {
                Picker("Bereich", selection: $section.animation(.smooth)) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                switch section {
                case .homework: homework
                case .exams: exams
                }
            }
        }
    }

    // MARK: Hausaufgaben

    private var openHomework: [Homework] {
        let today = SchoolCalendar.today
        return (model.snapshot?.homework ?? [])
            .filter { ($0.due ?? $0.date) >= SchoolCalendar.addDays(-1, to: today) }
            .sorted { ($0.due ?? $0.date) < ($1.due ?? $1.date) }
    }

    @ViewBuilder
    private var homework: some View {
        let items = openHomework.filter { showDone || !model.doneHomework.contains($0.id) }
        if items.isEmpty {
            EmptyStateCard(icon: "checkmark.circle.fill", title: "Nichts zu tun",
                           message: "Keine offenen Hausaufgaben eingetragen.")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    HomeworkCard(item: item, done: model.doneHomework.contains(item.id)) {
                        withAnimation(.bouncy) {
                            if model.doneHomework.contains(item.id) { model.doneHomework.remove(item.id) }
                            else { model.doneHomework.insert(item.id) }
                        }
                    }
                }
            }
        }
        Toggle("Erledigte anzeigen", isOn: $showDone.animation())
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: Arbeiten

    @ViewBuilder
    private var exams: some View {
        let items = (model.snapshot?.exams ?? []).filter { $0.date >= SchoolCalendar.today }
        if items.isEmpty {
            EmptyStateCard(icon: "doc.text.magnifyingglass", title: "Keine Arbeiten",
                           message: "Es sind keine Leistungsnachweise angekündigt.")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(items) { ExamCard(exam: $0) }
            }
        }
    }
}

struct HomeworkCard: View {
    let item: Homework
    let done: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : SubjectColor.color(for: item.subject))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.subject).font(.headline)
                    Spacer()
                    if let due = item.due {
                        Text("bis \(SchoolCalendar.relativeLabel(due))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(due <= SchoolCalendar.addDays(1, to: SchoolCalendar.today) ? .orange : .secondary)
                    } else {
                        Text("vom \(SchoolCalendar.relativeLabel(item.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .glassCard()
        .opacity(done ? 0.7 : 1)
    }
}

struct ExamCard: View {
    let exam: Exam

    private var daysLeft: Int {
        guard let date = SchoolCalendar.date(exam.date), let today = SchoolCalendar.date(SchoolCalendar.today) else { return 0 }
        return SchoolCalendar.calendar.dateComponents([.day], from: today, to: date).day ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                if daysLeft == 0 {
                    Text("Heute").font(.subheadline.bold())
                } else if daysLeft < 0 {
                    Image(systemName: "checkmark").font(.title2.bold())
                    Text("vorbei").font(.caption2)
                } else {
                    Text("\(daysLeft)").font(.title.bold().monospacedDigit())
                    Text(daysLeft == 1 ? "Tag" : "Tage").font(.caption2)
                }
            }
            .foregroundStyle((0...3).contains(daysLeft) ? Color.red : SubjectColor.color(for: exam.subject))
            .frame(width: 56, height: 56)
            .glassEffect(.regular.tint(((0...3).contains(daysLeft) ? Color.red : SubjectColor.color(for: exam.subject)).opacity(0.2)),
                         in: .rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(exam.subject).font(.headline)
                Text([exam.type, "\(SchoolCalendar.longWeekday(exam.date)), \(SchoolCalendar.dayMonth(exam.date))",
                      exam.hoursLabel ?? exam.start.map { "\($0) Uhr" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let comment = exam.comment {
                    Text(comment).font(.footnote).foregroundStyle(.secondary).italic()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard()
    }
}

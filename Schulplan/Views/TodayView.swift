import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDay = SchoolCalendar.today
    @Namespace private var glass

    private var days: [String] {
        let start = SchoolCalendar.schoolWeekStart()
        return SchoolCalendar.schoolDays(from: start) + SchoolCalendar.schoolDays(from: SchoolCalendar.addDays(7, to: start))
    }

    var body: some View {
        Screen(title: SchoolCalendar.relativeLabel(selectedDay), subtitle: subtitle) {
            VStack(spacing: 14) {
                dayPicker
                if let failed = model.snapshot?.failedModules, failed.contains("Stundenplan") {
                    Label("Stundenplan konnte nicht geladen werden – du siehst den letzten Stand.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glassCard(tint: .orange, cornerRadius: 16)
                }
                ForEach(model.events(on: selectedDay)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.isHoliday ? "sun.horizon.fill" : "calendar")
                            .foregroundStyle(event.isHoliday ? Color.green : .red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                            Text([event.timeLabel ?? "ganztägig", event.location].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .glassCard(tint: event.isHoliday ? .green : .red, cornerRadius: 18)
                }
                if selectedDay == SchoolCalendar.today, let next = nextLesson {
                    NowCard(lesson: next.lesson, isRunning: next.running)
                }
                lessonList
            }
        }
        .onAppear(perform: pickInitialDay)
        // Beim ersten Start sind die Daten beim Erscheinen noch nicht da – dann nachziehen.
        .onChange(of: model.snapshot == nil) { wasEmpty, isEmpty in
            if wasEmpty, !isEmpty { pickInitialDay() }
        }
    }

    private var subtitle: String {
        let lessons = model.lessons(on: selectedDay)
        let changes = lessons.filter { $0.state != .regular }.count
        let base = "\(SchoolCalendar.longWeekday(selectedDay)), \(SchoolCalendar.dayMonth(selectedDay))"
        guard !lessons.isEmpty else { return base }
        return changes > 0 ? "\(base) · \(changes) Änderung\(changes == 1 ? "" : "en")" : base
    }

    private var dayPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            dayChip(day).id(day)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(selectedDay, anchor: .center) }
        }
    }

    private func dayChip(_ day: String) -> some View {
        let selected = day == selectedDay
        let hasChanges = model.lessons(on: day).contains { $0.state != .regular }
        let isToday = day == SchoolCalendar.today
        return Button {
            withAnimation(.bouncy) { selectedDay = day }
        } label: {
            VStack(spacing: 2) {
                Text(SchoolCalendar.shortWeekday(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                Text(SchoolCalendar.dayNumber(day))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(selected ? .white : (isToday ? Color.accentColor : .primary))
                Circle()
                    .fill(hasChanges ? (selected ? .white : .red) : .clear)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 52, height: 70)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .rect(cornerRadius: 22))
        .glassEffectID(day, in: glass)
    }

    @ViewBuilder
    private var lessonList: some View {
        let lessons = model.lessons(on: selectedDay)
        if lessons.isEmpty {
            if model.snapshot == nil, model.isRefreshing {
                ProgressView().padding(.top, 60)
            } else {
                EmptyStateCard(
                    icon: "beach.umbrella.fill",
                    title: "Kein Unterricht",
                    message: "Für diesen Tag ist nichts eingetragen."
                )
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(lessons) { lesson in
                    LessonCard(lesson: lesson, isNow: isRunning(lesson))
                }
            }
            if lessons.allSatisfy({ $0.state == .cancelled }) {
                Label("Alle Stunden entfallen", systemImage: "party.popper.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }
        }
    }

    private func isRunning(_ lesson: Lesson) -> Bool {
        guard lesson.date == SchoolCalendar.today, lesson.state != .cancelled,
              let start = SchoolCalendar.minutes(lesson.start), let end = SchoolCalendar.minutes(lesson.end) else { return false }
        let now = SchoolCalendar.nowMinutes
        return now >= start && now < end
    }

    private var nextLesson: (lesson: Lesson, running: Bool)? {
        let today = model.lessons(on: SchoolCalendar.today).filter { $0.state != .cancelled }
        if let running = today.first(where: isRunning) { return (running, true) }
        let now = SchoolCalendar.nowMinutes
        if let upcoming = today.first(where: { (SchoolCalendar.minutes($0.start) ?? 0) > now }) { return (upcoming, false) }
        return nil
    }

    /// Nach Schulschluss bzw. am Wochenende direkt den nächsten Schultag zeigen.
    private func pickInitialDay() {
        let today = SchoolCalendar.today
        let todaysLessons = model.lessons(on: today)
        let lastEnd = todaysLessons.compactMap { SchoolCalendar.minutes($0.end) }.max() ?? 0
        if days.contains(today), !todaysLessons.isEmpty, SchoolCalendar.nowMinutes < lastEnd {
            selectedDay = today
        } else {
            selectedDay = days.first { $0 > today } ?? days.first ?? today
        }
    }
}

/// Großer Hinweis auf die laufende bzw. nächste Stunde.
struct NowCard: View {
    let lesson: Lesson
    let isRunning: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(lesson.hourLabel)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isRunning ? "Gerade" : "Als Nächstes")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(lesson.subject)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(18)
            .glassEffect(.regular.tint(tint.opacity(0.75)).interactive(), in: .rect(cornerRadius: 28))
        }
    }

    private var tint: Color { lesson.state == .regular ? SubjectColor.color(for: lesson.subject) : lesson.state.color }

    private var detail: String {
        var parts: [String] = []
        if let room = lesson.room { parts.append("Raum \(room)") }
        if isRunning, let end = SchoolCalendar.minutes(lesson.end) {
            parts.append("noch \(max(0, end - SchoolCalendar.nowMinutes)) Min.")
        } else if let start = SchoolCalendar.minutes(lesson.start) {
            let diff = start - SchoolCalendar.nowMinutes
            parts.append(diff < 60 ? "in \(diff) Min." : "um \(lesson.start ?? "")")
        }
        if lesson.state != .regular { parts.append(lesson.state.label) }
        return parts.joined(separator: " · ")
    }

    private var progress: CGFloat {
        guard isRunning, let start = SchoolCalendar.minutes(lesson.start), let end = SchoolCalendar.minutes(lesson.end), end > start
        else { return 0 }
        return CGFloat(SchoolCalendar.nowMinutes - start) / CGFloat(end - start)
    }
}

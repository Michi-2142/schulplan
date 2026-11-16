import SwiftUI

struct ChangesView: View {
    @Environment(AppModel.self) private var model

    private var groupedChanges: [(date: String, lessons: [Lesson])] {
        Dictionary(grouping: model.upcomingChanges, by: \.date)
            .map { ($0.key, $0.value.sorted { $0.hourSort < $1.hourSort }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        Screen(title: "Neues", subtitle: model.upcomingChanges.isEmpty ? "Alles nach Plan" : "\(model.upcomingChanges.count) Planänderungen") {
            VStack(spacing: 12) {
                let openLetters = model.letters.filter(\.needsAction)
                if !openLetters.isEmpty {
                    SectionHeader(title: "Zu bestätigen", trailing: "\(openLetters.count)")
                    ForEach(openLetters) { letter in
                        NavigationLink(value: letter) { LetterRow(letter: letter) }
                            .buttonStyle(.plain)
                    }
                    SectionHeader(title: "Stundenplan").padding(.top, 8)
                }
                if groupedChanges.isEmpty {
                    EmptyStateCard(icon: "checkmark.seal.fill", title: "Keine Änderungen",
                                   message: "Alle Stunden finden wie geplant statt. Du bekommst eine Mitteilung, sobald sich etwas ändert.")
                } else {
                    ForEach(groupedChanges, id: \.date) { group in
                        SectionHeader(title: SchoolCalendar.relativeLabel(group.date),
                                      trailing: SchoolCalendar.longWeekday(group.date))
                        ForEach(group.lessons) { lesson in
                            LessonCard(lesson: lesson)
                        }
                    }
                }

                if !model.history.isEmpty {
                    SectionHeader(title: "Verlauf", trailing: "\(model.history.count)")
                        .padding(.top, 12)
                    LazyVStack(spacing: 8) {
                        ForEach(model.history.prefix(60)) { event in
                            HistoryRow(event: event)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Letter.self) { LetterDetailView(letter: $0) }
        .toolbar {
            if !model.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Mehr", systemImage: "ellipsis") {
                        Button("Verlauf löschen", systemImage: "trash", role: .destructive) {
                            withAnimation { model.clearHistory() }
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let event: ChangeEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.icon)
                .font(.title3)
                .foregroundStyle(event.kind.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayTitle).font(.subheadline.weight(.semibold))
                Text(event.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                Text(event.detectedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
    }
}

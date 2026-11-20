import SwiftUI

/// Farbiger, leicht bewegter Hintergrund – Liquid Glass braucht etwas, das es brechen kann.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + 0.12 * sin(t / 6), 0.45 + 0.1 * cos(t / 7)], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: scheme == .dark ? darkColors : lightColors
            )
        }
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(red: 0.80, green: 0.88, blue: 1.00), Color(red: 0.87, green: 0.84, blue: 1.00), Color(red: 1.00, green: 0.87, blue: 0.88),
            Color(red: 0.75, green: 0.93, blue: 0.97), Color(red: 0.93, green: 0.94, blue: 1.00), Color(red: 0.99, green: 0.92, blue: 0.82),
            Color(red: 0.80, green: 0.95, blue: 0.87), Color(red: 0.86, green: 0.89, blue: 1.00), Color(red: 0.90, green: 0.84, blue: 0.99),
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.05, green: 0.10, blue: 0.28), Color(red: 0.16, green: 0.08, blue: 0.32), Color(red: 0.30, green: 0.07, blue: 0.20),
            Color(red: 0.02, green: 0.20, blue: 0.28), Color(red: 0.07, green: 0.08, blue: 0.16), Color(red: 0.28, green: 0.14, blue: 0.06),
            Color(red: 0.02, green: 0.22, blue: 0.16), Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.18, green: 0.07, blue: 0.30),
        ]
    }
}

extension ChangeEvent.Kind {
    var color: Color {
        switch self {
        case .cancelled: .red
        case .substitution: .orange
        case .roomChange: .purple
        case .added, .restored: .green
        case .changed: .blue
        case .newExam: .pink
        case .newHomework: .teal
        case .newMessage: .accentColor
        case .newLetter: .orange
        case .tileChanged: .pink
        case .newEvent, .eventChanged: .red
        case .newGrade: .indigo
        case .newAbsence: .orange
        case .exemptionDecided: .green
        case .newInvoice: .brown
        case .alldayNote: .teal
        case .parentTalk: .purple
        }
    }

    var icon: String {
        switch self {
        case .cancelled: "xmark.circle.fill"
        case .substitution: "arrow.triangle.swap"
        case .roomChange: "door.left.hand.open"
        case .added: "plus.circle.fill"
        case .restored: "arrow.uturn.backward.circle.fill"
        case .changed: "pencil.circle.fill"
        case .newExam: "doc.text.fill"
        case .newHomework: "book.closed.fill"
        case .newMessage: "bubble.left.fill"
        case .newLetter: "envelope.badge.fill"
        case .tileChanged: "pin.fill"
        case .newEvent: "calendar.badge.plus"
        case .eventChanged: "calendar.badge.exclamationmark"
        case .newGrade: "star.fill"
        case .newAbsence: "bed.double.fill"
        case .exemptionDecided: "checkmark.seal.fill"
        case .newInvoice: "eurosign.circle.fill"
        case .alldayNote: "figure.and.child.holdinghands"
        case .parentTalk: "person.2.fill"
        }
    }
}

extension View {
    /// Glas-Karte; bei Änderungen leicht in der Statusfarbe getönt.
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.22)) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}

extension Color {
    /// Farbe für Arbeiten / Leistungsnachweise im Wochenplan.
    static let examColor = Color.pink
}

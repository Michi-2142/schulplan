import SwiftUI

extension LessonState {
    var color: Color {
        switch self {
        case .regular: .blue
        case .cancelled: .red
        case .substitution: .orange
        case .roomChange: .purple
        case .added: .green
        }
    }

    var label: String {
        switch self {
        case .regular: "Regulär"
        case .cancelled: "Entfall"
        case .substitution: "Vertretung"
        case .roomChange: "Raum"
        case .added: "Zusatz"
        }
    }

    var icon: String {
        switch self {
        case .regular: "checkmark.circle"
        case .cancelled: "xmark.circle.fill"
        case .substitution: "arrow.triangle.swap"
        case .roomChange: "door.left.hand.open"
        case .added: "plus.circle.fill"
        }
    }
}

enum SubjectColor {
    private static let palette: [Color] = [.blue, .indigo, .teal, .cyan, .mint, .green, .pink, .purple, .orange, .brown]

    /// Stabile Farbe je Fach (gleiches Fach = gleiche Farbe über alle Ansichten).
    static func color(for subject: String) -> Color {
        let sum = subject.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}

import SwiftUI
import UIKit

/// HTML aus Schulmanager (Elternbriefe, Pinnwand, Nachrichten) lesbar machen.
enum HTML {
    // MARK: Klartext

    /// Tags entfernen, Zeilenumbrüche erhalten, Sonderzeichen dekodieren, Leerraum aufräumen.
    /// Idempotent: bereits bereinigter Text bleibt unverändert.
    static func plainText(_ text: String) -> String {
        var result = text
        if result.contains("<") {
            result = result
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "</(p|div|h[1-6]|li|tr)>", with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return tidy(decodeEntities(result))
    }

    /// Zeilen trimmen, mehr als eine Leerzeile zusammenfassen.
    static func tidy(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespaces) }
        var output: [String] = []
        for line in lines {
            if line.isEmpty, output.last?.isEmpty ?? true { continue }
            output.append(line)
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let entities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "euro": "€", "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "aacute": "á", "agrave": "à", "acirc": "â", "ccedil": "ç",
        "oacute": "ó", "ograve": "ò", "ocirc": "ô", "iacute": "í", "icirc": "î", "uacute": "ú", "ucirc": "û",
        "Eacute": "É", "ntilde": "ñ", "copy": "©", "reg": "®", "trade": "™", "deg": "°", "sect": "§", "para": "¶",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³",
        "shy": "", "zwnj": "", "zwj": "", "ensp": " ", "emsp": " ", "thinsp": " ",
    ]

    /// `&uuml;`, `&#252;` und `&#xFC;` → „ü“. Unbekanntes bleibt stehen.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            guard let semicolon = after.prefix(12).firstIndex(of: ";") else {
                result += "&"
                rest = after
                continue
            }
            let name = String(after[..<semicolon])
            if let decoded = decode(name) {
                result += decoded
                rest = after[after.index(after: semicolon)...]
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }

    private static func decode(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return entities[name]
    }

    // MARK: Formatierter Text

    /// HTML als formatierter Text: Absätze, fett/kursiv, Listen, Links – in der Systemschrift
    /// und mit Systemfarben, damit es im Dunkelmodus passt.
    @MainActor
    static func attributed(_ html: String) -> AttributedString? {
        guard html.contains("<") || html.contains("&") else { return nil }
        // Absätze und Listen als Text ausschreiben – die Abstände/Listenzeichen des HTML-Imports
        // gehen beim Übertragen in die Systemschrift sonst verloren.
        let prepared = html
            .replacingOccurrences(of: "<p[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "<br><br>", options: .caseInsensitive)
            .replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</li>", with: "<br>", options: .caseInsensitive)
            .replacingOccurrences(of: "</?(ul|ol)[^>]*>", with: "<br>", options: [.regularExpression, .caseInsensitive])
        let wrapped = "<meta charset=\"utf-8\"><div>\(prepared)</div>"
        guard let data = wrapped.data(using: .utf8),
              let source = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return nil }

        var output = AttributedString()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            var piece = AttributedString(source.attributedSubstring(from: range).string)
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            var font = Font.body
            if traits.contains(.traitBold) { font = font.bold() }
            if traits.contains(.traitItalic) { font = font.italic() }
            piece.font = font
            if let link = attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap(URL.init(string:)) {
                piece.link = link
            }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { piece.underlineStyle = .single }
            output += piece
        }
        return tidy(output)
    }

    /// Leerraum im formatierten Text aufräumen, ohne die Formatierung zu verlieren.
    private static func tidy(_ text: AttributedString) -> AttributedString {
        var text = text
        // Mehrfache Leerzeilen und Leerzeichen am Zeilenanfang entfernen.
        while let range = text.range(of: "\n\n\n") { text.replaceSubrange(range, with: AttributedString("\n\n")) }
        while let range = text.range(of: "\n ") { text.replaceSubrange(range, with: AttributedString("\n")) }
        while let first = text.characters.first, first.isWhitespace { text.removeSubrange(text.startIndex..<text.index(afterCharacter: text.startIndex)) }
        while let last = text.characters.last, last.isWhitespace {
            text.removeSubrange(text.index(beforeCharacter: text.endIndex)..<text.endIndex)
        }
        return text
    }
}

/// Zeigt HTML formatiert an; fällt auf den bereinigten Klartext zurück.
struct RichText: View {
    let html: String
    var font: Font = .body

    @State private var attributed: AttributedString?

    var body: some View {
        Group {
            if let attributed {
                Text(attributed)
            } else {
                Text(HTML.plainText(html))
            }
        }
        .font(font)
        .lineSpacing(3)
        .textSelection(.enabled)
        .tint(.accentColor)
        .task(id: html) { attributed = HTML.attributed(html) }
    }
}

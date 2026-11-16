import Foundation

/// Typfreies JSON. Die Schulmanager-API ist undokumentiert und liefert Felder mal als
/// Zahl, mal als String, mal als Objekt. Wir lesen deshalb tolerant statt strikt.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self, let value = dict[key] else { return nil }
        if case .null = value { return nil }
        return value
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let list) = self, list.indices.contains(index) else { return nil }
        return list[index]
    }

    /// String-Darstellung; Zahlen werden umgewandelt, leere Strings zählen als fehlend.
    var string: String? {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .int(let value): return String(value)
        case .double(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        default: return nil
        }
    }

    var array: [JSONValue]? {
        if case .array(let list) = self { return list }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    init(_ optional: String?) { self = optional.map { .string($0) } ?? .null }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
}

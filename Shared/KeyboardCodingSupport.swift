import Foundation

/// Helpers that make every model tolerant of hand-edited / partially corrupted
/// JSON.  A keyboard extension must never fail to launch because one field is
/// the wrong type or missing, so every property read goes through one of these
/// and falls back to a sane default instead of throwing.
extension KeyedDecodingContainer {

    /// Returns the decoded value, or `fallback` when the key is missing,
    /// `null`, or of an unexpected type.
    func keyraValue<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        if let value = try? decodeIfPresent(T.self, forKey: key) {
            return value
        }
        return fallback
    }

    /// Returns the decoded value or `nil` when missing / null / wrong type.
    func keyraOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        if let decoded = try? decodeIfPresent(type, forKey: key) {
            return decoded
        }
        return nil
    }

    /// Reads a numeric value that may have been written as a number or as a
    /// string (e.g. `"width": "1.5"`).
    func keyraDouble(_ key: Key, _ fallback: Double) -> Double {
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            if let number = Double(string.trimmingCharacters(in: .whitespaces)) {
                return number
            }
        }
        return fallback
    }

    /// Reads an integer that may have been written as a number or a string.
    func keyraInt(_ key: Key, _ fallback: Int) -> Int {
        if let number = try? decodeIfPresent(Int.self, forKey: key) {
            return number
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(number)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            if let number = Int(string.trimmingCharacters(in: .whitespaces)) {
                return number
            }
        }
        return fallback
    }

    /// Reads a boolean that may have been written as `true`, `"true"`, or `1`.
    func keyraBool(_ key: Key, _ fallback: Bool) -> Bool {
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) {
            return flag
        }
        if let number = try? decodeIfPresent(Int.self, forKey: key) {
            return number != 0
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            switch string.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return fallback
            }
        }
        return fallback
    }

    /// Reads a UUID that may be missing (a fresh one is generated) or malformed
    /// (a fresh one is generated as well — duplicate ids are repaired later).
    func keyraUUID(_ key: Key) -> UUID {
        if let identifier = try? decodeIfPresent(UUID.self, forKey: key) {
            return identifier
        }
        if let string = try? decodeIfPresent(String.self, forKey: key),
           let identifier = UUID(uuidString: string.trimmingCharacters(in: .whitespaces)) {
            return identifier
        }
        return UUID()
    }

    /// Reads a UUID encoded as a plain string, returning `nil` if unusable.
    func keyraOptionalUUID(_ key: Key) -> UUID? {
        if let identifier = try? decodeIfPresent(UUID.self, forKey: key) {
            return identifier
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return UUID(uuidString: string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Reads an optional non-empty string (empty strings are treated as absent).
    func keyraNonEmptyString(_ key: Key) -> String? {
        guard let string = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return string.isEmpty ? nil : string
    }
}

/// Shared JSON encoder / decoder configuration so that what the app writes is
/// exactly what the keyboard reads (sorted keys, pretty printed, UTF-8).
enum KeyboardJSON {

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func encodeToString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder().decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return decode(type, from: data)
    }
}

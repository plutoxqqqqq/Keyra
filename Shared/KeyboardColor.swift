import Foundation

/// A colour that serialises to a human readable hex string (`#RRGGBB` /
/// `#RRGGBBAA`) so exported keyboard JSON stays readable and hand-editable.
///
/// Decoding is deliberately *lenient*: keyboard configuration may come from a
/// file the user hand-edited, and a malformed colour must never be able to take
/// the keyboard down.  Strict validation happens in `JSONImportExport` where a
/// human is watching and can be told exactly what is wrong.
struct KeyboardColor: Codable, Equatable, Hashable {

    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = KeyboardColor.clampUnit(red)
        self.green = KeyboardColor.clampUnit(green)
        self.blue = KeyboardColor.clampUnit(blue)
        self.alpha = KeyboardColor.clampUnit(alpha)
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, with or without a leading
    /// `#` and with an optional `0x` prefix.  Returns `nil` for anything else.
    init?(hex string: String) {
        var body = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("#") { body.removeFirst() }
        if body.hasPrefix("0x") || body.hasPrefix("0X") { body.removeFirst(2) }

        let expanded: String
        switch body.count {
        case 3, 4:
            var doubled = ""
            for character in body { doubled.append(character); doubled.append(character) }
            expanded = doubled
        case 6, 8:
            expanded = body
        default:
            return nil
        }

        guard let value = UInt64(expanded, radix: 16) else { return nil }

        if expanded.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0,
                alpha: Double(value & 0xFF) / 255.0
            )
        }
    }

    // MARK: - Codable (lenient)

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let hex = try? container.decode(String.self), let parsed = KeyboardColor(hex: hex) {
                self = parsed
                return
            }
            // Allow [r, g, b] / [r, g, b, a] component arrays.
            if let components = try? container.decode([Double].self), components.count >= 3 {
                self.init(
                    red: components[0],
                    green: components[1],
                    blue: components[2],
                    alpha: components.count > 3 ? components[3] : 1
                )
                return
            }
            if let components = try? container.decode([Int].self), components.count >= 3 {
                self.init(
                    red: Double(components[0]) / 255.0,
                    green: Double(components[1]) / 255.0,
                    blue: Double(components[2]) / 255.0,
                    alpha: components.count > 3 ? Double(components[3]) / 255.0 : 1
                )
                return
            }
        }
        self = KeyboardColor.placeholder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    // MARK: - Output

    var hexString: String {
        let r = Int((red * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue * 255.0).rounded())
        if alpha < 0.999 {
            let a = Int((alpha * 255.0).rounded())
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// All components clamped into 0...1 — used by the sanitiser.
    func clamped() -> KeyboardColor {
        KeyboardColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// `0.2126R + 0.7152G + 0.0722B`, used to pick readable on-colours.
    var perceivedLuminance: Double {
        (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    var isPerceptuallyDark: Bool { perceivedLuminance < 0.5 }

    // MARK: - Constants

    /// Used when decoding a colour that cannot be parsed at all.
    static let placeholder = KeyboardColor(red: 0.5, green: 0.5, blue: 0.5)

    static let clear = KeyboardColor(red: 0, green: 0, blue: 0, alpha: 0)
    static let black = KeyboardColor(red: 0, green: 0, blue: 0)
    static let white = KeyboardColor(red: 1, green: 1, blue: 1)

    // MARK: - Helpers

    static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        if value < 0 { return 0 }
        if value > 1 { return 1 }
        return value
    }
}

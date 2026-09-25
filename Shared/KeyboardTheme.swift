import Foundation

/// Font weight is stored as a string so the JSON stays portable; the mapping to
/// `Font.Weight` / `UIFont.Weight` lives in the presentation layer.
enum KeyboardFontWeight: String, Codable, CaseIterable, Identifiable {
    case light, regular, medium, semibold, bold, heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        }
    }

    /// Approximate numeric weight, used for measuring text in the preview.
    var numericValue: Double {
        switch self {
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        }
    }
}

/// Visual appearance of the keyboard.  Themes are stored independently from
/// layouts so the same layout can be re-skinned without being edited.
struct KeyboardTheme: Codable, Equatable, Identifiable {

    var id: UUID
    var name: String

    // Colours
    var background: KeyboardColor
    var keyColor: KeyboardColor
    var specialKeyColor: KeyboardColor
    var pressedKeyColor: KeyboardColor
    var textColor: KeyboardColor
    var specialTextColor: KeyboardColor
    var borderColor: KeyboardColor

    // Geometry / typography
    var borderWidth: Double
    var cornerRadius: Double
    var keySpacing: Double
    var rowSpacing: Double
    var keyShadowRadius: Double
    var keyShadowOpacity: Double
    var keyOpacity: Double
    var fontSize: Double
    var fontWeight: KeyboardFontWeight
    var pressedScale: Double
    var isDarkAppearance: Bool

    init(
        id: UUID = UUID(),
        name: String,
        background: KeyboardColor,
        keyColor: KeyboardColor,
        specialKeyColor: KeyboardColor,
        pressedKeyColor: KeyboardColor,
        textColor: KeyboardColor,
        specialTextColor: KeyboardColor? = nil,
        borderColor: KeyboardColor = .clear,
        borderWidth: Double = 0,
        cornerRadius: Double = 6,
        keySpacing: Double = 6,
        rowSpacing: Double = 9,
        keyShadowRadius: Double = 0,
        keyShadowOpacity: Double = 0,
        keyOpacity: Double = 1,
        fontSize: Double = 22,
        fontWeight: KeyboardFontWeight = .regular,
        pressedScale: Double = 0.96,
        isDarkAppearance: Bool = false
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.keyColor = keyColor
        self.specialKeyColor = specialKeyColor
        self.pressedKeyColor = pressedKeyColor
        self.textColor = textColor
        self.specialTextColor = specialTextColor ?? textColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.keySpacing = keySpacing
        self.rowSpacing = rowSpacing
        self.keyShadowRadius = keyShadowRadius
        self.keyShadowOpacity = keyShadowOpacity
        self.keyOpacity = keyOpacity
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.pressedScale = pressedScale
        self.isDarkAppearance = isDarkAppearance
    }

    // MARK: - Codable (lenient, every field optional)

    private enum CodingKeys: String, CodingKey {
        case id, name
        case background, keyColor, specialKeyColor, pressedKeyColor
        case textColor, specialTextColor, borderColor
        case borderWidth, cornerRadius, keySpacing, rowSpacing
        case keyShadowRadius, keyShadowOpacity, keyOpacity
        case fontSize, fontWeight, pressedScale, isDarkAppearance
        // Legacy / alias keys accepted on import.
        case backgroundColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = KeyboardTheme.dark()

        id = container.keyraValue(.id, UUID())
        name = container.keyraValue(.name, "Untitled Theme")

        background = container.keyraValue(.background, fallback.background)
        if let alias = container.keyraOptional(KeyboardColor.self, forKey: .backgroundColor) {
            background = alias
        }

        keyColor = container.keyraValue(.keyColor, fallback.keyColor)
        specialKeyColor = container.keyraValue(.specialKeyColor, fallback.specialKeyColor)
        pressedKeyColor = container.keyraValue(.pressedKeyColor, fallback.pressedKeyColor)
        textColor = container.keyraValue(.textColor, fallback.textColor)
        specialTextColor = container.keyraValue(.specialTextColor, fallback.textColor)
        borderColor = container.keyraValue(.borderColor, fallback.borderColor)

        borderWidth = container.keyraValue(.borderWidth, fallback.borderWidth)
        cornerRadius = container.keyraValue(.cornerRadius, fallback.cornerRadius)
        keySpacing = container.keyraValue(.keySpacing, fallback.keySpacing)
        rowSpacing = container.keyraValue(.rowSpacing, fallback.rowSpacing)
        keyShadowRadius = container.keyraValue(.keyShadowRadius, fallback.keyShadowRadius)
        keyShadowOpacity = container.keyraValue(.keyShadowOpacity, fallback.keyShadowOpacity)
        keyOpacity = container.keyraValue(.keyOpacity, fallback.keyOpacity)
        fontSize = container.keyraValue(.fontSize, fallback.fontSize)
        fontWeight = container.keyraValue(.fontWeight, fallback.fontWeight)
        pressedScale = container.keyraValue(.pressedScale, fallback.pressedScale)
        isDarkAppearance = container.keyraValue(.isDarkAppearance, fallback.isDarkAppearance)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(background, forKey: .background)
        try container.encode(keyColor, forKey: .keyColor)
        try container.encode(specialKeyColor, forKey: .specialKeyColor)
        try container.encode(pressedKeyColor, forKey: .pressedKeyColor)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(specialTextColor, forKey: .specialTextColor)
        try container.encode(borderColor, forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(keySpacing, forKey: .keySpacing)
        try container.encode(rowSpacing, forKey: .rowSpacing)
        try container.encode(keyShadowRadius, forKey: .keyShadowRadius)
        try container.encode(keyShadowOpacity, forKey: .keyShadowOpacity)
        try container.encode(keyOpacity, forKey: .keyOpacity)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontWeight, forKey: .fontWeight)
        try container.encode(pressedScale, forKey: .pressedScale)
        try container.encode(isDarkAppearance, forKey: .isDarkAppearance)
    }

    // MARK: - Convenience

    func withName(_ newName: String) -> KeyboardTheme {
        var copy = self
        copy.name = newName
        return copy
    }

    /// A fresh copy with new identity, ready to be stored as a user theme.
    func duplicated(named newName: String? = nil) -> KeyboardTheme {
        var copy = self
        copy.id = UUID()
        copy.name = newName ?? "\(name) Copy"
        return copy
    }

    static func == (lhs: KeyboardTheme, rhs: KeyboardTheme) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.background == rhs.background
            && lhs.keyColor == rhs.keyColor
            && lhs.specialKeyColor == rhs.specialKeyColor
            && lhs.pressedKeyColor == rhs.pressedKeyColor
            && lhs.textColor == rhs.textColor
            && lhs.specialTextColor == rhs.specialTextColor
            && lhs.borderColor == rhs.borderColor
            && lhs.borderWidth == rhs.borderWidth
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.keySpacing == rhs.keySpacing
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.keyShadowRadius == rhs.keyShadowRadius
            && lhs.keyShadowOpacity == rhs.keyShadowOpacity
            && lhs.keyOpacity == rhs.keyOpacity
            && lhs.fontSize == rhs.fontSize
            && lhs.fontWeight == rhs.fontWeight
            && lhs.pressedScale == rhs.pressedScale
            && lhs.isDarkAppearance == rhs.isDarkAppearance
    }
}

// MARK: - Built-in themes

extension KeyboardTheme {

    static func light() -> KeyboardTheme {
        KeyboardTheme(
            name: "Light",
            background: KeyboardColor(red: 0.82, green: 0.84, blue: 0.87),
            keyColor: KeyboardColor(red: 1, green: 1, blue: 1),
            specialKeyColor: KeyboardColor(red: 0.68, green: 0.72, blue: 0.77),
            pressedKeyColor: KeyboardColor(red: 0.60, green: 0.76, blue: 1.0),
            textColor: KeyboardColor(red: 0.05, green: 0.06, blue: 0.09),
            borderColor: KeyboardColor(red: 0, green: 0, blue: 0, alpha: 0.10),
            borderWidth: 0,
            cornerRadius: 6,
            keySpacing: 6,
            rowSpacing: 10,
            keyShadowRadius: 0,
            keyShadowOpacity: 0,
            fontSize: 22,
            fontWeight: .regular,
            pressedScale: 0.96,
            isDarkAppearance: false
        )
    }

    static func dark() -> KeyboardTheme {
        KeyboardTheme(
            name: "Dark",
            background: KeyboardColor(red: 0.13, green: 0.14, blue: 0.16),
            keyColor: KeyboardColor(red: 0.35, green: 0.36, blue: 0.39),
            specialKeyColor: KeyboardColor(red: 0.24, green: 0.25, blue: 0.28),
            pressedKeyColor: KeyboardColor(red: 0.55, green: 0.58, blue: 0.63),
            textColor: KeyboardColor(red: 1, green: 1, blue: 1),
            borderColor: KeyboardColor(red: 0, green: 0, blue: 0, alpha: 0.35),
            borderWidth: 0,
            cornerRadius: 6,
            keySpacing: 6,
            rowSpacing: 10,
            keyShadowRadius: 0,
            keyShadowOpacity: 0,
            fontSize: 22,
            fontWeight: .regular,
            pressedScale: 0.96,
            isDarkAppearance: true
        )
    }

    static func purple() -> KeyboardTheme {
        KeyboardTheme(
            name: "Purple",
            background: KeyboardColor(hex: "#1B1030") ?? .black,
            keyColor: KeyboardColor(hex: "#3E2A6B") ?? .black,
            specialKeyColor: KeyboardColor(hex: "#2A1B4A") ?? .black,
            pressedKeyColor: KeyboardColor(hex: "#8B5CF6") ?? .black,
            textColor: KeyboardColor(hex: "#F5F3FF") ?? .white,
            borderColor: KeyboardColor(hex: "#8B5CF655") ?? .clear,
            borderWidth: 0.5,
            cornerRadius: 9,
            keySpacing: 6,
            rowSpacing: 10,
            keyShadowRadius: 4,
            keyShadowOpacity: 0.35,
            fontSize: 22,
            fontWeight: .medium,
            pressedScale: 0.94,
            isDarkAppearance: true
        )
    }

    static func minimal() -> KeyboardTheme {
        KeyboardTheme(
            name: "Minimal",
            background: KeyboardColor(red: 0.97, green: 0.97, blue: 0.98),
            keyColor: KeyboardColor(red: 1, green: 1, blue: 1),
            specialKeyColor: KeyboardColor(red: 0.93, green: 0.93, blue: 0.95),
            pressedKeyColor: KeyboardColor(red: 0.84, green: 0.88, blue: 0.96),
            textColor: KeyboardColor(red: 0.10, green: 0.11, blue: 0.13),
            borderColor: KeyboardColor(red: 0, green: 0, blue: 0, alpha: 0.08),
            borderWidth: 0.5,
            cornerRadius: 4,
            keySpacing: 8,
            rowSpacing: 12,
            keyShadowRadius: 0,
            keyShadowOpacity: 0,
            fontSize: 21,
            fontWeight: .light,
            pressedScale: 0.97,
            isDarkAppearance: false
        )
    }

    /// Fresh instances every time so ids are stable only inside a configuration.
    static var builtIn: [KeyboardTheme] {
        [light(), dark(), purple(), minimal()]
    }

    static var defaultTheme: KeyboardTheme { dark() }
}

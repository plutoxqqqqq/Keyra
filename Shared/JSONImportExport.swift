import Foundation
import CoreFoundation

// MARK: - Errors

enum KeyboardImportError: LocalizedError, Equatable {

    case notJSON(String)
    case unsupportedShape(String)
    case missingLayout
    case emptyLayout(String)
    case invalidField(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .notJSON(let reason):
            return "This file is not valid JSON. (\(reason))"
        case .unsupportedShape(let reason):
            return "This JSON does not look like a Keyra keyboard. (\(reason))"
        case .missingLayout:
            return "This file does not contain a keyboard layout."
        case .emptyLayout(let name):
            return "“\(name)” has no rows or no keys, so there would be nothing to type."
        case .invalidField(let path, let reason):
            return "Problem at \(path): \(reason)"
        }
    }
}

/// What a successful import produced.
struct ImportedLayout {
    var layout: KeyboardLayout
    /// A theme travelling with the keyboard, if the file carried one.
    var theme: KeyboardTheme?
    var warnings: [String]
    var sourceDescription: String
}

struct ImportedConfiguration {
    var configuration: KeyboardConfiguration
    var warnings: [String]
}

// MARK: - Envelope

/// The wrapper written by “Export”. Human readable on purpose: a keyboard can be
/// shared as a single JSON file that a person can read and edit.
struct KeyboardExportEnvelope: Codable {

    static let currentFormatVersion = 1

    var keyraFormatVersion: Int
    /// "layout" | "configuration" | "theme"
    var kind: String
    var app: String
    var exportedAt: Date
    var layout: KeyboardLayout?
    var configuration: KeyboardConfiguration?
    var theme: KeyboardTheme?

    private enum CodingKeys: String, CodingKey {
        case keyraFormatVersion, kind, app, exportedAt, layout, configuration, theme
    }

    init(
        kind: String,
        layout: KeyboardLayout? = nil,
        configuration: KeyboardConfiguration? = nil,
        theme: KeyboardTheme? = nil,
        exportedAt: Date = Date()
    ) {
        self.keyraFormatVersion = KeyboardExportEnvelope.currentFormatVersion
        self.kind = kind
        self.app = "Keyra"
        self.exportedAt = exportedAt
        self.layout = layout
        self.configuration = configuration
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyraFormatVersion = container.keyraInt(.keyraFormatVersion, 0)
        kind = container.keyraValue(.kind, "")
        app = container.keyraValue(.app, "unknown")
        exportedAt = container.keyraOptional(Date.self, forKey: .exportedAt) ?? Date(timeIntervalSince1970: 0)
        layout = container.keyraOptional(KeyboardLayout.self, forKey: .layout)
        configuration = container.keyraOptional(KeyboardConfiguration.self, forKey: .configuration)
        theme = container.keyraOptional(KeyboardTheme.self, forKey: .theme)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyraFormatVersion, forKey: .keyraFormatVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(app, forKey: .app)
        try container.encode(exportedAt, forKey: .exportedAt)
        if let layout { try container.encode(layout, forKey: .layout) }
        if let configuration { try container.encode(configuration, forKey: .configuration) }
        if let theme { try container.encode(theme, forKey: .theme) }
    }
}

// MARK: - Import / export

enum JSONImportExport {

    // MARK: Export

    static func exportString(_ envelope: KeyboardExportEnvelope) -> String {
        guard let data = try? KeyboardJSON.encoder().encode(envelope),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func exportData(_ envelope: KeyboardExportEnvelope) -> Data {
        (try? KeyboardJSON.encoder().encode(envelope)) ?? Data()
    }

    static func exportLayout(_ layout: KeyboardLayout) -> String {
        exportLayout(layout, theme: nil)
    }

    /// Exports a keyboard, optionally with the look it was designed in, so a
    /// single file carries everything needed to reproduce it elsewhere.
    static func exportLayout(_ layout: KeyboardLayout, theme: KeyboardTheme?) -> String {
        exportString(KeyboardExportEnvelope(kind: "layout", layout: layout, theme: theme))
    }

    static func exportConfiguration(_ configuration: KeyboardConfiguration) -> String {
        exportString(KeyboardExportEnvelope(kind: "configuration", configuration: configuration))
    }

    static func exportTheme(_ theme: KeyboardTheme) -> String {
        exportString(KeyboardExportEnvelope(kind: "theme", theme: theme))
    }

    /// A safe, descriptive file name such as `keyra-math-keyboard.json`.
    static func fileName(for layout: KeyboardLayout) -> String {
        var slug = layout.name.lowercased()
        var allowed = ""
        for character in slug {
            if character.isLetter || character.isNumber { allowed.append(character) }
            else if character == " " || character == "-" || character == "_" { allowed.append("-") }
        }
        while allowed.contains("--") { allowed = allowed.replacingOccurrences(of: "--", with: "-") }
        slug = allowed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "layout" }
        return "keyra-\(slug).json"
    }

    static func fileName(forConfiguration configuration: KeyboardConfiguration) -> String {
        "keyra-configuration-\(configuration.generation).json"
    }

    // MARK: Loose recovery (used by the store when a file is not a full config)

    /// Best-effort decode of *something* layout shaped. Never throws: returns
    /// `nil` when the bytes are not usable, so the caller can fall back safely.
    static func decodeLooseLayout(from data: Data) -> KeyboardLayout? {
        if let envelope = KeyboardJSON.decode(KeyboardExportEnvelope.self, from: data) {
            if let layout = envelope.layout { return layout }
            if let configuration = envelope.configuration { return configuration.activeLayout }
        }
        if let layout = KeyboardJSON.decode(KeyboardLayout.self, from: data) {
            return layout
        }
        if let layouts = KeyboardJSON.decode([KeyboardLayout].self, from: data), let first = layouts.first {
            return first
        }
        return nil
    }

    // MARK: Strict import

    /// Validates the raw JSON in detail (so the user is told exactly what is
    /// wrong) and then decodes it into the model.
    static func importLayout(from data: Data) throws -> ImportedLayout {
        var importedThemeFromConfiguration: KeyboardTheme?
        let root = try parseRoot(data)

        var warnings: [String] = []
        var payload: [String: Any]?
        var description = "keyboard layout"
        var themePayload: [String: Any]?

        if let dictionary = root as? [String: Any] {
            if let kind = dictionary["kind"] as? String, kind.lowercased() == "theme" {
                throw KeyboardImportError.unsupportedShape("this file contains a theme, not a keyboard")
            }
            if let nested = dictionary["layout"] as? [String: Any] {
                payload = nested
                description = "exported keyboard layout"
                themePayload = dictionary["theme"] as? [String: Any]
            } else if let nested = dictionary["configuration"] as? [String: Any],
                      let layouts = nested["layouts"] as? [[String: Any]] {
                // Importing a whole configuration: take the active one.
                let active = (nested["activeLayoutName"] as? String) ?? (nested["activeLayout"] as? String)
                var chosen = layouts.first
                if let active {
                    for candidate in layouts where (candidate["name"] as? String)?.caseInsensitiveCompare(active) == .orderedSame {
                        chosen = candidate
                        break
                    }
                }
                payload = chosen
                description = "keyboard taken from an exported configuration"
                if layouts.count > 1 {
                    warnings.append("That file contained \(layouts.count) keyboards; “\((chosen?["name"] as? String) ?? "the first one")” was imported. Export a single keyboard to move just one.")
                }
                // Carry the configuration's active theme along with its keyboard.
                if let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: []),
                   let decoded = KeyboardJSON.decode(KeyboardConfiguration.self, from: nestedData) {
                    var theme = decoded.activeTheme
                    theme.id = UUID()
                    importedThemeFromConfiguration = KeyboardValidator.sanitizeTheme(theme)
                }
            } else {
                payload = dictionary
                themePayload = dictionary["theme"] as? [String: Any]
            }
        } else if let array = root as? [Any] {
            if let first = array.first as? [String: Any] {
                payload = first
                description = "first keyboard from a JSON array"
                if array.count > 1 {
                    warnings.append("That file contained \(array.count) keyboards; only the first was imported.")
                }
            }
        }

        guard let payload else {
            throw KeyboardImportError.missingLayout
        }

        try validateLayoutDictionary(payload, path: "layout", warnings: &warnings)
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw KeyboardImportError.unsupportedShape("the keyboard could not be re-encoded")
        }

        // A theme may travel with the keyboard (either next to it, or as the
        // active theme of an exported configuration).
        var importedTheme = importedThemeFromConfiguration
        if importedTheme == nil, let themePayload {
            try validateThemeDictionary(themePayload, path: "theme", warnings: &warnings)
            if let themeData = try? JSONSerialization.data(withJSONObject: themePayload, options: []),
               var theme = KeyboardJSON.decode(KeyboardTheme.self, from: themeData) {
                theme.id = UUID()
                importedTheme = KeyboardValidator.sanitizeTheme(theme)
            } else {
                warnings.append("The theme in this file could not be read, so your current theme was kept.")
            }
        }

        var layout = KeyboardJSON.decode(KeyboardLayout.self, from: payloadData) ?? KeyboardLayout(name: "Imported")
        layout.id = UUID() // never collide with an existing layout
        var scratchIssues: [KeyboardIssue] = []
        layout = KeyboardValidator.sanitizeLayout(layout, issues: &scratchIssues)

        if layout.rows.isEmpty {
            throw KeyboardImportError.emptyLayout(layout.name)
        }

        warnings.append(contentsOf: scratchIssues.map { "\($0.title): \($0.detail)" })

        return ImportedLayout(
            layout: layout,
            theme: importedTheme,
            warnings: warnings,
            sourceDescription: description
        )
    }

    static func importTheme(from data: Data) throws -> (theme: KeyboardTheme, warnings: [String]) {
        let root = try parseRoot(data)
        var warnings: [String] = []
        guard let dictionary = root as? [String: Any] else {
            throw KeyboardImportError.unsupportedShape("a theme must be a JSON object")
        }
        let payload = (dictionary["theme"] as? [String: Any]) ?? dictionary
        try validateThemeDictionary(payload, path: "theme", warnings: &warnings)
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              var theme = KeyboardJSON.decode(KeyboardTheme.self, from: payloadData) else {
            throw KeyboardImportError.unsupportedShape("the theme could not be decoded")
        }
        theme.id = UUID()
        theme = KeyboardValidator.sanitizeTheme(theme)
        return (theme, warnings)
    }

    static func importConfiguration(from data: Data) throws -> ImportedConfiguration {
        let root = try parseRoot(data)
        var warnings: [String] = []
        guard let dictionary = root as? [String: Any] else {
            throw KeyboardImportError.unsupportedShape("a configuration must be a JSON object")
        }
        let payload = (dictionary["configuration"] as? [String: Any]) ?? dictionary

        guard let layouts = payload["layouts"] as? [[String: Any]], !layouts.isEmpty else {
            throw KeyboardImportError.missingLayout
        }
        for (index, layout) in layouts.enumerated() {
            try validateLayoutDictionary(layout, path: "layouts[\(index)]", warnings: &warnings)
        }
        if let themes = payload["themes"] as? [[String: Any]] {
            for (index, theme) in themes.enumerated() {
                try validateThemeDictionary(theme, path: "themes[\(index)]", warnings: &warnings)
            }
        }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let decoded = KeyboardJSON.decode(KeyboardConfiguration.self, from: payloadData) else {
            throw KeyboardImportError.unsupportedShape("the configuration could not be decoded")
        }

        // Give everything fresh identity so importing never overwrites anything.
        var configuration = decoded
        configuration.layouts = configuration.layouts.map { layout in
            var copy = layout
            copy.id = UUID()
            copy.rows = copy.rows.map { row in
                var rowCopy = row
                rowCopy.id = UUID()
                rowCopy.keys = rowCopy.keys.map { key in
                    var keyCopy = key
                    keyCopy.id = UUID()
                    return keyCopy
                }
                return rowCopy
            }
            return copy
        }

        let repaired = KeyboardValidator.sanitize(configuration)
        warnings.append(contentsOf: repaired.issues.map { "\($0.title): \($0.detail)" })
        return ImportedConfiguration(configuration: repaired.configuration, warnings: warnings)
    }

    // MARK: Private validation

    private static func parseRoot(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw KeyboardImportError.notJSON(error.localizedDescription)
        }
    }

    private static func validateLayoutDictionary(
        _ payload: [String: Any],
        path: String,
        warnings: inout [String]
    ) throws {
        let name = (payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Imported keyboard"

        guard let rawRows = payload["rows"] ?? payload["Rows"] else {
            throw KeyboardImportError.missingLayout
        }
        guard let rows = rawRows as? [Any] else {
            throw KeyboardImportError.invalidField(path: "\(path).rows", reason: "expected an array of rows")
        }
        guard !rows.isEmpty else {
            throw KeyboardImportError.emptyLayout(name)
        }

        var totalKeys = 0
        for (rowIndex, rawRow) in rows.enumerated() {
            let rowPath = "\(path).rows[\(rowIndex)]"
            guard let row = rawRow as? [String: Any] else {
                throw KeyboardImportError.invalidField(path: rowPath, reason: "expected an object")
            }
            if let height = row["height"], number(height) == nil {
                throw KeyboardImportError.invalidField(path: "\(rowPath).height", reason: "expected a number")
            }
            guard let rawKeys = row["keys"] ?? row["Keys"] else {
                throw KeyboardImportError.invalidField(path: "\(rowPath).keys", reason: "expected an array of keys")
            }
            guard let keys = rawKeys as? [Any] else {
                throw KeyboardImportError.invalidField(path: "\(rowPath).keys", reason: "expected an array of keys")
            }
            if keys.isEmpty {
                warnings.append("Row \(rowIndex + 1) has no keys and will be skipped.")
            }
            totalKeys += keys.count

            for (keyIndex, rawKey) in keys.enumerated() {
                let keyPath = "\(rowPath).keys[\(keyIndex)]"
                guard let key = rawKey as? [String: Any] else {
                    throw KeyboardImportError.invalidField(path: keyPath, reason: "expected an object")
                }
                if let label = key["label"], !(label is String) {
                    throw KeyboardImportError.invalidField(path: "\(keyPath).label", reason: "expected a string")
                }
                for dimension in ["width", "height"] {
                    if let value = key[dimension] {
                        guard let number = number(value) else {
                            throw KeyboardImportError.invalidField(path: "\(keyPath).\(dimension)", reason: "expected a number")
                        }
                        guard number.isFinite else {
                            throw KeyboardImportError.invalidField(path: "\(keyPath).\(dimension)", reason: "must be a finite number")
                        }
                        if number <= 0 {
                            throw KeyboardImportError.invalidField(path: "\(keyPath).\(dimension)", reason: "must be greater than zero")
                        }
                    }
                }
                if let action = key["action"] {
                    try validateAction(action, path: "\(keyPath).action", warnings: &warnings)
                } else if key["output"] == nil && key["value"] == nil && key["action"] == nil {
                    warnings.append("Key “\((key["label"] as? String) ?? "?")” has no action and will do nothing.")
                }
                if let alternates = key["longPress"] ?? key["longPressActions"] {
                    guard let alternatesArray = alternates as? [Any] else {
                        throw KeyboardImportError.invalidField(path: "\(keyPath).longPress", reason: "expected an array")
                    }
                    for (alternateIndex, rawAlternate) in alternatesArray.enumerated() {
                        let alternatePath = "\(keyPath).longPress[\(alternateIndex)]"
                        guard let alternate = rawAlternate as? [String: Any] else {
                            throw KeyboardImportError.invalidField(path: alternatePath, reason: "expected an object")
                        }
                        if let action = alternate["action"] {
                            try validateAction(action, path: "\(alternatePath).action", warnings: &warnings)
                        } else if alternate["value"] == nil {
                            warnings.append("A long-press alternative has no action and will be ignored.")
                        }
                    }
                }
            }
        }

        if totalKeys == 0 {
            throw KeyboardImportError.emptyLayout(name)
        }
    }

    private static func validateAction(_ value: Any, path: String, warnings: inout [String]) throws {
        guard let action = value as? [String: Any] else {
            throw KeyboardImportError.invalidField(path: path, reason: "expected an object such as {\"type\": \"insertText\", \"text\": \"π\"}")
        }
        guard let type = (action["type"] as? String)?.lowercased() else {
            warnings.append("An action at \(path) has no “type” and will do nothing.")
            return
        }

        let known = Set([
            "inserttext", "text", "insert", "insertmacro", "macro", "snippet",
            "backspace", "deletebackward", "delete", "space", "insertspace",
            "newline", "return", "enter", "linebreak", "shift", "capslock",
            "nextkeyboard", "globe", "nextinputmode", "switchkeyboard",
            "cursorleft", "moveleft", "movecursorleft",
            "cursorright", "moveright", "movecursorright",
            "cursormovebyoffset", "cursormove", "movecursor", "offset",
            "switchlayout", "switchlayer", "layer", "layout", "none", "noop"
        ])
        if !known.contains(type) {
            warnings.append("Unknown action type “\(type)” at \(path); that key will do nothing on this version.")
            return
        }

        switch type {
        case "inserttext", "text", "insert", "insertmacro", "macro", "snippet":
            let text = (action["text"] as? String) ?? (action["value"] as? String)
            guard let text, !text.isEmpty else {
                throw KeyboardImportError.invalidField(path: path, reason: "insert actions need a non-empty “text” value")
            }
        case "cursormovebyoffset", "cursormove", "movecursor", "offset":
            let offsetValue = action["offset"] ?? action["value"]
            guard let offsetValue, number(offsetValue) != nil else {
                throw KeyboardImportError.invalidField(path: path, reason: "cursor moves need a numeric “offset”")
            }
        case "switchlayout", "switchlayer", "layer", "layout":
            let name = (action["layoutName"] as? String) ?? (action["layout"] as? String) ?? (action["value"] as? String)
            let identifier = action["layoutID"] as? String
            if (name ?? "").isEmpty && (identifier ?? "").isEmpty {
                warnings.append("A switch-layout action at \(path) has no target and will do nothing.")
            }
        default:
            break
        }
    }

    private static func validateThemeDictionary(
        _ payload: [String: Any],
        path: String,
        warnings: inout [String]
    ) throws {
        let colorKeys = [
            "background", "keyColor", "specialKeyColor", "pressedKeyColor",
            "textColor", "specialTextColor", "borderColor", "backgroundColor"
        ]
        for colorKey in colorKeys {
            guard let raw = payload[colorKey] else { continue }
            if let string = raw as? String {
                if KeyboardColor(hex: string) == nil {
                    throw KeyboardImportError.invalidField(
                        path: "\(path).\(colorKey)",
                        reason: "“\(string)” is not a colour. Use hex such as #1B1030 or #1B1030FF."
                    )
                }
            } else if let numbers = raw as? [Any] {
                if numbers.count < 3 {
                    throw KeyboardImportError.invalidField(path: "\(path).\(colorKey)", reason: "expected at least 3 components")
                }
                for (index, value) in numbers.enumerated() where number(value) == nil {
                    throw KeyboardImportError.invalidField(path: "\(path).\(colorKey)[\(index)]", reason: "expected a number")
                }
            } else {
                throw KeyboardImportError.invalidField(path: "\(path).\(colorKey)", reason: "expected a hex string such as #101010")
            }
        }

        for numericKey in ["borderWidth", "cornerRadius", "keySpacing", "rowSpacing", "fontSize", "keyShadowRadius", "keyShadowOpacity", "keyOpacity", "pressedScale"] {
            if let value = payload[numericKey], number(value) == nil {
                throw KeyboardImportError.invalidField(path: "\(path).\(numericKey)", reason: "expected a number")
            }
        }

        if let weight = payload["fontWeight"] as? String,
           KeyboardFontWeight(rawValue: weight.lowercased()) == nil {
            warnings.append("Unknown font weight “\(weight)”; the default weight was used.")
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            // Booleans bridge to NSNumber; they are not valid dimensions.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

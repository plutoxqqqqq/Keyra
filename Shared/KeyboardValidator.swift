import Foundation

/// Severity of a configuration problem.
enum KeyboardIssueSeverity: String, Codable, CaseIterable, Identifiable {
    case error
    case warning
    case info

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Note"
        }
    }

    var symbolName: String {
        switch self {
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// A single, human-readable problem found in a layout or configuration.
struct KeyboardIssue: Identifiable, Equatable {

    let id: UUID
    var severity: KeyboardIssueSeverity
    var title: String
    var detail: String
    /// Which layout the issue belongs to, if any.
    var layoutID: UUID?
    var layoutName: String?

    init(
        id: UUID = UUID(),
        severity: KeyboardIssueSeverity,
        title: String,
        detail: String,
        layoutID: UUID? = nil,
        layoutName: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.layoutID = layoutID
        self.layoutName = layoutName
    }
}

/// Result of cleaning up a configuration that came from disk or from an import.
struct ConfigurationRepairResult {
    var configuration: KeyboardConfiguration
    var issues: [KeyboardIssue]

    var hasErrors: Bool { issues.contains { $0.severity == .error } }
    var hasWarnings: Bool { issues.contains { $0.severity == .warning } }
}

/// Limits used when repairing hostile or hand-written data. They exist to keep
/// the keyboard responsive — they are *not* layout rules, and they are far
/// above anything a person builds by hand.
enum KeyboardLimits {
    static let maxRows = 40
    static let maxKeysPerRow = 60
    static let maxKeysTotal = 600
    static let maxLayouts = 40
    static let maxThemes = 40
    static let minKeyWidthWeight = 0.15
    static let maxKeyWidthWeight = 40
    static let minKeyHeightWeight = 0.4
    static let maxKeyHeightWeight = 4
    static let minRowHeightWeight = 0.4
    static let maxRowHeightWeight = 6
    static let maxTextLength = 4096
    static let maxLongPressAlternates = 12
}

/// Validates and repairs configuration.
///
/// Two entry points:
/// * `sanitize` — always succeeds, always returns something renderable. Used on
///   every load, including inside the keyboard extension.
/// * `issues` — the diagnostics shown in the host app's editor.
enum KeyboardValidator {

    // MARK: - Repair

    static func sanitize(_ configuration: KeyboardConfiguration) -> ConfigurationRepairResult {
        var issues: [KeyboardIssue] = []
        var working = configuration

        if working.schemaVersion != KeyboardConfiguration.currentSchemaVersion {
            issues.append(KeyboardIssue(
                severity: .info,
                title: "Schema version \(working.schemaVersion)",
                detail: "Saved with a different schema version; missing fields were filled with defaults."
            ))
            working.schemaVersion = KeyboardConfiguration.currentSchemaVersion
        }

        // Themes ------------------------------------------------------------
        var themes = working.themes.map { sanitizeTheme($0) }
        if themes.isEmpty {
            themes = KeyboardTheme.builtIn
            issues.append(KeyboardIssue(
                severity: .warning,
                title: "No themes found",
                detail: "The four built-in themes were restored."
            ))
        }
        if themes.count > KeyboardLimits.maxThemes {
            themes = Array(themes.prefix(KeyboardLimits.maxThemes))
            issues.append(KeyboardIssue(
                severity: .warning,
                title: "Too many themes",
                detail: "Only the first \(KeyboardLimits.maxThemes) themes are kept."
            ))
        }
        themes = deduplicate(themes, issues: &issues, describe: { "theme “\($0.name)”" })
        working.themes = themes

        if !themes.contains(where: { $0.id == working.activeThemeID }) {
            working.activeThemeID = themes.first?.id ?? KeyboardTheme.defaultTheme.id
        }

        // Layouts -----------------------------------------------------------
        var layouts = working.layouts.map { sanitizeLayout($0, issues: &issues) }
        if layouts.isEmpty {
            layouts = [KeyboardDefaults.starterLayout]
            issues.append(KeyboardIssue(
                severity: .warning,
                title: "No layouts found",
                detail: "A built-in starter keyboard was loaded so the keyboard still works."
            ))
        }
        if layouts.count > KeyboardLimits.maxLayouts {
            layouts = Array(layouts.prefix(KeyboardLimits.maxLayouts))
            issues.append(KeyboardIssue(
                severity: .warning,
                title: "Too many layouts",
                detail: "Only the first \(KeyboardLimits.maxLayouts) layouts are kept."
            ))
        }
        var seenNames: Set<String> = []
        for index in layouts.indices {
            let name = layouts[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                layouts[index].name = "Keyboard \(index + 1)"
            }
            var candidate = layouts[index].name
            var suffix = 2
            while seenNames.contains(candidate.lowercased()) {
                candidate = "\(layouts[index].name) \(suffix)"
                suffix += 1
            }
            if candidate != layouts[index].name {
                issues.append(KeyboardIssue(
                    severity: .warning,
                    title: "Duplicate layout name",
                    detail: "Renamed to “\(candidate)” so layout switching by name stays unambiguous.",
                    layoutID: layouts[index].id,
                    layoutName: candidate
                ))
                layouts[index].name = candidate
            }
            seenNames.insert(candidate.lowercased())
        }
        working.layouts = layouts

        if !layouts.contains(where: { $0.id == working.activeLayoutID }) {
            working.activeLayoutID = layouts.first?.id ?? KeyboardDefaults.starterLayout.id
            issues.append(KeyboardIssue(
                severity: .warning,
                title: "Active keyboard was missing",
                detail: "Switched to “\(working.activeLayout?.name ?? "Starter")”."
            ))
        }

        // Settings ----------------------------------------------------------
        working.settings = sanitizeSettings(working.settings)

        if working.generation < 1 { working.generation = 1 }
        return ConfigurationRepairResult(configuration: working, issues: issues)
    }

    static func sanitizeTheme(_ theme: KeyboardTheme) -> KeyboardTheme {
        var result = theme
        if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.name = "Untitled Theme"
        }
        result.background = result.background.clamped()
        result.keyColor = result.keyColor.clamped()
        result.specialKeyColor = result.specialKeyColor.clamped()
        result.pressedKeyColor = result.pressedKeyColor.clamped()
        result.textColor = result.textColor.clamped()
        result.specialTextColor = result.specialTextColor.clamped()
        result.borderColor = result.borderColor.clamped()
        result.borderWidth = clamp(result.borderWidth, 0, 6, fallback: 0)
        result.cornerRadius = clamp(result.cornerRadius, 0, 26, fallback: 6)
        result.keySpacing = clamp(result.keySpacing, 0, 24, fallback: 6)
        result.rowSpacing = clamp(result.rowSpacing, 0, 32, fallback: 9)
        result.keyShadowRadius = clamp(result.keyShadowRadius, 0, 20, fallback: 0)
        result.keyShadowOpacity = clamp(result.keyShadowOpacity, 0, 1, fallback: 0)
        result.keyOpacity = clamp(result.keyOpacity, 0.1, 1, fallback: 1)
        result.fontSize = clamp(result.fontSize, 9, 44, fallback: 22)
        result.pressedScale = clamp(result.pressedScale, 0.8, 1.1, fallback: 0.96)
        return result
    }

    static func sanitizeSettings(_ settings: KeyboardSettings) -> KeyboardSettings {
        var result = settings
        result.doubleTapWindow = clamp(result.doubleTapWindow, 0.15, 1.0, fallback: 0.35)
        result.longPressDelay = clamp(result.longPressDelay, 0.15, 1.5, fallback: 0.38)
        result.backspaceRepeatDelay = clamp(result.backspaceRepeatDelay, 0.15, 2.0, fallback: 0.45)
        result.backspaceRepeatInterval = clamp(result.backspaceRepeatInterval, 0.02, 0.5, fallback: 0.09)
        result.fontScale = clamp(result.fontScale, 0.6, 1.8, fallback: 1.0)
        return result
    }

    static func sanitizeLayout(_ layout: KeyboardLayout, issues: inout [KeyboardIssue]) -> KeyboardLayout {
        var result = layout
        let displayName = result.name.isEmpty ? "Untitled" : result.name

        if result.rows.isEmpty {
            issues.append(KeyboardIssue(
                severity: .error,
                title: "“\(displayName)” has no rows",
                detail: "Add at least one row with a key, or the keyboard will be empty.",
                layoutID: layout.id,
                layoutName: displayName
            ))
        }
        if result.rows.count > KeyboardLimits.maxRows {
            result.rows = Array(result.rows.prefix(KeyboardLimits.maxRows))
            issues.append(KeyboardIssue(
                severity: .error,
                title: "“\(displayName)” has too many rows",
                detail: "Only the first \(KeyboardLimits.maxRows) rows are kept; the keyboard area cannot grow without limit.",
                layoutID: layout.id,
                layoutName: displayName
            ))
        }

        var seenKeyIDs: Set<UUID> = []
        var totalKeys = 0

        for rowIndex in result.rows.indices {
            result.rows[rowIndex].height = clamp(
                result.rows[rowIndex].height,
                KeyboardLimits.minRowHeightWeight,
                KeyboardLimits.maxRowHeightWeight,
                fallback: 1
            )

            if result.rows[rowIndex].keys.count > KeyboardLimits.maxKeysPerRow {
                result.rows[rowIndex].keys = Array(result.rows[rowIndex].keys.prefix(KeyboardLimits.maxKeysPerRow))
                issues.append(KeyboardIssue(
                    severity: .warning,
                    title: "Row \(rowIndex + 1) had too many keys",
                    detail: "Keys beyond \(KeyboardLimits.maxKeysPerRow) were removed.",
                    layoutID: layout.id,
                    layoutName: displayName
                ))
            }

            if result.rows[rowIndex].keys.isEmpty {
                issues.append(KeyboardIssue(
                    severity: .warning,
                    title: "Row \(rowIndex + 1) of “\(displayName)” is empty",
                    detail: "Empty rows are skipped on the keyboard — add a key or delete the row.",
                    layoutID: layout.id,
                    layoutName: displayName
                ))
            }

            for keyIndex in result.rows[rowIndex].keys.indices {
                totalKeys += 1
                var key = result.rows[rowIndex].keys[keyIndex]

                key.width = clamp(key.width, KeyboardLimits.minKeyWidthWeight, KeyboardLimits.maxKeyWidthWeight, fallback: 1)
                key.height = clamp(key.height, KeyboardLimits.minKeyHeightWeight, KeyboardLimits.maxKeyHeightWeight, fallback: 1)
                key.action = sanitizeAction(key.action, label: key.label)
                if key.label.isEmpty {
                    key.label = key.action.unshiftedText ?? "?"
                }
                if key.shiftOutput?.isEmpty == true { key.shiftOutput = nil }
                if key.shiftOutput != nil, key.shiftOutput?.count ?? 0 > KeyboardLimits.maxTextLength {
                    key.shiftOutput = String(key.shiftOutput?.prefix(KeyboardLimits.maxTextLength) ?? "")
                }

                // Repair the alternates list. Incomplete entries are kept (the
                // editor must not lose a half-finished edit) but duplicated ids
                // are repaired and the count is bounded.
                var cleanedAlternates: [KeyboardKeyLongPress] = []
                var seenAlternateIDs: Set<UUID> = []
                for var alternate in key.longPress {
                    alternate.action = sanitizeAction(alternate.action, label: alternate.label)
                    if alternate.label.isEmpty { alternate.label = alternate.action.unshiftedText ?? "?" }
                    if seenAlternateIDs.contains(alternate.id) { alternate.id = UUID() }
                    seenAlternateIDs.insert(alternate.id)
                    cleanedAlternates.append(alternate)
                    if cleanedAlternates.count >= KeyboardLimits.maxLongPressAlternates { break }
                }
                key.longPress = cleanedAlternates

                if key.action.isIncomplete {
                    issues.append(KeyboardIssue(
                        severity: .warning,
                        title: "Key “\(key.label)” does nothing yet",
                        detail: "Its action is \(key.action.type.displayName) but it has no output configured.",
                        layoutID: layout.id,
                        layoutName: displayName
                    ))
                }

                if seenKeyIDs.contains(key.id) {
                    key.id = UUID()
                    issues.append(KeyboardIssue(
                        severity: .warning,
                        title: "Duplicate key identifier",
                        detail: "A repeated key id was replaced with a new one.",
                        layoutID: layout.id,
                        layoutName: displayName
                    ))
                }
                seenKeyIDs.insert(key.id)
                result.rows[rowIndex].keys[keyIndex] = key
            }
        }

        // Re-deduplicate row ids across the whole layout.
        var seenRowIDs: Set<UUID> = []
        for index in result.rows.indices {
            if seenRowIDs.contains(result.rows[index].id) {
                result.rows[index].id = UUID()
            }
            seenRowIDs.insert(result.rows[index].id)
        }

        if totalKeys > KeyboardLimits.maxKeysTotal {
            issues.append(KeyboardIssue(
                severity: .error,
                title: "“\(displayName)” has \(totalKeys) keys",
                detail: "That is far more than fits on a phone keyboard. The editor will show it, but the keyboard may clip it.",
                layoutID: layout.id,
                layoutName: displayName
            ))
        }

        return result
    }

    /// Repairs an action without ever changing its *type*.
    ///
    /// This matters while editing: a key that is halfway through being set up
    /// (an “insert text” key with no text yet, or a layout switch with no target
    /// chosen) must keep its type so the editor can keep showing the right
    /// controls. Such keys are reported through `KeyboardIssue` instead, and the
    /// engine treats them as no-ops at runtime.
    private static func sanitizeAction(_ action: KeyboardKeyAction, label: String) -> KeyboardKeyAction {
        switch action {
        case .insertText(let text):
            return .insertText(String(text.prefix(KeyboardLimits.maxTextLength)))
        case .insertMacro(let text):
            return .insertMacro(String(text.prefix(KeyboardLimits.maxTextLength)))
        case .cursorMoveByOffset(let offset):
            let bounded = max(-512, min(512, offset))
            return .cursorMoveByOffset(bounded)
        case .switchLayout(let id, let name):
            var cleanedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedName?.isEmpty == true { cleanedName = nil }
            return .switchLayout(layoutID: id, layoutName: cleanedName)
        default:
            return action
        }
    }

    private static func deduplicate<T: Identifiable>(
        _ items: [T],
        issues: inout [KeyboardIssue],
        describe: (T) -> String
    ) -> [T] where T.ID == UUID {
        var seen: Set<UUID> = []
        var output: [T] = []
        for item in items {
            if seen.contains(item.id) {
                issues.append(KeyboardIssue(
                    severity: .warning,
                    title: "Duplicate \(describe(item))",
                    detail: "A duplicated identifier was skipped."
                ))
                continue
            }
            seen.insert(item.id)
            output.append(item)
        }
        return output
    }

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        if value < lower { return lower }
        if value > upper { return upper }
        return value
    }

    // MARK: - Diagnostics for the editor

    static func issues(for layout: KeyboardLayout, in configuration: KeyboardConfiguration) -> [KeyboardIssue] {
        var found: [KeyboardIssue] = []
        let name = layout.name.isEmpty ? "Untitled" : layout.name

        if layout.rows.isEmpty {
            found.append(KeyboardIssue(severity: .error, title: "No rows",
                                       detail: "This keyboard has no rows yet. Add a row to start building.",
                                       layoutID: layout.id, layoutName: name))
        }
        if layout.keyCount == 0 {
            found.append(KeyboardIssue(severity: .error, title: "No keys",
                                       detail: "Add at least one key so this keyboard can be used.",
                                       layoutID: layout.id, layoutName: name))
        }

        for (index, row) in layout.rows.enumerated() where row.keys.isEmpty {
            found.append(KeyboardIssue(severity: .warning, title: "Row \(index + 1) is empty",
                                       detail: "Empty rows are skipped on the real keyboard.",
                                       layoutID: layout.id, layoutName: name))
        }

        for key in layout.allKeys where key.action.isIncomplete {
            found.append(KeyboardIssue(severity: .warning, title: "Key “\(key.label)” is incomplete",
                                       detail: "Configure \(key.action.type.displayName) so the key does something.",
                                       layoutID: layout.id, layoutName: name))
        }

        for key in layout.allKeys {
            for alternate in key.longPress where alternate.action.isIncomplete {
                found.append(KeyboardIssue(
                    severity: .warning,
                    title: "Long press “\(alternate.label)” on key “\(key.label)” is incomplete",
                    detail: "It will do nothing until you give it an output.",
                    layoutID: layout.id,
                    layoutName: name
                ))
            }
        }

        // Switch-layout targets that do not exist.
        for key in layout.allKeys {
            guard case .switchLayout(_, let target) = key.action, let target, !target.isEmpty else { continue }
            if configuration.layout(named: target) == nil {
                found.append(KeyboardIssue(
                    severity: .error,
                    title: "Key “\(key.label)” points at a missing keyboard",
                    detail: "There is no keyboard named “\(target)”. Rename the key's target or create that keyboard.",
                    layoutID: layout.id,
                    layoutName: name
                ))
            }
        }

        // Missing escape hatch: if the layout has no globe key the user may not
        // be able to switch keyboards without opening Settings.
        if !layout.containsNextKeyboardKey {
            found.append(KeyboardIssue(
                severity: .warning,
                title: "No Next Keyboard key",
                detail: "Add a key with the “Next Keyboard (Globe)” action so this keyboard can be left without opening Settings. The runtime adds one automatically when a text field needs it.",
                layoutID: layout.id,
                layoutName: name
            ))
        }

        let geometry = KeyboardMetrics.geometry(
            layout: layout,
            availableWidth: KeyboardMetrics.referencePortraitWidth,
            availableHeight: KeyboardMetrics.referenceKeyboardHeight,
            keySpacing: 6,
            rowSpacing: 10
        )
        if geometry.isOverflowing {
            found.append(KeyboardIssue(
                severity: .warning,
                title: "Layout may be too tall",
                detail: "\(layout.rows.count) rows do not fit the reference keyboard height without shrinking below normal key size. The real keyboard grows to fit, but other apps may overlay it.",
                layoutID: layout.id,
                layoutName: name
            ))
        }
        if geometry.minimumKeyWidth < KeyboardMetrics.readableKeyWidth {
            found.append(KeyboardIssue(
                severity: .warning,
                title: "Some keys would be very narrow",
                detail: "The widest row has \(geometry.maxRowKeyCount) keys, which leaves about \(Int(geometry.minimumKeyWidth))pt per key. Consider splitting it across two rows.",
                layoutID: layout.id,
                layoutName: name
            ))
        }

        return found
    }

    static func issues(for configuration: KeyboardConfiguration) -> [KeyboardIssue] {
        var found: [KeyboardIssue] = []
        for layout in configuration.layouts {
            found.append(contentsOf: issues(for: layout, in: configuration))
        }
        return found
    }

    /// The worst severity present, used to colour status badges.
    static func worstSeverity(in issues: [KeyboardIssue]) -> KeyboardIssueSeverity? {
        if issues.contains(where: { $0.severity == .error }) { return .error }
        if issues.contains(where: { $0.severity == .warning }) { return .warning }
        if issues.contains(where: { $0.severity == .info }) { return .info }
        return nil
    }
}

import Foundation

// MARK: - Actions

/// Every action the keyboard engine understands.
///
/// The set is deliberately explicit (no `AnyCodable` escape hatch) so that a
/// layout can never contain something the engine is unable to perform, and so
/// unknown / future action types degrade to `.none` instead of crashing.
enum KeyboardKeyAction: Equatable, Hashable {

    /// Insert an arbitrary Unicode string (one character or a whole sentence).
    case insertText(String)

    /// Insert a multi-line snippet / macro. Same effect as `insertText`, kept
    /// separate so the editor can present it as a snippet and the renderer can
    /// style it as a special key.
    case insertMacro(String)

    case backspace
    case space
    case newline
    case shift
    case nextKeyboard
    case cursorLeft
    case cursorRight

    /// Move the caret by `offset` characters where iOS supports it.
    case cursorMoveByOffset(Int)

    /// Switch to another layout, resolved by name first (names survive JSON
    /// import/export, ids do not) then by id.
    case switchLayout(layoutID: UUID?, layoutName: String?)

    /// Do nothing — useful as a placeholder while designing a layout.
    case none
}

/// The stable, human-facing type name used in JSON and in the editor picker.
enum KeyboardKeyActionType: String, CaseIterable, Identifiable, Codable {
    case insertText
    case insertMacro
    case backspace
    case space
    case newline
    case shift
    case nextKeyboard
    case cursorLeft
    case cursorRight
    case cursorMoveByOffset
    case switchLayout
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .insertText: return "Insert Text"
        case .insertMacro: return "Insert Macro / Snippet"
        case .backspace: return "Backspace"
        case .space: return "Space"
        case .newline: return "New Line / Return"
        case .shift: return "Shift"
        case .nextKeyboard: return "Next Keyboard (Globe)"
        case .cursorLeft: return "Move Cursor Left"
        case .cursorRight: return "Move Cursor Right"
        case .cursorMoveByOffset: return "Move Cursor By Offset"
        case .switchLayout: return "Switch Layout / Layer"
        case .none: return "Do Nothing"
        }
    }

    /// One-line explanation shown under the picker in the key editor.
    var explanation: String {
        switch self {
        case .insertText:
            return "Types exactly the text you enter — any Unicode, any length, including emoji and multi-character strings such as \"=>\"."
        case .insertMacro:
            return "Types a saved snippet. New lines and spacing are preserved exactly as written."
        case .backspace:
            return "Deletes the previous character using the system text proxy."
        case .space:
            return "Inserts a single space. The key's label can say anything (\"space\", \"English\", \"+\")."
        case .newline:
            return "Inserts a line break. Some apps may treat this as Send or Done instead of Return — that is up to the app."
        case .shift:
            return "Shift for the next character, or Caps Lock on double tap. Keys may define their own shifted output."
        case .nextKeyboard:
            return "Switches to your next enabled keyboard using Apple's public API."
        case .cursorLeft:
            return "Moves the caret one character left. This is a caret move, not the \"←\" character."
        case .cursorRight:
            return "Moves the caret one character right. This is a caret move, not the \"→\" character."
        case .cursorMoveByOffset:
            return "Moves the caret by a number of characters. iOS may clamp large jumps."
        case .switchLayout:
            return "Jumps to one of your other layouts — build ABC / 123 / SYM / MATH / EMOJI keyboards this way."
        case .none:
            return "The key renders but performs no action."
        }
    }

    var isTextProducing: Bool {
        self == .insertText || self == .insertMacro || self == .space || self == .newline
    }

    var usesShiftOutput: Bool {
        self == .insertText || self == .insertMacro
    }
}

extension KeyboardKeyAction {

    var type: KeyboardKeyActionType {
        switch self {
        case .insertText: return .insertText
        case .insertMacro: return .insertMacro
        case .backspace: return .backspace
        case .space: return .space
        case .newline: return .newline
        case .shift: return .shift
        case .nextKeyboard: return .nextKeyboard
        case .cursorLeft: return .cursorLeft
        case .cursorRight: return .cursorRight
        case .cursorMoveByOffset: return .cursorMoveByOffset
        case .switchLayout: return .switchLayout
        case .none: return .none
        }
    }

    /// The text this action types on a normal (unshifted) press, if any.
    var unshiftedText: String? {
        switch self {
        case .insertText(let text), .insertMacro(let text): return text
        case .space: return " "
        case .newline: return "\n"
        default: return nil
        }
    }

    var cursorOffset: Int? {
        switch self {
        case .cursorMoveByOffset(let offset): return offset
        case .cursorLeft: return -1
        case .cursorRight: return 1
        default: return nil
        }
    }

    /// A brand new action of the requested type, used by the key editor.
    static func makeDefault(for type: KeyboardKeyActionType) -> KeyboardKeyAction {
        switch type {
        case .insertText: return .insertText("")
        case .insertMacro: return .insertMacro("")
        case .backspace: return .backspace
        case .space: return .space
        case .newline: return .newline
        case .shift: return .shift
        case .nextKeyboard: return .nextKeyboard
        case .cursorLeft: return .cursorLeft
        case .cursorRight: return .cursorRight
        case .cursorMoveByOffset: return .cursorMoveByOffset(-1)
        case .switchLayout: return .switchLayout(layoutID: nil, layoutName: nil)
        case .none: return .none
        }
    }

    /// `true` when this action cannot do anything yet (e.g. an "insert text"
    /// key with no text) so the editor can warn instead of shipping a dead key.
    var isIncomplete: Bool {
        switch self {
        case .insertText(let text), .insertMacro(let text): return text.isEmpty
        case .switchLayout(let id, let name): return id == nil && (name ?? "").isEmpty
        case .cursorMoveByOffset(let offset): return offset == 0
        default: return false
        }
    }

    /// Short description used in key lists and accessibility labels.
    var summary: String {
        switch self {
        case .insertText(let text):
            return text.isEmpty ? "Insert text (empty)" : "Type “\(KeyboardKeyAction.previewable(text))”"
        case .insertMacro(let text):
            return text.isEmpty ? "Macro (empty)" : "Macro “\(KeyboardKeyAction.previewable(text))”"
        case .backspace: return "Backspace"
        case .space: return "Type a space"
        case .newline: return "Type a line break"
        case .shift: return "Shift / Caps Lock"
        case .nextKeyboard: return "Next keyboard"
        case .cursorLeft: return "Caret left"
        case .cursorRight: return "Caret right"
        case .cursorMoveByOffset(let offset): return "Caret by \(offset)"
        case .switchLayout(_, let name):
            if let name, !name.isEmpty { return "Switch to “\(name)”" }
            return "Switch layout"
        case .none: return "No action"
        }
    }

    /// Collapses newlines so preview text stays on one line.
    static func previewable(_ text: String, limit: Int = 28) -> String {
        var collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if collapsed.count > limit {
            collapsed = String(collapsed.prefix(limit)) + "…"
        }
        return collapsed
    }
}

// MARK: - Codable

extension KeyboardKeyAction: Codable {

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case value
        case offset
        case layoutID = "layoutID"
        case layoutName
        case layout
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .none
            return
        }

        let rawType = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
        let normalised = (rawType ?? "none").trimmingCharacters(in: .whitespaces).lowercased()

        // `value` is accepted as an alias for `text` because it appears in the
        // documented example schema and in hand-written JSON.
        let text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? nil
        let value = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? nil
        let payload = text ?? value

        switch normalised {
        case "inserttext", "text", "insert":
            self = .insertText(payload ?? "")
        case "insertmacro", "macro", "snippet":
            self = .insertMacro(payload ?? "")
        case "backspace", "deletebackward", "delete":
            self = .backspace
        case "space", "insertspace":
            self = .space
        case "newline", "return", "enter", "linebreak":
            self = .newline
        case "shift", "capslock":
            self = .shift
        case "nextkeyboard", "globe", "nextinputmode", "switchkeyboard":
            self = .nextKeyboard
        case "cursorleft", "moveleft", "movecursorleft":
            self = .cursorLeft
        case "cursorright", "moveright", "movecursorright":
            self = .cursorRight
        case "cursormovebyoffset", "cursormove", "movecursor", "offset":
            var offset = container.keyraInt(.offset, 0)
            if offset == 0, let value, let parsed = Int(value) { offset = parsed }
            self = .cursorMoveByOffset(offset)
        case "switchlayout", "switchlayer", "layer", "layout":
            let name = container.keyraNonEmptyString(.layoutName)
                ?? container.keyraNonEmptyString(.layout)
                ?? value
            let identifier = container.keyraOptionalUUID(.layoutID)
            self = .switchLayout(layoutID: identifier, layoutName: name)
        default:
            // Unknown or future action types must never break the keyboard.
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        switch self {
        case .insertText(let text), .insertMacro(let text):
            try container.encode(text, forKey: .text)
        case .cursorMoveByOffset(let offset):
            try container.encode(offset, forKey: .offset)
        case .switchLayout(let identifier, let name):
            if let identifier { try container.encode(identifier, forKey: .layoutID) }
            if let name { try container.encode(name, forKey: .layoutName) }
        default:
            break
        }
    }
}

// MARK: - Long press

/// A long-press alternative attached to a key (e.g. "." → ".com").
struct KeyboardKeyLongPress: Codable, Equatable, Identifiable {

    var id: UUID
    var label: String
    var action: KeyboardKeyAction

    init(id: UUID = UUID(), label: String, action: KeyboardKeyAction) {
        self.id = id
        self.label = label
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, action, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.keyraUUID(.id)
        let decodedAction = container.keyraValue(.action, KeyboardKeyAction.none)
        label = container.keyraValue(.label, decodedAction.unshiftedText ?? "")
        if decodedAction == .none, let value = container.keyraNonEmptyString(.value) {
            action = .insertText(value)
        } else {
            action = decodedAction
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(action, forKey: .action)
    }
}

// MARK: - Key

/// One key on the keyboard.  `width` / `height` are *relative weights*, never
/// pixels: the renderer normalises them against the space actually available,
/// which is what lets a row of 3 keys and a row of 20 keys coexist.
struct KeyboardKey: Codable, Equatable, Identifiable {

    var id: UUID
    var label: String
    var action: KeyboardKeyAction

    /// Text typed while Shift (or Caps Lock) is active. When `nil` the engine
    /// falls back to `settings.autoUppercaseOnShift` (single cased letters
    /// only) and otherwise types the normal output unchanged.
    var shiftOutput: String?

    /// Relative width weight: 1.0 normal, 1.5 backspace, 5.0 space.
    var width: Double
    /// Relative height weight inside its row (1.0 = the row's full height).
    var height: Double
    /// Styling hint: uses the theme's special-key colour.
    var isSpecial: Bool
    /// Press-and-hold alternatives rendered in a popup above the key.
    var longPress: [KeyboardKeyLongPress]
    /// Repeat the action while held (backspace, caret movement).
    var repeatsWhenHeld: Bool
    /// Custom VoiceOver description. Never expose raw ids to VoiceOver.
    var accessibilityLabel: String?

    init(
        id: UUID = UUID(),
        label: String,
        action: KeyboardKeyAction,
        shiftOutput: String? = nil,
        width: Double = 1,
        height: Double = 1,
        isSpecial: Bool = false,
        longPress: [KeyboardKeyLongPress] = [],
        repeatsWhenHeld: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.action = action
        self.shiftOutput = shiftOutput
        self.width = width
        self.height = height
        self.isSpecial = isSpecial
        self.longPress = longPress
        self.repeatsWhenHeld = repeatsWhenHeld
        self.accessibilityLabel = accessibilityLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, action, output, value, shiftOutput, shiftedOutput
        case width, height, isSpecial, longPress, longPressActions
        case repeatsWhenHeld, accessibilityLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.keyraUUID(.id)

        var decodedAction = container.keyraValue(.action, KeyboardKeyAction.none)
        // Convenience: `{"label": "a", "output": "a"}` without an action object.
        if decodedAction == .none,
           let output = container.keyraNonEmptyString(.output) ?? container.keyraNonEmptyString(.value) {
            decodedAction = .insertText(output)
        }

        action = decodedAction
        label = container.keyraValue(.label, decodedAction.unshiftedText ?? "")

        shiftOutput = container.keyraNonEmptyString(.shiftOutput)
            ?? container.keyraNonEmptyString(.shiftedOutput)

        width = container.keyraDouble(.width, 1)
        height = container.keyraDouble(.height, 1)
        isSpecial = container.keyraBool(.isSpecial, !decodedAction.type.isTextProducing)
        repeatsWhenHeld = container.keyraBool(.repeatsWhenHeld, decodedAction == .backspace)

        let candidates = container.keyraValue(.longPress, [KeyboardKeyLongPress]())
        if candidates.isEmpty {
            longPress = container.keyraValue(.longPressActions, [KeyboardKeyLongPress]())
        } else {
            longPress = candidates
        }

        accessibilityLabel = container.keyraNonEmptyString(.accessibilityLabel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(action, forKey: .action)
        if let shiftOutput { try container.encode(shiftOutput, forKey: .shiftOutput) }
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(isSpecial, forKey: .isSpecial)
        if !longPress.isEmpty { try container.encode(longPress, forKey: .longPress) }
        try container.encode(repeatsWhenHeld, forKey: .repeatsWhenHeld)
        if let accessibilityLabel { try container.encode(accessibilityLabel, forKey: .accessibilityLabel) }
    }

    // MARK: - Helpers

    /// What VoiceOver announces for this key.
    var spokenLabel: String {
        if let accessibilityLabel, !accessibilityLabel.isEmpty { return accessibilityLabel }
        switch action {
        case .insertText(let text), .insertMacro(let text):
            if label.count == 1, label.rangeOfCharacter(from: .letters) != nil {
                return "Letter \(label)"
            }
            if text.isEmpty { return "Insert text" }
            return "Type \(KeyboardKeyAction.previewable(text, limit: 16))"
        case .space: return "Space"
        case .backspace: return "Backspace"
        case .newline: return "Return"
        case .shift: return "Shift"
        case .nextKeyboard: return "Next Keyboard"
        case .cursorLeft: return "Move cursor left"
        case .cursorRight: return "Move cursor right"
        case .cursorMoveByOffset(let offset): return "Move cursor by \(offset)"
        case .switchLayout(_, let name): return name.map { "Switch to \($0) keyboard" } ?? "Switch keyboard layout"
        case .none: return label.isEmpty ? "Empty key" : label
        }
    }

    /// The text this key types with the given shift state, honouring an explicit
    /// custom `shiftOutput` before falling back to automatic upper-casing.
    func insertion(forShiftState shiftState: ShiftState, autoUppercase: Bool) -> String? {
        switch action {
        case .space:
            return " "
        case .newline:
            return "\n"
        case .insertText(let text), .insertMacro(let text):
            guard shiftState != .off else { return text }
            if let shiftOutput, !shiftOutput.isEmpty { return shiftOutput }
            guard autoUppercase else { return text }
            guard text.count == 1, let character = text.first, character.isLowercase else { return text }
            return text.uppercased()
        default:
            return action.unshiftedText
        }
    }

    /// Label shown on the key while Shift is active.
    func displayLabel(forShiftState shiftState: ShiftState) -> String {
        guard shiftState != .off, action.type.usesShiftOutput else { return label }
        if let shiftOutput, !shiftOutput.isEmpty { return shiftOutput }
        guard label.count == 1, let character = label.first, character.isLowercase else { return label }
        return label.uppercased()
    }

    func duplicated() -> KeyboardKey {
        var copy = self
        copy.id = UUID()
        copy.longPress = longPress.map { KeyboardKeyLongPress(id: UUID(), label: $0.label, action: $0.action) }
        return copy
    }
}

// MARK: - Row

struct KeyboardRow: Codable, Equatable, Identifiable {

    var id: UUID
    /// Optional name shown only inside the editor.
    var name: String?
    /// Relative height weight for this row (1.0 = one standard keyboard row).
    var height: Double
    var keys: [KeyboardKey]

    init(id: UUID = UUID(), name: String? = nil, height: Double = 1, keys: [KeyboardKey] = []) {
        self.id = id
        self.name = name
        self.height = height
        self.keys = keys
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, height, keys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.keyraUUID(.id)
        name = container.keyraNonEmptyString(.name)
        height = container.keyraDouble(.height, 1)
        keys = container.keyraValue(.keys, [KeyboardKey]())
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let name { try container.encode(name, forKey: .name) }
        try container.encode(height, forKey: .height)
        try container.encode(keys, forKey: .keys)
    }

    var isUsable: Bool { !keys.isEmpty }

    func duplicated() -> KeyboardRow {
        KeyboardRow(
            name: name.map { "\($0) copy" },
            height: height,
            keys: keys.map { $0.duplicated() }
        )
    }
}

// MARK: - Layout

struct KeyboardLayout: Codable, Equatable, Identifiable {

    var id: UUID
    /// Layout names are the primary way layouts reference each other, because
    /// names survive JSON import/export while UUIDs do not.
    var name: String
    var rows: [KeyboardRow]
    var notes: String?

    init(id: UUID = UUID(), name: String, rows: [KeyboardRow] = [], notes: String? = nil) {
        self.id = id
        self.name = name
        self.rows = rows
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rows, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.keyraUUID(.id)
        name = container.keyraValue(.name, "Untitled Layout")
        rows = container.keyraValue(.rows, [KeyboardRow]())
        notes = container.keyraNonEmptyString(.notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rows, forKey: .rows)
        if let notes { try container.encode(notes, forKey: .notes) }
    }

    // MARK: Derived values

    var rowCount: Int { rows.count }

    var keyCount: Int { rows.reduce(0) { $0 + $1.keys.count } }

    var isEmpty: Bool { rows.isEmpty || keyCount == 0 }

    var allKeys: [KeyboardKey] { rows.flatMap { $0.keys } }

    func row(withID rowID: UUID) -> KeyboardRow? {
        rows.first { $0.id == rowID }
    }

    func rowIndex(for rowID: UUID) -> Int? {
        rows.firstIndex { $0.id == rowID }
    }

    func key(withID keyID: UUID) -> KeyboardKey? {
        for row in rows {
            if let match = row.keys.first(where: { $0.id == keyID }) { return match }
        }
        return nil
    }

    func rowID(containing keyID: UUID) -> UUID? {
        for row in rows where row.keys.contains(where: { $0.id == keyID }) {
            return row.id
        }
        return nil
    }

    /// Layouts that contain a "next keyboard" key let the user leave this
    /// keyboard without opening Settings.
    var containsNextKeyboardKey: Bool {
        allKeys.contains { $0.action == .nextKeyboard }
    }

    func duplicated(named newName: String? = nil) -> KeyboardLayout {
        KeyboardLayout(
            name: newName ?? "\(name) Copy",
            rows: rows.map { $0.duplicated() },
            notes: notes
        )
    }

    /// A small but completely valid layout: every key does something, and the
    /// utility row includes the globe key so the user is never trapped.
    static func starter(named name: String = "New Keyboard") -> KeyboardLayout {
        let letters = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
        let letterKeys = letters.map { character in
            KeyboardKey(
                label: character,
                action: .insertText(character),
                shiftOutput: character.uppercased()
            )
        }
        let utilityKeys: [KeyboardKey] = [
            KeyboardKey(label: "⇧", action: .shift, width: 1.4, isSpecial: true, accessibilityLabel: "Shift"),
            KeyboardKey(label: "space", action: .space, width: 4, isSpecial: true, accessibilityLabel: "Space"),
            KeyboardKey(label: "return", action: .newline, width: 1.6, isSpecial: true, accessibilityLabel: "Return"),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.4, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace"),
            KeyboardKey(label: "🌐", action: .nextKeyboard, width: 1, isSpecial: true, accessibilityLabel: "Next Keyboard")
        ]
        return KeyboardLayout(
            name: name,
            rows: [
                KeyboardRow(name: "Letters", height: 1, keys: letterKeys),
                KeyboardRow(name: "Bottom bar", height: 1.15, keys: utilityKeys)
            ]
        )
    }
}

// MARK: - Haptics / settings

enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case off, light, medium, strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

enum RowJustification: String, Codable, CaseIterable, Identifiable {
    /// Keys stretch to fill the row (classic keyboard look).
    case fill
    /// Very wide keys are capped and the row is centred instead of stretched.
    case capAndCenter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Stretch to fill"
        case .capAndCenter: return "Cap very wide keys"
        }
    }
}

struct KeyboardSettings: Codable, Equatable {

    var haptics: HapticStrength
    var keyClickSound: Bool

    /// Upper-case a single lower-cased letter when Shift is active and the key
    /// has no explicit `shiftOutput`.
    var autoUppercaseOnShift: Bool

    var doubleTapShiftEnablesCapsLock: Bool
    /// Seconds allowed between two Shift taps to count as a double tap.
    var doubleTapWindow: Double

    var longPressEnabled: Bool
    /// Seconds a key must be held before long-press alternatives appear.
    var longPressDelay: Double

    var backspaceRepeatEnabled: Bool
    var backspaceRepeatDelay: Double
    var backspaceRepeatInterval: Double

    /// Append a system globe key at runtime when `needsInputModeSwitchKey` is
    /// true and the active layout has no Next Keyboard key, so the user can
    /// never get stuck inside the keyboard. Never persisted into the layout.
    var autoInsertNextKeyboardKey: Bool

    var rowJustification: RowJustification

    /// Multiplier applied to the theme font size (accessibility).
    var fontScale: Double

    init(
        haptics: HapticStrength = .off,
        keyClickSound: Bool = false,
        autoUppercaseOnShift: Bool = true,
        doubleTapShiftEnablesCapsLock: Bool = true,
        doubleTapWindow: Double = 0.35,
        longPressEnabled: Bool = true,
        longPressDelay: Double = 0.38,
        backspaceRepeatEnabled: Bool = true,
        backspaceRepeatDelay: Double = 0.45,
        backspaceRepeatInterval: Double = 0.09,
        autoInsertNextKeyboardKey: Bool = true,
        rowJustification: RowJustification = .capAndCenter,
        fontScale: Double = 1.0
    ) {
        self.haptics = haptics
        self.keyClickSound = keyClickSound
        self.autoUppercaseOnShift = autoUppercaseOnShift
        self.doubleTapShiftEnablesCapsLock = doubleTapShiftEnablesCapsLock
        self.doubleTapWindow = doubleTapWindow
        self.longPressEnabled = longPressEnabled
        self.longPressDelay = longPressDelay
        self.backspaceRepeatEnabled = backspaceRepeatEnabled
        self.backspaceRepeatDelay = backspaceRepeatDelay
        self.backspaceRepeatInterval = backspaceRepeatInterval
        self.autoInsertNextKeyboardKey = autoInsertNextKeyboardKey
        self.rowJustification = rowJustification
        self.fontScale = fontScale
    }

    private enum CodingKeys: String, CodingKey {
        case haptics, keyClickSound, autoUppercaseOnShift
        case doubleTapShiftEnablesCapsLock, doubleTapWindow
        case longPressEnabled, longPressDelay
        case backspaceRepeatEnabled, backspaceRepeatDelay, backspaceRepeatInterval
        case autoInsertNextKeyboardKey, rowJustification, fontScale
        case capsLockEnabled, soundEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = KeyboardSettings()
        haptics = container.keyraValue(.haptics, fallback.haptics)
        keyClickSound = container.keyraBool(.keyClickSound, container.keyraBool(.soundEnabled, fallback.keyClickSound))
        autoUppercaseOnShift = container.keyraBool(.autoUppercaseOnShift, fallback.autoUppercaseOnShift)
        doubleTapShiftEnablesCapsLock = container.keyraBool(
            .doubleTapShiftEnablesCapsLock,
            container.keyraBool(.capsLockEnabled, fallback.doubleTapShiftEnablesCapsLock)
        )
        doubleTapWindow = container.keyraDouble(.doubleTapWindow, fallback.doubleTapWindow)
        longPressEnabled = container.keyraBool(.longPressEnabled, fallback.longPressEnabled)
        longPressDelay = container.keyraDouble(.longPressDelay, fallback.longPressDelay)
        backspaceRepeatEnabled = container.keyraBool(.backspaceRepeatEnabled, fallback.backspaceRepeatEnabled)
        backspaceRepeatDelay = container.keyraDouble(.backspaceRepeatDelay, fallback.backspaceRepeatDelay)
        backspaceRepeatInterval = container.keyraDouble(.backspaceRepeatInterval, fallback.backspaceRepeatInterval)
        autoInsertNextKeyboardKey = container.keyraBool(.autoInsertNextKeyboardKey, fallback.autoInsertNextKeyboardKey)
        rowJustification = container.keyraValue(.rowJustification, fallback.rowJustification)
        fontScale = container.keyraDouble(.fontScale, fallback.fontScale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(haptics, forKey: .haptics)
        try container.encode(keyClickSound, forKey: .keyClickSound)
        try container.encode(autoUppercaseOnShift, forKey: .autoUppercaseOnShift)
        try container.encode(doubleTapShiftEnablesCapsLock, forKey: .doubleTapShiftEnablesCapsLock)
        try container.encode(doubleTapWindow, forKey: .doubleTapWindow)
        try container.encode(longPressEnabled, forKey: .longPressEnabled)
        try container.encode(longPressDelay, forKey: .longPressDelay)
        try container.encode(backspaceRepeatEnabled, forKey: .backspaceRepeatEnabled)
        try container.encode(backspaceRepeatDelay, forKey: .backspaceRepeatDelay)
        try container.encode(backspaceRepeatInterval, forKey: .backspaceRepeatInterval)
        try container.encode(autoInsertNextKeyboardKey, forKey: .autoInsertNextKeyboardKey)
        try container.encode(rowJustification, forKey: .rowJustification)
        try container.encode(fontScale, forKey: .fontScale)
    }
}

// MARK: - Configuration

/// The complete shared document: what the host app edits and the keyboard reads.
struct KeyboardConfiguration: Codable, Equatable {

    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var layouts: [KeyboardLayout]
    var themes: [KeyboardTheme]
    var activeLayoutID: UUID
    var activeThemeID: UUID
    var settings: KeyboardSettings
    /// Incremented on every save so the keyboard (and diagnostics) can see that
    /// the configuration changed without diffing the whole document.
    var generation: Int
    var updatedAt: Date?

    init(
        schemaVersion: Int = KeyboardConfiguration.currentSchemaVersion,
        layouts: [KeyboardLayout],
        themes: [KeyboardTheme],
        activeLayoutID: UUID,
        activeThemeID: UUID,
        settings: KeyboardSettings = KeyboardSettings(),
        generation: Int = 1,
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.layouts = layouts
        self.themes = themes
        self.activeLayoutID = activeLayoutID
        self.activeThemeID = activeThemeID
        self.settings = settings
        self.generation = generation
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, layouts, themes, activeLayoutID, activeThemeID
        case settings, generation, updatedAt
        // Convenience aliases accepted on import.
        case activeLayout, activeLayoutName, activeTheme, activeThemeName, theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.keyraInt(.schemaVersion, KeyboardConfiguration.currentSchemaVersion)
        layouts = container.keyraValue(.layouts, [KeyboardLayout]())
        themes = container.keyraValue(.themes, [KeyboardTheme]())

        if themes.isEmpty {
            if let single = container.keyraOptional(KeyboardTheme.self, forKey: .theme) {
                themes = [single.withName(single.name.isEmpty ? "Imported Theme" : single.name)]
            } else {
                themes = KeyboardTheme.builtIn
            }
        }

        let explicitLayoutID = container.keyraOptionalUUID(.activeLayoutID)
        let explicitThemeID = container.keyraOptionalUUID(.activeThemeID)
        let activeLayoutName = container.keyraNonEmptyString(.activeLayout)
            ?? container.keyraNonEmptyString(.activeLayoutName)
        let activeThemeName = container.keyraNonEmptyString(.activeTheme)
            ?? container.keyraNonEmptyString(.activeThemeName)

        var resolvedLayoutID = explicitLayoutID
        if resolvedLayoutID == nil, let activeLayoutName {
            resolvedLayoutID = layouts.first { $0.name.caseInsensitiveCompare(activeLayoutName) == .orderedSame }?.id
        }
        if resolvedLayoutID == nil { resolvedLayoutID = layouts.first?.id }
        if resolvedLayoutID == nil { resolvedLayoutID = UUID() }

        var resolvedThemeID = explicitThemeID
        if resolvedThemeID == nil, let activeThemeName {
            resolvedThemeID = themes.first { $0.name.caseInsensitiveCompare(activeThemeName) == .orderedSame }?.id
        }
        if resolvedThemeID == nil { resolvedThemeID = themes.first?.id }
        if resolvedThemeID == nil { resolvedThemeID = UUID() }

        activeLayoutID = resolvedLayoutID ?? UUID()
        activeThemeID = resolvedThemeID ?? UUID()
        settings = container.keyraValue(.settings, KeyboardSettings())
        generation = container.keyraInt(.generation, 1)
        updatedAt = container.keyraOptional(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(layouts, forKey: .layouts)
        try container.encode(themes, forKey: .themes)
        try container.encode(activeLayoutID, forKey: .activeLayoutID)
        try container.encode(activeThemeID, forKey: .activeThemeID)
        try container.encode(settings, forKey: .settings)
        try container.encode(generation, forKey: .generation)
        if let updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }

    // MARK: - Lookups

    var activeLayout: KeyboardLayout {
        layouts.first { $0.id == activeLayoutID } ?? layouts.first ?? KeyboardDefaults.starterLayout
    }

    var activeTheme: KeyboardTheme {
        themes.first { $0.id == activeThemeID } ?? themes.first ?? KeyboardTheme.defaultTheme
    }

    func layout(withID identifier: UUID) -> KeyboardLayout? {
        layouts.first { $0.id == identifier }
    }

    /// Name lookup is case-insensitive and ignores surrounding whitespace.
    func layout(named name: String) -> KeyboardLayout? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return layouts.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    func theme(withID identifier: UUID) -> KeyboardTheme? {
        themes.first { $0.id == identifier }
    }

    /// The layout after / before the active one in stored order (wrapping).
    func layout(after identifier: UUID) -> KeyboardLayout? {
        guard !layouts.isEmpty else { return nil }
        guard let index = layouts.firstIndex(where: { $0.id == identifier }) else {
            return layouts.first
        }
        let next = (index + 1) % layouts.count
        return layouts[next]
    }
}

import SwiftUI

/// Editor for a single key.
///
/// The form is driven by the selected action: an "insert text" key shows its
/// output field, a backspace key shows repeat options, a Shift key shows the
/// Caps Lock settings, a layout switch shows the target picker — and everything
/// irrelevant is hidden.
struct KeyEditorView: View {

    @EnvironmentObject private var store: AppStore
    let layoutID: UUID
    let keyID: UUID

    @State private var showingDeleteConfirm = false

    private var key: KeyboardKey? {
        store.configuration.layout(withID: layoutID)?.key(withID: keyID)
    }

    private var otherLayouts: [KeyboardLayout] {
        store.configuration.layouts.filter { $0.id != layoutID }
    }

    var body: some View {
        Group {
            if let key {
                editor(for: key)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("This key was removed.")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        guard let key else { return "Key" }
        return key.label.isEmpty ? "Key" : "Key “\(key.label)”"
    }

    @ViewBuilder
    private func editor(for key: KeyboardKey) -> some View {
        List {
            // MARK: Label
            Section {
                TextField("Display label", text: binding(\.label, fallback: ""))
                    .autocorrectionDisabled(true)

                TextField("VoiceOver label (optional)", text: optionalBinding(\.accessibilityLabel))
                    .autocorrectionDisabled(true)

                Toggle("Special key styling", isOn: binding(\.isSpecial, fallback: false))

                HStack {
                    Text("What VoiceOver says")
                    Spacer()
                    Text(key.spokenLabel)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .font(.footnote)
            } header: {
                Text("Label")
            } footer: {
                Text("The label is what you see. Leave the VoiceOver label empty and Keyra describes the key from its action — no internal identifiers are ever read out.")
            }

            // MARK: Action
            Section {
                Picker("Action", selection: actionTypeBinding) {
                    ForEach(KeyboardKeyActionType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                Text(key.action.type.explanation)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                actionFields(for: key)
            } header: {
                Text("Action")
            }

            // MARK: Shift
            if key.action.type.usesShiftOutput {
                Section {
                    Toggle("Custom shifted output", isOn: customShiftToggle)
                    if key.shiftOutput != nil {
                        TextField("Shifted output", text: optionalBinding(\.shiftOutput))
                            .autocorrectionDisabled(true)
                    } else {
                        Text(store.settings.autoUppercaseOnShift
                             ? "No custom output: a single lower-case letter is upper-cased while Shift is on."
                             : "No custom output, and automatic upper-casing is off in Setup, so this key types the same text with Shift on.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Shift")
                }
            }

            if key.action == .shift {
                Section {
                    Toggle("Double-tap Shift enables Caps Lock", isOn: settingsBinding(\.doubleTapShiftEnablesCapsLock, fallback: true))
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Double-tap window")
                            Spacer()
                            Text(String(format: "%.2f s", store.settings.doubleTapWindow)).foregroundColor(.secondary)
                        }
                        Slider(value: settingsBinding(\.doubleTapWindow, fallback: 0.35), in: 0.15...0.8, step: 0.05)
                    }
                } header: {
                    Text("Shift behaviour")
                } footer: {
                    Text("Tap Shift once for one shifted character, twice quickly for Caps Lock, and once more to turn it off. These settings are shared by every Shift key.")
                }
            }

            // MARK: Sizing
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Width weight")
                        Spacer()
                        Text(String(format: "%.2f×", key.width)).foregroundColor(.secondary)
                    }
                    Slider(value: binding(\.width, fallback: 1), in: 0.2...12, step: 0.05)
                }

                HStack(spacing: 6) {
                    ForEach([1.0, 1.5, 2.0, 3.0, 5.0], id: \.self) { value in
                        Button(String(format: "%g", value)) {
                            setValue(\.width, value)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Height weight in this row")
                        Spacer()
                        Text(String(format: "%.2f×", key.height)).foregroundColor(.secondary)
                    }
                    Slider(value: binding(\.height, fallback: 1), in: 0.4...2, step: 0.05)
                }
            } header: {
                Text("Size")
            } footer: {
                Text("Width and height are relative weights, never fixed pixels: the keyboard measures the available width on your iPhone and shares it out. A width of 5 makes a space bar; 1 makes a normal key.")
            }

            // MARK: Long press
            Section {
                ForEach(key.longPress) { alternate in
                    LongPressAlternateEditor(
                        alternate: alternate,
                        onChange: { updated in
                            updateAlternate(alternate.id) { $0 = updated }
                        },
                        onDelete: {
                            updateKey { current in
                                current.longPress.removeAll { $0.id == alternate.id }
                            }
                        }
                    )
                }

                if key.longPress.count < KeyboardLimits.maxLongPressAlternates {
                    Button {
                        updateKey { current in
                            current.longPress.append(
                                KeyboardKeyLongPress(
                                    label: "…",
                                    action: .insertText(current.label.isEmpty ? "…" : current.label)
                                )
                            )
                        }
                    } label: {
                        Label("Add a long-press alternative", systemImage: "plus")
                    }
                }
            } header: {
                Text("Long press (\(key.longPress.count))")
            } footer: {
                Text("Hold this key for about half a second and a popup appears above it: slide to the alternative you want and lift. A quick tap always types the key's normal output, so ordinary typing stays reliable.")
            }

            // MARK: Repeat
            if isRepeatable(key.action) {
                Section {
                    Toggle("Repeat while held", isOn: binding(\.repeatsWhenHeld, fallback: false))
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Repeat delay")
                            Spacer()
                            Text(String(format: "%.2f s", store.settings.backspaceRepeatDelay)).foregroundColor(.secondary)
                        }
                        Slider(value: settingsBinding(\.backspaceRepeatDelay, fallback: 0.45), in: 0.15...1.2, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Repeat speed")
                            Spacer()
                            Text(String(format: "%.0f /s", 1.0 / max(0.02, store.settings.backspaceRepeatInterval))).foregroundColor(.secondary)
                        }
                        Slider(value: settingsBinding(\.backspaceRepeatInterval, fallback: 0.09), in: 0.02...0.3, step: 0.01)
                    }
                } header: {
                    Text("Press and hold")
                } footer: {
                    Text("Repeating stops the moment you lift your finger. The repeat timers are owned by the keyboard view and cancelled on release, so nothing keeps deleting in the background.")
                }
            }

            // MARK: Order
            Section {
                HStack(spacing: 8) {
                    Button {
                        store.moveKey(keyID, in: layoutID, by: -1)
                    } label: {
                        Label("Left", systemImage: "arrow.left").font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.moveKey(keyID, in: layoutID, by: 1)
                    } label: {
                        Label("Right", systemImage: "arrow.right").font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.moveKeyAcrossRows(keyID, in: layoutID, direction: -1)
                    } label: {
                        Label("Up", systemImage: "arrow.up").font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.moveKeyAcrossRows(keyID, in: layoutID, direction: 1)
                    } label: {
                        Label("Down", systemImage: "arrow.down").font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    _ = store.duplicateKey(keyID, in: layoutID)
                } label: {
                    Label("Duplicate this key", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete this key", systemImage: "trash")
                }
            } header: {
                Text("Order")
            } footer: {
                Text("These four buttons always work, even if dragging feels awkward.")
            }
        }
        .alert("Delete this key?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteKey(keyID, in: layoutID)
            }
        }
    }

    // MARK: - Action-specific fields

    @ViewBuilder
    private func actionFields(for key: KeyboardKey) -> some View {
        switch key.action {
        case .insertText(let text):
            TextField("Text to type", text: textBinding(get: { text }, set: { setAction(.insertText($0)) }), axis: .vertical)
                .lineLimit(1...6)
                .autocorrectionDisabled(true)
            Text("Anything goes: “->”, “Hello, world!”, “★”, a whole email address or an emoji.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .insertMacro(let text):
            TextField("Snippet", text: textBinding(get: { text }, set: { setAction(.insertMacro($0)) }), axis: .vertical)
                .lineLimit(3...12)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled(true)

            Menu {
                ForEach(KeyboardDefaults.macroTemplates.indices, id: \.self) { index in
                    Button(KeyboardDefaults.macroTemplates[index].name) {
                        setAction(.insertMacro(KeyboardDefaults.macroTemplates[index].text))
                    }
                }
            } label: {
                Label("Use a template", systemImage: "doc.text")
            }

            Text("New lines and spacing are preserved exactly, so signatures and code blocks type correctly.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .cursorMoveByOffset(let offset):
            Stepper(value: cursorOffsetBinding(current: offset), in: -50...50) {
                Text("Move the caret by \(offset) character\(abs(offset) == 1 ? "" : "s")")
            }
            Text("iOS may ignore very large jumps; Keyra keeps the request within the range UITextDocumentProxy supports.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .switchLayout:
            Picker("Target keyboard", selection: switchLayoutBinding) {
                Text("Choose…").tag("")
                ForEach(otherLayouts) { layout in
                    Text(layout.name).tag(layout.name)
                }
            }
            TextField("…or type a name", text: switchLayoutNameBinding)
                .autocorrectionDisabled(true)
            Text(otherLayouts.isEmpty
                 ? "You only have one keyboard so far. Create another one first, then come back and point this key at it."
                 : "Layouts are matched by name, so an exported keyboard keeps working after you import it somewhere else.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .backspace:
            Text("Deletes one character per press using the system text proxy.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .space:
            Text("Types a single space. The label above is only what you see — rename it to “English”, “+”, or anything else.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .newline:
            Text("Types a line break. Some apps treat that as Send or Done rather than Return — that choice belongs to the app, not to the keyboard.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .shift:
            Text("Shift affects text, macro, space and new-line keys. Keys with a custom shifted output use it; otherwise a single lower-case letter is upper-cased.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .nextKeyboard:
            Text("Calls Apple's public keyboard-switching API. Keyra only shows this key when the text field actually needs it, and it adds one at runtime if your layout is missing one, so you can never get stuck.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .cursorLeft, .cursorRight:
            Text("Moves the caret one character. This is different from typing the “←” or “→” character — use an Insert Text key for those.")
                .font(.footnote)
                .foregroundColor(.secondary)

        case .none:
            Text("This key renders but does not do anything. That is fine while you are designing a layout.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ path: WritableKeyPath<KeyboardKey, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.configuration.layout(withID: layoutID)?.key(withID: keyID)?[keyPath: path] ?? fallback },
            set: { newValue in setValue(path, newValue) }
        )
    }

    private func optionalBinding(_ path: WritableKeyPath<KeyboardKey, String?>) -> Binding<String> {
        Binding(
            get: { store.configuration.layout(withID: layoutID)?.key(withID: keyID)?[keyPath: path] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                setValue(path, trimmed.isEmpty ? nil : newValue)
            }
        )
    }

    private func settingsBinding<T>(_ path: WritableKeyPath<KeyboardSettings, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: { newValue in
                var updated = store.settings
                updated[keyPath: path] = newValue
                store.updateSettings(updated)
            }
        )
    }

    private func textBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: get, set: set)
    }

    private var cursorOffsetBinding: Binding<Int> {
        Binding(
            get: {
                if case .cursorMoveByOffset(let offset) = store.configuration.layout(withID: layoutID)?.key(withID: keyID)?.action {
                    return offset
                }
                return -1
            },
            set: { setAction(.cursorMoveByOffset($0)) }
        )
    }

    private var actionTypeBinding: Binding<KeyboardKeyActionType> {
        Binding(
            get: { store.configuration.layout(withID: layoutID)?.key(withID: keyID)?.action.type ?? .insertText },
            set: { changeActionType(to: $0) }
        )
    }

    private var customShiftToggle: Binding<Bool> {
        Binding(
            get: { store.configuration.layout(withID: layoutID)?.key(withID: keyID)?.shiftOutput != nil },
            set: { isOn in
                guard var current = currentKey() else { return }
                if isOn {
                    if current.shiftOutput == nil {
                        current.shiftOutput = current.label.count == 1 ? current.label.uppercased() : current.label
                    }
                } else {
                    current.shiftOutput = nil
                }
                store.updateKey(current, in: layoutID)
            }
        )
    }

    private var switchLayoutBinding: Binding<String> {
        Binding(
            get: {
                guard case .switchLayout(_, let name) = store.configuration.layout(withID: layoutID)?.key(withID: keyID)?.action else { return "" }
                return name ?? ""
            },
            set: { newValue in
                setAction(.switchLayout(layoutID: nil, layoutName: newValue.isEmpty ? nil : newValue))
            }
        )
    }

    private var switchLayoutNameBinding: Binding<String> {
        Binding(
            get: {
                guard case .switchLayout(_, let name) = store.configuration.layout(withID: layoutID)?.key(withID: keyID)?.action else { return "" }
                return name ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                setAction(.switchLayout(layoutID: nil, layoutName: trimmed.isEmpty ? nil : trimmed))
            }
        )
    }

    // MARK: - Mutation helpers

    private func currentKey() -> KeyboardKey? {
        store.configuration.layout(withID: layoutID)?.key(withID: keyID)
    }

    private func setValue<T>(_ path: WritableKeyPath<KeyboardKey, T>, _ value: T) {
        guard var current = currentKey() else { return }
        current[keyPath: path] = value
        store.updateKey(current, in: layoutID)
    }

    private func setAction(_ action: KeyboardKeyAction) {
        guard var current = currentKey() else { return }
        guard current.action != action else { return }
        current.action = action
        store.updateKey(current, in: layoutID)
    }

    private func updateKey(_ transform: (inout KeyboardKey) -> Void) {
        guard var current = currentKey() else { return }
        transform(&current)
        store.updateKey(current, in: layoutID)
    }

    private func updateAlternate(_ alternateID: UUID, transform: (inout KeyboardKeyLongPress) -> Void) {
        updateKey { current in
            guard let index = current.longPress.firstIndex(where: { $0.id == alternateID }) else { return }
            transform(&current.longPress[index])
        }
    }

    private func isRepeatable(_ action: KeyboardKeyAction) -> Bool {
        switch action {
        case .backspace, .cursorLeft, .cursorRight, .cursorMoveByOffset: return true
        default: return false
        }
    }

    /// Switching action keeps as much of the user's work as possible.
    private func changeActionType(to newType: KeyboardKeyActionType) {
        guard var current = currentKey() else { return }
        guard current.action.type != newType else { return }

        var existingText = ""
        switch current.action {
        case .insertText(let text), .insertMacro(let text):
            existingText = text
        default:
            existingText = ""
        }
        if existingText.isEmpty, current.label.count > 1 {
            existingText = current.label
        }

        switch newType {
        case .insertText:
            current.action = .insertText(existingText.isEmpty ? current.label : existingText)
        case .insertMacro:
            current.action = .insertMacro(existingText)
            current.isSpecial = true
        case .backspace:
            current.action = .backspace
            current.isSpecial = true
            current.repeatsWhenHeld = true
            if current.label.isEmpty { current.label = "⌫" }
        case .space:
            current.action = .space
            current.isSpecial = true
            if current.label.isEmpty || current.label == existingText { current.label = "space" }
        case .newline:
            current.action = .newline
            current.isSpecial = true
            if current.label.isEmpty || current.label == existingText { current.label = "return" }
        case .shift:
            current.action = .shift
            current.isSpecial = true
            if current.label.isEmpty { current.label = "⇧" }
        case .nextKeyboard:
            current.action = .nextKeyboard
            current.isSpecial = true
            if current.label.isEmpty { current.label = "🌐" }
        case .cursorLeft:
            current.action = .cursorLeft
            current.isSpecial = true
            current.repeatsWhenHeld = true
            if current.label.isEmpty { current.label = "◀" }
        case .cursorRight:
            current.action = .cursorRight
            current.isSpecial = true
            current.repeatsWhenHeld = true
            if current.label.isEmpty { current.label = "▶" }
        case .cursorMoveByOffset:
            current.action = .cursorMoveByOffset(-1)
        case .switchLayout:
            let target = otherLayouts.first?.name
            current.action = .switchLayout(layoutID: nil, layoutName: target)
            current.isSpecial = true
            if current.label.isEmpty, let target { current.label = target }
        case .none:
            current.action = .none
        }

        store.updateKey(current, in: layoutID)
    }
}

/// Inline editor for one long-press alternative.
struct LongPressAlternateEditor: View {

    let alternate: KeyboardKeyLongPress
    var onChange: (KeyboardKeyLongPress) -> Void
    var onDelete: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case insertText, cursorMove, none
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .insertText: return "Type text"
            case .cursorMove: return "Move caret"
            case .none: return "Do nothing"
            }
        }
    }

    private var kind: Kind {
        switch alternate.action {
        case .insertText, .insertMacro: return .insertText
        case .cursorMoveByOffset, .cursorLeft, .cursorRight: return .cursorMove
        default: return .none
        }
    }

    private var textValue: String {
        switch alternate.action {
        case .insertText(let text), .insertMacro(let text): return text
        default: return ""
        }
    }

    private var offsetValue: Int {
        switch alternate.action {
        case .cursorMoveByOffset(let offset): return offset
        case .cursorLeft: return -1
        case .cursorRight: return 1
        default: return 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Label", text: Binding(
                    get: { alternate.label },
                    set: { newValue in
                        var updated = alternate
                        updated.label = newValue
                        onChange(updated)
                    }
                ))
                .autocorrectionDisabled(true)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .accessibilityLabel(Text("Remove this long-press alternative"))
            }

            Picker("Does", selection: Binding(
                get: { kind },
                set: { newKind in
                    var updated = alternate
                    switch newKind {
                    case .insertText:
                        updated.action = .insertText(textValue.isEmpty ? updated.label : textValue)
                    case .cursorMove:
                        updated.action = .cursorMoveByOffset(offsetValue)
                    case .none:
                        updated.action = .none
                    }
                    onChange(updated)
                }
            )) {
                ForEach(Kind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if kind == .insertText {
                TextField("Text", text: Binding(
                    get: { textValue },
                    set: { newValue in
                        var updated = alternate
                        updated.action = .insertText(newValue)
                        if updated.label.isEmpty || updated.label == "…" { updated.label = newValue }
                        onChange(updated)
                    }
                ))
                .autocorrectionDisabled(true)
                .font(.system(.footnote, design: .monospaced))
            }

            if kind == .cursorMove {
                Stepper("Move by \(offsetValue)", value: Binding(
                    get: { offsetValue },
                    set: { newValue in
                        var updated = alternate
                        updated.action = .cursorMoveByOffset(newValue)
                        onChange(updated)
                    }
                ), in: -50...50)
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }
}

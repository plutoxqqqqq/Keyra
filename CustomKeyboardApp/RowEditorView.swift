import SwiftUI

/// Editor for a single row: its keys, their order, and the row's own settings.
struct RowEditorView: View {

    @EnvironmentObject private var store: AppStore
    let layoutID: UUID
    let rowID: UUID

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingDeleteConfirm = false

    private var row: KeyboardRow? {
        store.configuration.layout(withID: layoutID)?.row(withID: rowID)
    }

    private var rowIndex: Int? {
        store.configuration.layout(withID: layoutID)?.rows.firstIndex { $0.id == rowID }
    }

    var body: some View {
        Group {
            if let row {
                editor(for: row)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("This row was removed.")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        if let name = row?.name, !name.isEmpty { return name }
        if let rowIndex { return "Row \(rowIndex + 1)" }
        return "Row"
    }

    @ViewBuilder
    private func editor(for row: KeyboardRow) -> some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(row.keys) { key in
                            KeyraKeyChip(key: key)
                        }
                        if row.keys.isEmpty {
                            Text("No keys yet")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("This row")
            } footer: {
                Text("Keys share the row's width by relative weight: a key with width 2 takes twice the space of a key with width 1. Any number of keys is allowed.")
            }

            Section {
                ForEach(row.keys) { key in
                    NavigationLink(value: KeyRoute(layoutID: layoutID, keyID: key.id)) {
                        KeyRowSummary(key: key)
                    }
                }
                .onMove { offsets, destination in
                    store.moveKeys(in: rowID, layoutID: layoutID, from: offsets, to: destination)
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let key = row.keys[safe: index] {
                            store.deleteKey(key.id, in: layoutID)
                        }
                    }
                }

                Button {
                    if let keyID = store.addKey(to: rowID, in: layoutID) {
                        _ = keyID
                    }
                } label: {
                    Label("Add a text key", systemImage: "plus")
                }
            } header: {
                Text("Keys (\(row.keys.count))")
            } footer: {
                Text("Drag to reorder, or swipe to delete. Tap a key to change its label, output, width, Shift behaviour and long-press options.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                    ForEach(templates.indices, id: \.self) { index in
                        Button {
                            store.appendKey(templates[index].key, toRow: rowID, in: layoutID)
                        } label: {
                            Text(templates[index].name)
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Add a ready-made key")
            } footer: {
                Text("These are ordinary keys — once added you can edit every detail of them like any other key.")
            }

            Section {
                Button {
                    renameText = row.name ?? "Row \((rowIndex ?? 0) + 1)"
                    showingRename = true
                } label: {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(row.name ?? "Not named").foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Height weight")
                        Spacer()
                        Text(String(format: "%.2f×", row.height)).foregroundColor(.secondary)
                    }
                    Slider(value: heightBinding, in: 0.4...3, step: 0.05)
                }

                HStack(spacing: 10) {
                    Button {
                        store.moveRow(rowID, in: layoutID, by: -1)
                    } label: {
                        Label("Move up", systemImage: "arrow.up")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.moveRow(rowID, in: layoutID, by: 1)
                    } label: {
                        Label("Move down", systemImage: "arrow.down")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    _ = store.duplicateRow(rowID, in: layoutID)
                } label: {
                    Label("Duplicate this row", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete this row", systemImage: "trash")
                }
            } header: {
                Text("Row settings")
            } footer: {
                Text("Height weight is relative: a row with 1.5 is half again as tall as a row with 1. Every row is measured when the keyboard opens, and the keyboard asks iOS for exactly the height it needs.")
            }
        }
        .sheet(isPresented: $showingRename) {
            RenameSheet(
                title: "Name this row",
                placeholder: "e.g. Top row, Symbols, Bottom bar",
                text: $renameText,
                onSave: { name in
                    store.renameRow(name, rowID: rowID, layoutID: layoutID)
                    showingRename = false
                },
                onCancel: { showingRename = false }
            )
        }
        .alert("Delete this row?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteRow(rowID, in: layoutID)
            }
        } message: {
            Text("Every key in the row is removed with it.")
        }
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { row?.height ?? 1 },
            set: { store.setRowHeight($0, rowID: rowID, layoutID: layoutID) }
        )
    }

    /// Ready-made keys offered by the row editor (pure data, no special cases in
    /// the renderer).
    private var templates: [(name: String, key: KeyboardKey)] {
        [
            ("Space", KeyboardKey(label: "space", action: .space, width: 4, isSpecial: true, accessibilityLabel: "Space")),
            ("Backspace", KeyboardKey(label: "⌫", action: .backspace, width: 1.5, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace")),
            ("Shift", KeyboardKey(label: "⇧", action: .shift, width: 1.5, isSpecial: true, accessibilityLabel: "Shift")),
            ("Return", KeyboardKey(label: "return", action: .newline, width: 1.8, isSpecial: true, accessibilityLabel: "Return")),
            ("Next keyboard", KeyboardKey(label: "🌐", action: .nextKeyboard, width: 1.2, isSpecial: true, accessibilityLabel: "Next Keyboard")),
            ("Caret left", KeyboardKey(label: "◀", action: .cursorLeft, width: 1.2, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Move cursor left")),
            ("Caret right", KeyboardKey(label: "▶", action: .cursorRight, width: 1.2, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Move cursor right")),
            ("Tab (4 spaces)", KeyboardKey(label: "tab", action: .insertText("    "), width: 1.4, isSpecial: true, accessibilityLabel: "Insert four spaces")),
            ("Switch keyboard", KeyboardKey(label: "123", action: .switchLayout(layoutID: nil, layoutName: store.configuration.layouts.first { $0.id != layoutID }?.name), width: 1.5, isSpecial: true, accessibilityLabel: "Switch keyboard")),
            ("Emoji 😀", KeyboardKey(label: "😀", action: .insertText("😀"), accessibilityLabel: "Emoji smiling face")),
            ("Arrow →", KeyboardKey(label: "→", action: .insertText("→"), accessibilityLabel: "Insert arrow right")),
            ("Symbol ≠", KeyboardKey(label: "≠", action: .insertText("≠"), accessibilityLabel: "Insert not equal"))
        ]
    }
}

/// Compact summary of a key inside the row editor.
struct KeyRowSummary: View {

    let key: KeyboardKey

    var body: some View {
        HStack(spacing: 10) {
            KeyraKeyChip(key: key)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.label.isEmpty ? "(no label)" : key.label)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(key.action.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "w %.2f", key.width))
                if !key.longPress.isEmpty {
                    Text("\(key.longPress.count) long-press")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

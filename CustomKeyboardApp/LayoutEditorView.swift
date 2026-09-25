import SwiftUI

/// The keyboard builder: preview, checks, rows, and keyboard-level settings.
struct LayoutEditorView: View {

    @EnvironmentObject private var store: AppStore
    let layoutID: UUID

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var exportPayload: ExportPayload?
    @State private var showingDeleteConfirm = false

    private var layout: KeyboardLayout {
        store.configuration.layout(withID: layoutID) ?? store.activeLayout
    }

    private var issues: [KeyboardIssue] {
        store.issues.filter { $0.layoutID == layoutID }
    }

    var body: some View {
        List {
            Section {
                KeyboardPreviewCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section {
                KeyraIssueList(issues: issues)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
            }

            Section {
                ForEach(layout.rows) { row in
                    NavigationLink(value: RowRoute(layoutID: layoutID, rowID: row.id)) {
                        RowSummaryRow(row: row, index: rowIndex(of: row.id))
                    }
                }
                .onMove { offsets, destination in
                    store.moveRows(in: layoutID, from: offsets, to: destination)
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let row = layout.rows[safe: index] {
                            store.deleteRow(row.id, in: layoutID)
                        }
                    }
                }

                Button {
                    if let rowID = store.addRow(to: layoutID) {
                        _ = rowID
                    }
                } label: {
                    Label("Add a row", systemImage: "plus")
                }
            } header: {
                Text("Rows (\(layout.rows.count))")
            } footer: {
                Text("Drag to reorder rows, or swipe to delete. Every row sizes itself: 3 keys and 20 keys are both fine. Rows with no keys are skipped on the real keyboard.")
            }

            Section {
                Button {
                    renameText = layout.name
                    showingRename = true
                } label: {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(layout.name).foregroundColor(.secondary)
                    }
                }

                TextField("Notes for this keyboard", text: notesBinding, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.footnote)

                Button {
                    store.setActive(layoutID: layoutID)
                } label: {
                    HStack {
                        Label("Use this keyboard first", systemImage: "checkmark.circle")
                        Spacer()
                        if layout.id == store.configuration.activeLayoutID {
                            Text("Active").foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Keyra opens the active keyboard. Other keyboards can be reached from a key whose action is “Switch Layout / Layer”.")
            }

            Section {
                Button {
                    if let url = store.exportFile(for: layoutID) {
                        exportPayload = ExportPayload(url: url)
                    }
                } label: {
                    Label("Export this keyboard", systemImage: "square.and.arrow.up")
                }

                Button {
                    _ = store.duplicate(layoutID: layoutID)
                } label: {
                    Label("Duplicate this keyboard", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete this keyboard", systemImage: "trash")
                }
            } header: {
                Text("Share and manage")
            } footer: {
                Text("Exports are plain, readable JSON that can be edited by hand and imported again on another iPhone.")
            }
        }
        .navigationTitle(layout.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.select(layoutID: layoutID)
        }
        .sheet(isPresented: $showingRename) {
            RenameSheet(
                title: "Rename keyboard",
                placeholder: "Keyboard name",
                text: $renameText,
                onSave: { newName in
                    store.rename(layoutID: layoutID, to: newName)
                    showingRename = false
                },
                onCancel: { showingRename = false }
            )
        }
        .sheet(item: $exportPayload) { payload in
            ExportSheet(
                payload: payload,
                json: store.exportJSON(for: layoutID),
                title: layout.name
            )
        }
        .alert("Delete “\(layout.name)”?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.delete(layoutID: layoutID)
            }
        } message: {
            Text("This removes the keyboard from Keyra. A copy in the shared container is updated the next time you save.")
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { layout.notes ?? "" },
            set: { store.setNotes($0, layoutID: layoutID) }
        )
    }

    private func rowIndex(of rowID: UUID) -> Int {
        layout.rows.firstIndex { $0.id == rowID } ?? 0
    }
}

/// One row inside the layout editor.
struct RowSummaryRow: View {

    let row: KeyboardRow
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(rowName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(row.keys.count) keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                if row.keys.isEmpty {
                    KeyraPill(text: "Empty", severity: .warning)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(row.keys) { key in
                        KeyraKeyChip(key: key)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var rowName: String {
        if let name = row.name, !name.isEmpty { return name }
        return "Row \(index + 1)"
    }
}

/// Sheet wrapper for the share/export flow.
struct ExportSheet: View {

    let payload: ExportPayload
    let json: String
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("“\(title)” exported as JSON. Save it to Files, AirDrop it, or copy the text and paste it anywhere.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(item: payload.url) {
                    Label("Share or save to Files", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                KeyraCopyButton(text: json, label: "Copy the JSON")

                ScrollView {
                    Text(json)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Identifiable wrapper so a written file can drive a sheet.
struct ExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// Simple reusable rename / single-field sheet.
struct RenameSheet: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled(true)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// "My Keyboards" — every saved keyboard, with the active one marked.
struct KeyboardListView: View {

    @EnvironmentObject private var store: AppStore

    @State private var path: [LayoutRoute] = []
    @State private var showingCreate = false
    @State private var newKeyboardName: String = ""
    @State private var showingImporter = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let layout = layoutAfterCorruptionRecovery() {
                    Section {
                        KeyraCard(
                            title: "Your saved settings could not be read",
                            systemImage: "exclamationmark.triangle",
                            footnote: "Keyra loaded the built-in keyboards instead. The unreadable file was kept next to the configuration so nothing was destroyed."
                        ) {
                            Button("Show me the built-in keyboards") {
                                path.append(LayoutRoute(id: layout.id))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    ForEach(store.configuration.layouts) { layout in
                        NavigationLink(value: LayoutRoute(id: layout.id)) {
                            KeyboardListRow(
                                layout: layout,
                                isActive: layout.id == store.configuration.activeLayoutID,
                                issueCount: store.issues.filter { $0.layoutID == layout.id }.count
                            )
                        }
                    }
                    .onMove { offsets, destination in
                        store.moveLayouts(from: offsets, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if let layout = store.configuration.layouts[safe: index] {
                                store.delete(layoutID: layout.id)
                            }
                        }
                    }
                } header: {
                    Text("My keyboards")
                } footer: {
                    Text("The keyboard starts on the keyboard marked Active. Everything here is stored on this iPhone only.")
                }

                Section {
                    Button {
                        newKeyboardName = store.uniqueLayoutName(basedOn: "New Keyboard")
                        showingCreate = true
                    } label: {
                        Label("Create a keyboard", systemImage: "plus.circle")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import a keyboard (.json)", systemImage: "square.and.arrow.down")
                    }

                    NavigationLink {
                        PresetsView()
                    } label: {
                        Label("Start from a preset", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("Add")
                }
            }
            .navigationTitle("Keyra")
            .navigationDestination(for: LayoutRoute.self) { route in
                LayoutEditorView(layoutID: route.id)
            }
            .navigationDestination(for: RowRoute.self) { route in
                RowEditorView(layoutID: route.layoutID, rowID: route.rowID)
            }
            .navigationDestination(for: KeyRoute.self) { route in
                KeyEditorView(layoutID: route.layoutID, keyID: route.keyID)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newKeyboardName = store.uniqueLayoutName(basedOn: "New Keyboard")
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Create a keyboard"))
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateKeyboardSheet(
                    name: $newKeyboardName,
                    onCreate: { name in
                        let identifier = store.addLayout(named: name)
                        showingCreate = false
                        path.append(LayoutRoute(id: identifier))
                    },
                    onAddPresets: {
                        store.addBuiltInPresets()
                        showingCreate = false
                    },
                    onCancel: { showingCreate = false }
                )
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        store.importFile(at: url)
                    }
                case .failure(let error):
                    store.banner = AppBanner(
                        title: "Import cancelled",
                        detail: error.localizedDescription,
                        severity: .warning
                    )
                }
            }
        }
    }

    private func layoutAfterCorruptionRecovery() -> KeyboardLayout? {
        guard store.recoveredFromCorruption else { return nil }
        return store.configuration.layouts.first
    }
}

/// One row in the keyboard list.
struct KeyboardListRow: View {

    let layout: KeyboardLayout
    let isActive: Bool
    let issueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(layout.name)
                    .font(.body)
                    .fontWeight(.medium)
                if isActive {
                    KeyraPill(text: "Active", systemImage: "checkmark.circle")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("\(layout.rows.count) rows")
                Text("·")
                Text("\(layout.keyCount) keys")
                if issueCount > 0 {
                    Text("·")
                    KeyraPill(text: "\(issueCount) to check", severity: .warning)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // A tiny taste of the layout without rendering the whole keyboard.
            HStack(spacing: 3) {
                ForEach(Array(layout.rows.prefix(3))) { row in
                    HStack(spacing: 2) {
                        ForEach(Array(row.keys.prefix(6))) { key in
                            Text(key.label)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(minWidth: 12)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Sheet used to create a keyboard or pull in the presets.
struct CreateKeyboardSheet: View {

    @Binding var name: String
    var onCreate: (String) -> Void
    var onAddPresets: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Keyboard name")
                } footer: {
                    Text("You can rename it later. Layouts are referenced by name, so give the ones you will jump between clear names such as ABC, 123 or MATH.")
                }

                Section {
                    Button("Start with a blank keyboard") {
                        onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Keyboard" : name)
                    }
                    Button("Add the five built-in keyboards") {
                        onAddPresets()
                    }
                }
            }
            .navigationTitle("New keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

extension Array {
    /// Bounds-checked access; layout indexes come from UI events and must not trap.
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// Import and export keyboards as readable JSON.
struct ImportExportView: View {

    @EnvironmentObject private var store: AppStore

    @State private var selectedLayoutID: UUID?
    @State private var showingImporter = false
    @State private var pastedJSON: String = ""
    @State private var exportPayload: ExportPayload?
    @State private var showingEverything = false

    private var layouts: [KeyboardLayout] { store.configuration.layouts }

    private var selectedLayout: KeyboardLayout? {
        if let selectedLayoutID, let match = store.configuration.layout(withID: selectedLayoutID) {
            return match
        }
        return layouts.first
    }

    var body: some View {
        List {
            Section {
                if layouts.isEmpty {
                    Text("You have no keyboards to export yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Keyboard", selection: selectionBinding) {
                        ForEach(layouts) { layout in
                            Text(layout.name).tag(layout.id)
                        }
                    }

                    Button {
                        if let layout = selectedLayout, let url = store.exportFile(for: layout.id) {
                            exportPayload = ExportPayload(url: url)
                        }
                    } label: {
                        Label("Export the selected keyboard", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        if let url = store.exportAllFile() {
                            exportPayload = ExportPayload(url: url)
                        }
                    } label: {
                        Label("Export every keyboard and theme", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Exports are plain JSON: readable, editable and small. Use them as a backup, or to move a keyboard to another iPhone.")
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import from Files", systemImage: "square.and.arrow.down")
                }

                TextEditor(text: $pastedJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1))
                    )

                Button {
                    let data = Data(pastedJSON.utf8)
                    guard !pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        store.banner = AppBanner(title: "Nothing to import", detail: "Paste a keyboard's JSON first.", severity: .warning)
                        return
                    }
                    store.importData(data, origin: "pasted text")
                    pastedJSON = ""
                } label: {
                    Label("Import the pasted JSON", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Importing never overwrites an existing keyboard: it is added with a fresh identity, and renamed if the name is already taken. Anything unreadable is rejected with a description of the exact problem.")
            }

            Section {
                Button {
                    showingEverything = true
                } label: {
                    Label("How the JSON is structured", systemImage: "curlybraces")
                }
            } header: {
                Text("Format")
            }
        }
        .navigationTitle("Import / Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportPayload) { payload in
            ExportSheet(
                payload: payload,
                json: selectedLayout.map { store.exportJSON(for: $0.id) } ?? store.exportConfigurationJSON(),
                title: selectedLayout?.name ?? "Keyra"
            )
        }
        .sheet(isPresented: $showingEverything) {
            JSONFormatSheet()
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
                store.banner = AppBanner(title: "Import cancelled", detail: error.localizedDescription, severity: .warning)
            }
        }
    }

    private var selectionBinding: Binding<UUID> {
        Binding(
            get: { selectedLayout?.id ?? layouts.first?.id ?? UUID() },
            set: { selectedLayoutID = $0 }
        )
    }
}

/// Explains the file format with a real, valid example.
struct JSONFormatSheet: View {

    @Environment(\.dismiss) private var dismiss

    private var example: String {
        """
        {
          "keyraFormatVersion": 1,
          "kind": "layout",
          "layout": {
            "name": "Math Keyboard",
            "rows": [
              {
                "height": 1,
                "keys": [
                  {
                    "label": "π",
                    "width": 1,
                    "action": { "type": "insertText", "text": "π" }
                  },
                  {
                    "label": "√",
                    "width": 1,
                    "action": { "type": "insertText", "text": "√" },
                    "longPress": [
                      { "label": "∛", "action": { "type": "insertText", "text": "∛" } }
                    ]
                  },
                  {
                    "label": "◀",
                    "width": 1.5,
                    "isSpecial": true,
                    "action": { "type": "cursorMoveByOffset", "offset": -1 }
                  },
                  {
                    "label": "123",
                    "width": 1.5,
                    "isSpecial": true,
                    "action": { "type": "switchLayout", "layoutName": "Symbols" }
                  },
                  {
                    "label": "sig",
                    "width": 2,
                    "isSpecial": true,
                    "action": {
                      "type": "insertMacro",
                      "text": "Hello,\\n\\nKind regards,\\nJoseph"
                    }
                  }
                ]
              }
            ]
          }
        }
        """
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A keyboard is a list of rows; a row is a list of keys; a key has a label and an action. There is no fixed number of rows or keys anywhere in Keyra.")
                        .font(.subheadline)
                }

                Section("Action types") {
                    ForEach(KeyboardKeyActionType.allCases) { type in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName).font(.subheadline).fontWeight(.medium)
                            Text(type.explanation)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal) {
                        Text(example)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    KeyraCopyButton(text: example, label: "Copy the example")
                } header: {
                    Text("Example")
                } footer: {
                    Text("Width and height are relative weights. Colours are hex strings such as #1B1030 or #1B1030FF. Everything is optional except a label or an action.")
                }
            }
            .navigationTitle("The JSON format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

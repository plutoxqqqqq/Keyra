import SwiftUI

/// Built-in keyboards. Each one is ordinary data, which is the proof that the
/// layout engine is fully dynamic.
struct PresetsView: View {

    @EnvironmentObject private var store: AppStore
    @State private var showingResetConfirm = false

    private var presets: [KeyboardLayout] { KeyboardDefaults.presets }

    var body: some View {
        List {
            Section {
                ForEach(presets.indices, id: \.self) { index in
                    NavigationLink(value: PresetRoute(index: index)) {
                        PresetRow(preset: presets[index])
                    }
                }
            } header: {
                Text("Built-in keyboards")
            } footer: {
                Text("Tap one to try the real keyboard renderer on it. Adding a preset copies it, so your own edits never touch the originals.")
            }

            Section {
                Button {
                    store.addBuiltInPresets()
                } label: {
                    Label("Add all five to my keyboards", systemImage: "square.grid.2x2.fill")
                }

                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Restore everything to defaults", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Restoring replaces every keyboard and theme with the originals. Export anything you want to keep first.")
            }
        }
        .navigationTitle("Presets")
        .navigationDestination(for: PresetRoute.self) { route in
            PresetDetailView(presetIndex: route.index)
        }
        .alert("Restore the built-in keyboards?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                store.resetEverything()
            }
        } message: {
            Text("Every keyboard and theme you created is replaced by the five built-in keyboards and four themes.")
        }
    }
}

/// Summary row for a preset.
struct PresetRow: View {

    let preset: KeyboardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(preset.name)
                .font(.body)
                .fontWeight(.medium)

            Text("\(preset.rows.count) rows · \(preset.keyCount) keys · widest row \(widestRow) keys")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 3) {
                ForEach(Array(preset.rows.prefix(3))) { row in
                    HStack(spacing: 2) {
                        ForEach(Array(row.keys.prefix(7))) { key in
                            Text(key.label)
                                .font(.system(size: 9))
                                .lineLimit(1)
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

    private var widestRow: Int {
        preset.rows.map { $0.keys.count }.max() ?? 0
    }
}

/// A preset preview that runs the real engine against a private text buffer.
struct PresetDetailView: View {

    @EnvironmentObject private var store: AppStore
    let presetIndex: Int

    @StateObject private var session: PreviewSession

    init(presetIndex: Int) {
        self.presetIndex = presetIndex
        let presets = KeyboardDefaults.presets
        let index = (presetIndex >= 0 && presetIndex < presets.count) ? presetIndex : 0
        let preset = presets.isEmpty ? KeyboardDefaults.starterLayout : presets[index]
        let configuration = KeyboardConfiguration(
            layouts: [preset],
            themes: KeyboardTheme.builtIn,
            activeLayoutID: preset.id,
            activeThemeID: KeyboardTheme.builtIn.first?.id ?? UUID(),
            settings: KeyboardSettings()
        )
        _session = StateObject(wrappedValue: PreviewSession(configuration: configuration))
    }

    private var preset: KeyboardLayout {
        let presets = KeyboardDefaults.presets
        let index = (presetIndex >= 0 && presetIndex < presets.count) ? presetIndex : 0
        return presets.isEmpty ? KeyboardDefaults.starterLayout : presets[index]
    }

    var body: some View {
        List {
            Section {
                KeyboardSizedPreview(model: session.model, maximumHeight: 520)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } footer: {
                Text("This is the real keyboard view. Type into it freely — the text stays in memory on this screen and never leaves your iPhone.")
            }

            Section {
                HStack(alignment: .top) {
                    Text(session.typed.isEmpty ? "Nothing typed yet." : session.typed)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(session.typed.isEmpty ? .secondary : .primary)
                        .lineLimit(6)
                    Spacer(minLength: 0)
                }
                Button {
                    session.clear()
                } label: {
                    Label("Clear", systemImage: "delete.left")
                }
            } header: {
                Text("What it typed")
            }

            if let notes = preset.notes {
                Section("How to use it") {
                    Text(notes)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("What is inside") {
                KeyraValueRow(label: "Rows", value: "\(preset.rows.count)")
                KeyraValueRow(label: "Keys", value: "\(preset.keyCount)")
                KeyraValueRow(label: "Long-press keys", value: "\(preset.allKeys.filter { !$0.longPress.isEmpty }.count)")
                KeyraValueRow(label: "Layout switches", value: "\(preset.allKeys.filter { $0.action.type == .switchLayout }.count)")
            }

            Section {
                Button {
                    _ = store.addLayout(fromPreset: preset)
                } label: {
                    Label("Add this keyboard", systemImage: "plus.circle")
                }
            } footer: {
                Text("Adds a fresh copy you can edit. The preset itself stays unchanged.")
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

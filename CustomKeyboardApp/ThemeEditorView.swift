import SwiftUI

/// Theme list: every saved theme, with the active one marked.
struct ThemeEditorView: View {

    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                ForEach(store.configuration.themes) { theme in
                    NavigationLink(value: ThemeRoute(id: theme.id)) {
                        ThemeListRow(theme: theme, isActive: theme.id == store.configuration.activeThemeID)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let theme = store.configuration.themes[safe: index] {
                            store.deleteTheme(theme.id)
                        }
                    }
                }

                Button {
                    _ = store.addTheme()
                } label: {
                    Label("New theme", systemImage: "plus")
                }
            } header: {
                Text("Themes")
            } footer: {
                Text("One theme is used by every keyboard, so all of your layouts look consistent. Swipe a theme away to delete it, or duplicate one and change a few colours.")
            }
        }
        .navigationTitle("Themes")
        .navigationDestination(for: ThemeRoute.self) { route in
            ThemeDetailView(themeID: route.id)
        }
    }
}

/// One row in the theme list, showing the theme's own colours.
struct ThemeListRow: View {

    let theme: KeyboardTheme
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            MiniKeyboardSwatch(theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if isActive {
                        KeyraPill(text: "Active", systemImage: "checkmark.circle")
                    }
                }
                Text("Corner \(Int(theme.cornerRadius)) · spacing \(Int(theme.keySpacing)) · \(Int(theme.fontSize))pt")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// A tiny fake keyboard drawn from the theme's colours — cheap and instant.
struct MiniKeyboardSwatch: View {

    let theme: KeyboardTheme

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(column == 2 ? theme.specialKeyColor.swiftUIColor : theme.keyColor.swiftUIColor)
                            .frame(width: 7, height: 6)
                    }
                }
            }
        }
        .padding(4)
        .background(theme.background.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityHidden(true)
    }
}

/// Full theme editor with a live keyboard preview.
struct ThemeDetailView: View {

    @EnvironmentObject private var store: AppStore
    let themeID: UUID

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var exportPayload: ExportPayload?
    @State private var showingDeleteConfirm = false

    private var theme: KeyboardTheme {
        store.configuration.theme(withID: themeID) ?? store.activeTheme
    }

    var body: some View {
        List {
            Section {
                KeyboardSizedPreview(model: store.previewModel, maximumHeight: 360, showsNotice: false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } header: {
                Text("Live preview")
            } footer: {
                Text("The preview uses the keyboard you are editing in the Keyboards tab, drawn with this theme. Changes appear as you make them — nothing is saved to the keyboard until it is applied.")
            }

            Section {
                Button {
                    renameText = theme.name
                    showingRename = true
                } label: {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(theme.name).foregroundColor(.secondary)
                    }
                }
            }

            Section("Colours") {
                KeyraColorField(title: "Keyboard background", color: themeBinding(\.background))
                KeyraColorField(title: "Key background", color: themeBinding(\.keyColor))
                KeyraColorField(title: "Special key background", color: themeBinding(\.specialKeyColor))
                KeyraColorField(title: "Pressed key", color: themeBinding(\.pressedKeyColor))
                KeyraColorField(title: "Key text", color: themeBinding(\.textColor))
                KeyraColorField(title: "Special key text", color: themeBinding(\.specialTextColor))
                KeyraColorField(title: "Key border", color: themeBinding(\.borderColor))
            }

            Section("Shape and spacing") {
                ThemeSlider(title: "Corner radius", value: themeBinding(\.cornerRadius), range: 0...26, format: "%.1f pt")
                ThemeSlider(title: "Key spacing", value: themeBinding(\.keySpacing), range: 0...24, format: "%.1f pt")
                ThemeSlider(title: "Row spacing", value: themeBinding(\.rowSpacing), range: 0...32, format: "%.1f pt")
                ThemeSlider(title: "Border width", value: themeBinding(\.borderWidth), range: 0...4, format: "%.2f pt")
                ThemeSlider(title: "Key opacity", value: themeBinding(\.keyOpacity), range: 0.1...1, format: "%.2f")
                ThemeSlider(title: "Shadow radius", value: themeBinding(\.keyShadowRadius), range: 0...16, format: "%.1f pt")
                ThemeSlider(title: "Shadow strength", value: themeBinding(\.keyShadowOpacity), range: 0...0.8, format: "%.2f")
                ThemeSlider(title: "Press effect", value: themeBinding(\.pressedScale), range: 0.85...1.05, format: "%.2f×")
            }

            Section("Text") {
                ThemeSlider(title: "Key label size", value: themeBinding(\.fontSize), range: 10...36, format: "%.0f pt")
                Picker("Font weight", selection: themeBinding(\.fontWeight)) {
                    ForEach(KeyboardFontWeight.allCases) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }
                ThemeSlider(title: "Text scaling", value: settingsBinding(\.fontScale), range: 0.7...1.6, format: "%.2f×")
                Toggle("Dark appearance hint", isOn: themeBinding(\.isDarkAppearance))
            }

            Section {
                Button {
                    store.setActive(themeID: themeID)
                } label: {
                    HStack {
                        Label("Use this theme", systemImage: "checkmark.circle")
                        Spacer()
                        if theme.id == store.configuration.activeThemeID {
                            Text("Active").foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    _ = store.duplicate(themeID: themeID)
                } label: {
                    Label("Duplicate this theme", systemImage: "plus.square.on.square")
                }

                Button {
                    writeExport()
                } label: {
                    Label("Export this theme", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete this theme", systemImage: "trash")
                }
            } header: {
                Text("Manage")
            }
        }
        .navigationTitle(theme.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.previewModel.previewThemeOverride = theme
        }
        .onDisappear {
            store.previewModel.previewThemeOverride = nil
        }
        .onChange(of: theme) { newValue in
            store.previewModel.previewThemeOverride = newValue
        }
        .sheet(isPresented: $showingRename) {
            RenameSheet(
                title: "Rename theme",
                placeholder: "Theme name",
                text: $renameText,
                onSave: { newName in
                    var updated = theme
                    updated.name = newName
                    store.updateTheme(updated)
                    showingRename = false
                },
                onCancel: { showingRename = false }
            )
        }
        .sheet(item: $exportPayload) { payload in
            ExportSheet(payload: payload, json: JSONImportExport.exportTheme(theme), title: theme.name)
        }
        .alert("Delete “\(theme.name)”?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteTheme(themeID)
            }
        } message: {
            Text("Keyboards using it move to the first remaining theme.")
        }
    }

    private func themeBinding<T>(_ path: WritableKeyPath<KeyboardTheme, T>) -> Binding<T> {
        Binding(
            get: { theme[keyPath: path] },
            set: { newValue in
                var updated = theme
                updated[keyPath: path] = newValue
                store.updateTheme(updated)
            }
        )
    }

    private func writeExport() {
        let data = JSONImportExport.exportData(KeyboardExportEnvelope(kind: "theme", theme: theme))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyra-theme-\(theme.name.lowercased()).json")
        do {
            try data.write(to: url, options: [.atomic])
            exportPayload = ExportPayload(url: url)
        } catch {
            store.banner = AppBanner(title: "Could not write the theme file", detail: error.localizedDescription, severity: .error)
        }
    }

    private func settingsBinding<T>(_ path: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: { newValue in
                var updated = store.settings
                updated[keyPath: path] = newValue
                store.updateSettings(updated)
            }
        )
    }
}

/// A labelled slider used throughout the theme editor.
struct ThemeSlider: View {

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            Slider(value: $value, in: range)
        }
    }
}

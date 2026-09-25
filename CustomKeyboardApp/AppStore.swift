import SwiftUI
import Foundation

/// A message shown as a banner in the host app (import results, save problems…).
struct AppBanner: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var severity: KeyboardIssueSeverity

    init(id: UUID = UUID(), title: String, detail: String, severity: KeyboardIssueSeverity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

/// The host application's model.
///
/// Owns the shared configuration, applies every edit through the same validator
/// the keyboard uses, persists (debounced) into the shared container when it is
/// available, and keeps the live preview in step with the editor.
final class AppStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var configuration: KeyboardConfiguration
    @Published private(set) var issues: [KeyboardIssue]
    @Published private(set) var sharedContainerAvailable: Bool
    @Published private(set) var storageDescription: String
    @Published private(set) var sharedContainerDiagnosis: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var keyboardStatus: KeyboardRuntimeStatus?
    @Published private(set) var recoveredFromCorruption: Bool

    /// Which keyboard the editor is working on.
    @Published var selectedLayoutID: UUID
    /// Text typed into the live preview (never leaves the device).
    @Published var previewText: String = ""
    @Published var banner: AppBanner?

    // MARK: - Collaborators

    let store: KeyboardConfigurationStore
    let previewModel: KeyboardViewModel

    private let previewProxy: ObservingTextProxy
    private var pendingSave: DispatchWorkItem?

    // MARK: - Init

    init(store: KeyboardConfigurationStore? = nil) {
        let resolvedStore: KeyboardConfigurationStore
        let diagnosis: String?

        if let store {
            resolvedStore = store
            diagnosis = store.sharedContainerAvailable ? nil : KeyboardConfigurationStore.resolveStorage().diagnosis
        } else {
            let resolved = KeyboardConfigurationStore.defaultStoreWithDiagnosis()
            resolvedStore = resolved.store
            diagnosis = resolved.diagnosis
        }

        let result = resolvedStore.load()
        let proxy = ObservingTextProxy()

        self.store = resolvedStore
        self.configuration = result.configuration
        self.issues = KeyboardValidator.issues(for: result.configuration)
        self.sharedContainerAvailable = result.sharedContainerAvailable
        self.storageDescription = result.locationDescription
        self.sharedContainerDiagnosis = diagnosis
        self.recoveredFromCorruption = result.didRecoverFromCorruption
        self.selectedLayoutID = result.configuration.activeLayoutID
        self.previewProxy = proxy
        self.previewModel = KeyboardViewModel(
            configuration: result.configuration,
            proxy: proxy,
            onEffect: { _ in }
        )

        proxy.onChange = { [weak self] in
            self?.refreshPreviewText()
        }

        // Reading repaired the stored data (old schema, clamped values…) so write
        // the cleaned copy back instead of leaving the problem on disk.
        if result.needsSave {
            scheduleSave()
        }
    }

    // MARK: - Derived values

    var activeLayout: KeyboardLayout { configuration.activeLayout }

    var activeTheme: KeyboardTheme { configuration.activeTheme }

    var editingLayout: KeyboardLayout {
        configuration.layout(withID: selectedLayoutID) ?? activeLayout
    }

    var editingLayoutIssues: [KeyboardIssue] {
        issues.filter { $0.layoutID == nil || $0.layoutID == selectedLayoutID }
    }

    var settings: KeyboardSettings { configuration.settings }

    var hasErrors: Bool { issues.contains { $0.severity == .error } }

    var statusSummary: String {
        if sharedContainerAvailable {
            return "Shared with the keyboard"
        }
        return "Not shared with the keyboard"
    }

    // MARK: - Selection

    func select(layoutID: UUID) {
        selectedLayoutID = layoutID
        if previewModel.layout.id != layoutID {
            previewModel.activateLayout(id: layoutID)
        }
    }

    func setActive(layoutID: UUID) {
        update { $0.activeLayoutID = layoutID }
        select(layoutID: layoutID)
    }

    // MARK: - Layouts

    @discardableResult
    func addLayout(named name: String? = nil) -> UUID {
        let layout = KeyboardLayout.starter(named: name ?? uniqueLayoutName(basedOn: "New Keyboard"))
        update { $0.layouts.append(layout) }
        select(layoutID: layout.id)
        return layout.id
    }

    @discardableResult
    func addLayout(fromPreset preset: KeyboardLayout) -> UUID {
        var copy = preset.duplicated(named: uniqueLayoutName(basedOn: preset.name))
        copy.id = UUID()
        update { $0.layouts.append(copy) }
        select(layoutID: copy.id)
        return copy.id
    }

    @discardableResult
    func duplicate(layoutID: UUID) -> UUID? {
        guard let source = configuration.layout(withID: layoutID) else { return nil }
        let copy = source.duplicated(named: uniqueLayoutName(basedOn: "\(source.name) Copy"))
        update { $0.layouts.append(copy) }
        select(layoutID: copy.id)
        return copy.id
    }

    func delete(layoutID: UUID) {
        guard configuration.layouts.count > 1 else {
            banner = AppBanner(
                title: "Keep at least one keyboard",
                detail: "Keyra always needs one keyboard available for the extension to show.",
                severity: .warning
            )
            return
        }
        update { configuration in
            configuration.layouts.removeAll { $0.id == layoutID }
            if configuration.activeLayoutID == layoutID, let first = configuration.layouts.first {
                configuration.activeLayoutID = first.id
            }
        }
        if selectedLayoutID == layoutID {
            select(layoutID: configuration.activeLayoutID)
        }
    }

    func rename(layoutID: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            configuration.layouts[index].name = trimmed
        }
    }

    func setNotes(_ notes: String, layoutID: UUID) {
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.layouts[index].notes = trimmed.isEmpty ? nil : trimmed
        }
    }

    func moveLayouts(from offsets: IndexSet, to destination: Int) {
        update { configuration in
            configuration.layouts.move(fromOffsets: offsets, toOffset: destination)
        }
    }

    func uniqueLayoutName(basedOn base: String) -> String {
        let existing = Set(configuration.layouts.map { $0.name.lowercased() })
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Keyboard" : trimmed
        if !existing.contains(root.lowercased()) { return root }
        var index = 2
        while existing.contains("\(root) \(index)".lowercased()) { index += 1 }
        return "\(root) \(index)"
    }

    // MARK: - Rows

    @discardableResult
    func addRow(to layoutID: UUID) -> UUID? {
        guard configuration.layout(withID: layoutID) != nil else { return nil }
        let row = KeyboardRow(
            name: nil,
            height: 1,
            keys: [
                KeyboardKey(
                    label: "space",
                    action: .space,
                    width: 3,
                    isSpecial: true,
                    accessibilityLabel: "Space"
                )
            ]
        )
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            configuration.layouts[index].rows.append(row)
        }
        return row.id
    }

    func deleteRow(_ rowID: UUID, in layoutID: UUID) {
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            configuration.layouts[index].rows.removeAll { $0.id == rowID }
        }
    }

    @discardableResult
    func duplicateRow(_ rowID: UUID, in layoutID: UUID) -> UUID? {
        guard let layout = configuration.layout(layoutID),
              let row = layout.row(withID: rowID) else { return nil }
        let copy = row.duplicated()
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[index].rows.firstIndex(where: { $0.id == rowID }) else { return }
            configuration.layouts[index].rows.insert(copy, at: rowIndex + 1)
        }
        return copy.id
    }

    func moveRows(in layoutID: UUID, from offsets: IndexSet, to destination: Int) {
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            configuration.layouts[index].rows.move(fromOffsets: offsets, toOffset: destination)
        }
    }

    /// Guaranteed-safe reordering used by the Move Up / Move Down buttons.
    func moveRow(_ rowID: UUID, in layoutID: UUID, by offset: Int) {
        update { configuration in
            guard let index = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[index].rows.firstIndex(where: { $0.id == rowID }) else { return }
            let target = rowIndex + offset
            guard target >= 0, target < configuration.layouts[index].rows.count else { return }
            let row = configuration.layouts[index].rows.remove(at: rowIndex)
            configuration.layouts[index].rows.insert(row, at: target)
        }
    }

    func setRowHeight(_ height: Double, rowID: UUID, layoutID: UUID) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }) else { return }
            configuration.layouts[layoutIndex].rows[rowIndex].height = height
        }
    }

    func renameRow(_ name: String, rowID: UUID, layoutID: UUID) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.layouts[layoutIndex].rows[rowIndex].name = trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - Keys

    @discardableResult
    func addKey(to rowID: UUID, in layoutID: UUID, at index: Int? = nil) -> UUID? {
        let key = KeyboardKey(label: "a", action: .insertText("a"), shiftOutput: "A")
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }) else { return }
            let position = index ?? configuration.layouts[layoutIndex].rows[rowIndex].keys.count
            let clamped = max(0, min(position, configuration.layouts[layoutIndex].rows[rowIndex].keys.count))
            configuration.layouts[layoutIndex].rows[rowIndex].keys.insert(key, at: clamped)
        }
        return key.id
    }

    /// Appends a ready-made key (used by the row editor's "add special key" bar).
    /// The identifier is always regenerated so a template key is never shared.
    func appendKey(_ template: KeyboardKey, toRow rowID: UUID, in layoutID: UUID) {
        var copy = template
        copy.id = UUID()
        copy.longPress = template.longPress.map {
            KeyboardKeyLongPress(id: UUID(), label: $0.label, action: $0.action)
        }
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }) else { return }
            configuration.layouts[layoutIndex].rows[rowIndex].keys.append(copy)
        }
    }

    func deleteKey(_ keyID: UUID, in layoutID: UUID) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            for rowIndex in configuration.layouts[layoutIndex].rows.indices {
                configuration.layouts[layoutIndex].rows[rowIndex].keys.removeAll { $0.id == keyID }
            }
        }
    }

    @discardableResult
    func duplicateKey(_ keyID: UUID, in layoutID: UUID) -> UUID? {
        guard let layout = configuration.layout(withID: layoutID),
              let source = layout.key(withID: keyID),
              let rowID = layout.rowID(containing: keyID) else { return nil }
        let copy = source.duplicated()
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }),
                  let keyIndex = configuration.layouts[layoutIndex].rows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else { return }
            configuration.layouts[layoutIndex].rows[rowIndex].keys.insert(copy, at: keyIndex + 1)
        }
        return copy.id
    }

    /// Replaces a key by identifier. Every key edit funnels through here.
    func updateKey(_ key: KeyboardKey, in layoutID: UUID) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            for rowIndex in configuration.layouts[layoutIndex].rows.indices {
                if let keyIndex = configuration.layouts[layoutIndex].rows[rowIndex].keys.firstIndex(where: { $0.id == key.id }) {
                    configuration.layouts[layoutIndex].rows[rowIndex].keys[keyIndex] = key
                    return
                }
            }
        }
    }

    func moveKeys(in rowID: UUID, layoutID: UUID, from offsets: IndexSet, to destination: Int) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }),
                  let rowIndex = configuration.layouts[layoutIndex].rows.firstIndex(where: { $0.id == rowID }) else { return }
            configuration.layouts[layoutIndex].rows[rowIndex].keys.move(fromOffsets: offsets, toOffset: destination)
        }
    }

    /// Horizontal reorder inside one row (the guaranteed-safe fallback to drag).
    func moveKey(_ keyID: UUID, in layoutID: UUID, by offset: Int) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            for rowIndex in configuration.layouts[layoutIndex].rows.indices {
                guard let keyIndex = configuration.layouts[layoutIndex].rows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else { continue }
                let target = keyIndex + offset
                guard target >= 0, target < configuration.layouts[layoutIndex].rows[rowIndex].keys.count else { return }
                let key = configuration.layouts[layoutIndex].rows[rowIndex].keys.remove(at: keyIndex)
                configuration.layouts[layoutIndex].rows[rowIndex].keys.insert(key, at: target)
                return
            }
        }
    }

    /// Moves a key to the previous (-1) or next (+1) row.
    func moveKeyAcrossRows(_ keyID: UUID, in layoutID: UUID, direction: Int) {
        update { configuration in
            guard let layoutIndex = configuration.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            let rows = configuration.layouts[layoutIndex].rows
            for rowIndex in rows.indices {
                guard let keyIndex = rows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else { continue }
                let targetRow = rowIndex + direction
                guard targetRow >= 0, targetRow < rows.count else { return }
                let key = configuration.layouts[layoutIndex].rows[rowIndex].keys.remove(at: keyIndex)
                let insertAt = min(keyIndex, configuration.layouts[layoutIndex].rows[targetRow].keys.count)
                configuration.layouts[layoutIndex].rows[targetRow].keys.insert(key, at: insertAt)
                return
            }
        }
    }

    // MARK: - Themes

    @discardableResult
    func addTheme(named name: String? = nil) -> UUID {
        var theme = KeyboardTheme.defaultTheme.duplicated(named: name ?? "New Theme")
        theme.id = UUID()
        update { $0.themes.append(theme) }
        return theme.id
    }

    @discardableResult
    func duplicate(themeID: UUID) -> UUID? {
        guard let theme = configuration.theme(withID: themeID) else { return nil }
        let copy = theme.duplicated()
        update { $0.themes.append(copy) }
        return copy.id
    }

    func deleteTheme(_ themeID: UUID) {
        guard configuration.themes.count > 1 else {
            banner = AppBanner(title: "Keep at least one theme", detail: "The keyboard always needs a theme to draw with.", severity: .warning)
            return
        }
        update { configuration in
            configuration.themes.removeAll { $0.id == themeID }
            if configuration.activeThemeID == themeID, let first = configuration.themes.first {
                configuration.activeThemeID = first.id
            }
        }
    }

    func updateTheme(_ theme: KeyboardTheme) {
        update { configuration in
            guard let index = configuration.themes.firstIndex(where: { $0.id == theme.id }) else { return }
            configuration.themes[index] = KeyboardValidator.sanitizeTheme(theme)
        }
    }

    func setActive(themeID: UUID) {
        update { $0.activeThemeID = themeID }
    }

    // MARK: - Settings

    func updateSettings(_ newSettings: KeyboardSettings) {
        update { $0.settings = newSettings }
    }

    // MARK: - Presets

    func addBuiltInPresets() {
        var names = Set(configuration.layouts.map { $0.name.lowercased() })
        var additions: [KeyboardLayout] = []

        for preset in KeyboardDefaults.presets {
            var candidate = preset.name
            var suffix = 2
            while names.contains(candidate.lowercased()) {
                candidate = "\(preset.name) \(suffix)"
                suffix += 1
            }
            names.insert(candidate.lowercased())
            var copy = preset.duplicated(named: candidate)
            copy.id = UUID()
            additions.append(copy)
        }

        update { $0.layouts.append(contentsOf: additions) }
        banner = AppBanner(
            title: additions.count == 1 ? "Added 1 preset" : "Added \(additions.count) presets",
            detail: "Copies were renamed where they would have clashed, so nothing you already made was overwritten.",
            severity: .info
        )
    }

    func resetEverything() {
        let fresh = KeyboardDefaults.configuration()
        configuration = fresh
        issues = KeyboardValidator.issues(for: fresh)
        selectedLayoutID = fresh.activeLayoutID
        previewModel.reload(configuration: fresh)
        previewModel.activateLayout(id: fresh.activeLayoutID)
        scheduleSave()
        banner = AppBanner(
            title: "Restored the built-in keyboards",
            detail: "QWERTY, Symbols, Math, Emoji and Coding are back, along with the four built-in themes.",
            severity: .info
        )
    }

    // MARK: - Import / export

    func exportJSON(for layoutID: UUID) -> String {
        guard let layout = configuration.layout(withID: layoutID) else {
            return JSONImportExport.exportConfiguration(configuration)
        }
        return JSONImportExport.exportLayout(layout, theme: activeTheme)
    }

    func exportConfigurationJSON() -> String {
        JSONImportExport.exportConfiguration(configuration)
    }

    /// Writes an export to the temporary directory and returns its URL so it can
    /// be shared with the Files app or any other app.
    func exportFile(for layoutID: UUID) -> URL? {
        guard let layout = configuration.layout(withID: layoutID) else { return nil }
        let envelope = KeyboardExportEnvelope(kind: "layout", layout: layout, theme: activeTheme)
        let data = JSONImportExport.exportData(envelope)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(JSONImportExport.fileName(for: layout))
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            banner = AppBanner(title: "Could not write the export file", detail: error.localizedDescription, severity: .error)
            return nil
        }
    }

    func exportAllFile() -> URL? {
        let data = JSONImportExport.exportData(KeyboardExportEnvelope(kind: "configuration", configuration: configuration))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(JSONImportExport.fileName(forConfiguration: configuration))
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            banner = AppBanner(title: "Could not write the export file", detail: error.localizedDescription, severity: .error)
            return nil
        }
    }

    /// Reading is bounded so a huge or hostile file cannot stall the app.
    private func readData(from url: URL) -> Data? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > KeyboardConfigurationStore.maximumReadableBytes {
            banner = AppBanner(
                title: "That file is too large",
                detail: "Keyra reads keyboard files up to \(KeyboardConfigurationStore.maximumReadableBytes / (1024 * 1024)) MB.",
                severity: .error
            )
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func importFile(at url: URL) {
        guard let data = readData(from: url) else {
            if banner == nil {
                banner = AppBanner(title: "Could not read the file", detail: "The file could not be opened.", severity: .error)
            }
            return
        }
        importData(data, origin: url.lastPathComponent)
    }

    func importData(_ data: Data, origin: String) {
        // Decide what this file is by shape, not by file extension.
        if isFullConfigurationElsewhere(data) {
            do {
                let imported = try JSONImportExport.importConfiguration(from: data)
                configuration = imported.configuration
                issues = KeyboardValidator.issues(for: imported.configuration)
                selectedLayoutID = imported.configuration.activeLayoutID
                previewModel.reload(configuration: imported.configuration)
                scheduleSave()
                banner = AppBanner(
                    title: "Imported a full configuration",
                    detail: "This replaced every keyboard and theme with the contents of \(origin)." + warningSummary(imported.warnings),
                    severity: imported.warnings.isEmpty ? .info : .warning
                )
                return
            } catch let error as KeyboardImportError {
                banner = AppBanner(title: "That file could not be imported", detail: error.errorDescription ?? "Unknown problem.", severity: .error)
                return
            } catch {
                banner = AppBanner(title: "That file could not be imported", detail: error.localizedDescription, severity: .error)
                return
            }
        }

        do {
            let imported = try JSONImportExport.importLayout(from: data)
            var layout = imported.layout
            layout.name = uniqueLayoutName(basedOn: layout.name)

            // A theme travelling with the keyboard becomes the active theme, so
            // the imported keyboard looks the way it was designed.
            var importedTheme = imported.theme
            if var theme = importedTheme {
                theme.name = uniqueThemeName(basedOn: theme.name)
                importedTheme = theme
            }

            update { configuration in
                configuration.layouts.append(layout)
                if let theme = importedTheme {
                    configuration.themes.append(theme)
                    configuration.activeThemeID = theme.id
                }
            }
            select(layoutID: layout.id)

            let themeNote = importedTheme.map { " Its theme “\($0.name)” was added and is now active." } ?? ""
            banner = AppBanner(
                title: "Imported “\(layout.name)”",
                detail: "\(layout.rows.count) rows, \(layout.keyCount) keys from \(origin)."
                    + themeNote
                    + warningSummary(imported.warnings),
                severity: imported.warnings.isEmpty ? .info : .warning
            )
        } catch let error as KeyboardImportError {
            banner = AppBanner(title: "That file could not be imported", detail: error.errorDescription ?? "Unknown problem.", severity: .error)
        } catch {
            banner = AppBanner(title: "That file could not be imported", detail: error.localizedDescription, severity: .error)
        }
    }

    /// Theme names must stay unique for the same reason layout names do.
    func uniqueThemeName(basedOn base: String) -> String {
        let existing = Set(configuration.themes.map { $0.name.lowercased() })
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Theme" : trimmed
        if !existing.contains(root.lowercased()) { return root }
        var index = 2
        while existing.contains("\(root) \(index)".lowercased()) { index += 1 }
        return "\(root) \(index)"
    }

    private func isFullConfigurationElsewhere(_ data: Data) -> Bool {
        // A file is treated as a full configuration only when it says so.
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            return false
        }
        if let kind = root["kind"] as? String, kind.lowercased() == "configuration" { return true }
        return (root["layouts"] as? [Any]) != nil
    }

    private func warningSummary(_ warnings: [String]) -> String {
        guard !warnings.isEmpty else { return "" }
        if warnings.count == 1 { return " " + warnings[0] }
        return " \(warnings.count) notes: " + warnings.prefix(3).joined(separator: " · ")
    }

    // MARK: - Persistence

    /// Saves at most a few times per second while the user drags sliders.
    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let saved = try store.save(configuration)
            configuration = saved
            lastSavedAt = Date()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    func reloadFromDisk() {
        let result = store.load()
        configuration = result.configuration
        issues = KeyboardValidator.issues(for: result.configuration)
        recoveredFromCorruption = result.didRecoverFromCorruption
        sharedContainerAvailable = result.sharedContainerAvailable
        storageDescription = result.locationDescription
        if configuration.layout(withID: selectedLayoutID) == nil {
            selectedLayoutID = configuration.activeLayoutID
        }
        previewModel.reload(configuration: configuration)
        refreshKeyboardStatus()
    }

    func refreshKeyboardStatus() {
        keyboardStatus = store.loadStatus()
    }

    // MARK: - Live preview

    func refreshPreviewText() {
        let text = previewProxy.text
        if text != previewText { previewText = text }
    }

    func clearPreviewText() {
        previewProxy.clear()
        refreshPreviewText()
    }

    /// Types through the real engine so the preview exercises the same code path
    /// as the keyboard on a phone.
    func typeIntoPreview(_ sample: String) {
        previewModel.performImmediately(
            KeyboardKey(label: sample, action: .insertText(sample))
        )
    }

    // MARK: - Edit plumbing

    /// Applies a change, re-validates with the *same* validator the keyboard
    /// uses, refreshes the preview and queues a save.
    private func update(_ transform: (inout KeyboardConfiguration) -> Void) {
        var next = configuration
        transform(&next)
        let repaired = KeyboardValidator.sanitize(next)
        configuration = repaired.configuration
        issues = KeyboardValidator.issues(for: repaired.configuration)
        finishEdit()
    }

    private func finishEdit(select newSelection: UUID? = nil) {
        if let newSelection {
            selectedLayoutID = newSelection
        }
        if configuration.layout(withID: selectedLayoutID) == nil {
            selectedLayoutID = configuration.activeLayoutID
        }
        previewModel.reload(configuration: configuration)
        if previewModel.layout.id != selectedLayoutID {
            previewModel.activateLayout(id: selectedLayoutID)
        }
        scheduleSave()
    }
}

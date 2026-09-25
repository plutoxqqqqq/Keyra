import SwiftUI

/// Keyboard setup, shared-container diagnostics, typing behaviour and data.
struct SetupView: View {

    @EnvironmentObject private var store: AppStore

    private var containerID: String { KeyboardConfigurationStore.containerIdentifier() }

    var body: some View {
        List {
            statusSection
            sharedContainerSection
            typingSection
            shiftSection
            dataSection
            privacySection
            aboutSection
        }
        .navigationTitle("Setup")
        .onAppear {
            store.refreshKeyboardStatus()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            if let status = store.keyboardStatus {
                KeyraValueRow(label: "Keyboard has opened", value: "Yes")
                KeyraValueRow(label: "Last opened", value: status.summary)
                KeyraValueRow(
                    label: "Shared container",
                    value: status.appGroupReachable ? "Reachable" : "Not reachable",
                    tint: status.appGroupReachable ? .green : .orange
                )
                KeyraValueRow(
                    label: "Allow Full Access",
                    value: status.hasFullAccess ? "Granted" : "Off",
                    tint: status.hasFullAccess ? .green : .orange
                )
                KeyraValueRow(label: "Layouts the keyboard can see", value: "\(status.layoutCount)")
                KeyraValueRow(label: "Keys on the active keyboard", value: "\(status.keyCount)")
                if let note = status.note {
                    KeyraValueRow(label: "Note", value: note, tint: .orange)
                }
                KeyraValueRow(label: "Extension version", value: status.extensionVersion ?? "unknown")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("The keyboard has not reported in yet. This is normal before you have used it once.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button {
                    store.refreshKeyboardStatus()
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Keyboard status")
        } footer: {
            Text("iOS does not let an app switch its own keyboard on, so Keyra cannot report “enabled” — it reports what the keyboard itself last saw. If nothing appears here, the keyboard has not been opened yet.")
        }
    }

    // MARK: - Shared container

    private var sharedContainerSection: some View {
        Section {
            KeyraValueRow(label: "App Group", value: containerID, monospaced: true)
            KeyraValueRow(
                label: "Available to the app",
                value: store.sharedContainerAvailable ? "Yes" : "No",
                tint: store.sharedContainerAvailable ? .green : .orange
            )
            KeyraValueRow(label: "Storage", value: store.storageDescription)

            if let status = store.keyboardStatus, !status.appGroupReachable {
                Text("The keyboard last opened without access to the shared container, so it used its built-in keyboards. Enable Allow Full Access for Keyra, then open Keyra again.")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.sharedContainerAvailable, let diagnosis = store.sharedContainerDiagnosis {
                Text(diagnosis)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KeyraCopyButton(text: containerID, label: "Copy the App Group ID")
        } header: {
            Text("Sharing layouts with the keyboard")
        } footer: {
            Text("Keyra stores your keyboards in one JSON file. For the keyboard extension to read that same file, three things must all be true: the App Group entitlement must be present in the signed app (SideStore: enable “App Groups” for Keyra), the extension must declare RequestsOpenAccess (it does), and you must turn on Allow Full Access in Settings → General → Keyboard → Keyboards → Keyra. If any of them is missing the keyboard still works — it simply falls back to the built-in keyboards, and this screen tells you so.")
        }
    }

    // MARK: - Typing

    private var typingSection: some View {
        Section {
            Picker("Key haptics", selection: settingsBinding(\.haptics)) {
                ForEach(HapticStrength.allCases) { strength in
                    Text(strength.displayName).tag(strength)
                }
            }

            Toggle("Key click sound", isOn: settingsBinding(\.keyClickSound))

            Toggle("Long-press alternatives", isOn: settingsBinding(\.longPressEnabled))
            if store.settings.longPressEnabled {
                slider(
                    title: "Hold time before the popup",
                    value: settingsBinding(\.longPressDelay),
                    range: 0.2...1.0,
                    format: "%.2f s"
                )
            }

            Toggle("Hold backspace to keep deleting", isOn: settingsBinding(\.backspaceRepeatEnabled))
            if store.settings.backspaceRepeatEnabled {
                slider(
                    title: "Delay before repeating",
                    value: settingsBinding(\.backspaceRepeatDelay),
                    range: 0.15...1.2,
                    format: "%.2f s"
                )
                slider(
                    title: "Repeat interval",
                    value: settingsBinding(\.backspaceRepeatInterval),
                    range: 0.02...0.3,
                    format: "%.2f s"
                )
            }

            Toggle("Add a globe key when a keyboard needs one", isOn: settingsBinding(\.autoInsertNextKeyboardKey))

            Picker("Very wide keys", selection: settingsBinding(\.rowJustification)) {
                ForEach(RowJustification.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } header: {
            Text("Typing")
        } footer: {
            Text("Haptics use the standard iOS feedback generator and the key click uses the system keyboard sound — no bundled audio, no private APIs. The globe key is added at runtime only when the text field actually needs it, and it never changes your saved layout.")
        }
    }

    // MARK: - Shift

    private var shiftSection: some View {
        Section {
            Toggle("Upper-case single letters while Shift is on", isOn: settingsBinding(\.autoUppercaseOnShift))
            Toggle("Double-tap Shift for Caps Lock", isOn: settingsBinding(\.doubleTapShiftEnablesCapsLock))
            slider(title: "Double-tap window", value: settingsBinding(\.doubleTapWindow), range: 0.15...0.8, format: "%.2f s")
            slider(title: "Keyboard text scaling", value: settingsBinding(\.fontScale), range: 0.7...1.6, format: "%.2f×")
        } header: {
            Text("Shift and text size")
        } footer: {
            Text("Automatic upper-casing only ever affects a single lower-case letter. If a key has its own shifted output (é, ≠, ★) that value always wins.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            KeyraValueRow(label: "Keyboards", value: "\(store.configuration.layouts.count)")
            KeyraValueRow(label: "Themes", value: "\(store.configuration.themes.count)")
            KeyraValueRow(label: "Saved version", value: "\(store.configuration.generation)")
            KeyraValueRow(
                label: "Last saved",
                value: store.lastSavedAt.map { Self.timeFormatter.string(from: $0) } ?? "not yet"
            )
            if let error = store.saveErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            NavigationLink {
                ImportExportView()
            } label: {
                Label("Import / export keyboards", systemImage: "square.and.arrow.up.on.square")
            }

            Button {
                store.resetEverything()
            } label: {
                Label("Restore the built-in keyboards", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Everything is stored locally in \(store.storageDescription). Nothing is uploaded anywhere, and there is no account, no analytics and no network code in this project.")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            PrivacyLine(text: "No keylogging. The keyboard only inserts the text you configure — it never records, stores or transmits what you type.")
            PrivacyLine(text: "No network. Neither the app nor the keyboard makes any network request. There is no backend.")
            PrivacyLine(text: "No tracking. No analytics, no advertising identifiers, no crash reporting of typed content.")
            PrivacyLine(text: "No unnecessary permissions. Keyra never asks for contacts, microphone, camera, location or photos.")
            PrivacyLine(text: "Full Access is only used for the App Group shared container, so your edited layouts can reach the keyboard. It is not needed for typing itself.")
        } header: {
            Text("Privacy")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About Keyra", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

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

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            Slider(value: value, in: range)
        }
    }
}

/// One privacy statement line.
struct PrivacyLine: View {

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// About screen: what this is, how it is built, and the exact limits.
struct AboutView: View {

    var body: some View {
        List {
            Section {
                Text("Keyra is a native iPhone keyboard you build yourself.")
                    .font(.headline)
                Text("The app is the builder: add rows, add keys, choose what each key does, pick colours, save, and the keyboard extension types exactly that. Nothing about the layout is hardcoded — QWERTY, Symbols, Math, Emoji and Coding are ordinary data you can rewrite or delete.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("How it is built") {
                KeyraValueRow(label: "Host app", value: "SwiftUI")
                KeyraValueRow(label: "Keyboard extension", value: "UIInputViewController + SwiftUI")
                KeyraValueRow(label: "Shared model", value: "Codable value types")
                KeyraValueRow(label: "Storage", value: "App Group JSON file")
                KeyraValueRow(label: "Version", value: Bundle.main.appVersionString)
            }

            Section("Public APIs used") {
                bullet("textDocumentProxy.insertText(_:)")
                bullet("textDocumentProxy.deleteBackward()")
                bullet("textDocumentProxy.adjustTextPosition(byCharacterOffset:)")
                bullet("advanceToNextInputMode() and needsInputModeSwitchKey")
                bullet("UIImpactFeedbackGenerator, UIDevice.playInputClick()")
            }

            Section {
                Text("Keyra does not use private APIs, does not fake keyboard switching, and never claims a caret operation that iOS does not support. Caret movement is limited to what UITextDocumentProxy offers, and inserting a “←” character is a separate action from moving the caret.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Honest limits")
            }

            Section {
                Text("SideStore re-signs this app for your own Apple ID. A free Apple account can have only a small number of app IDs signed at once, and the signing expires after a few days, so re-signing occasionally is normal. The keyboard travels inside the app — it is not a second app to install.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("SideStore")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension Bundle {
    var appVersionString: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

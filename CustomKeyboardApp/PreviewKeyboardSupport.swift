import SwiftUI

/// Wraps the in-memory proxy so the host app can show exactly what the preview
/// keyboard just typed. The buffer never leaves the device and is never written
/// to disk.
final class ObservingTextProxy: KeyboardTextProxy {

    let inner: InMemoryTextProxy
    var onChange: (() -> Void)?

    init(inner: InMemoryTextProxy = InMemoryTextProxy()) {
        self.inner = inner
    }

    func insertText(_ text: String) {
        inner.insertText(text)
        onChange?()
    }

    func deleteBackward() {
        inner.deleteBackward()
        onChange?()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        inner.adjustTextPosition(byCharacterOffset: offset)
        onChange?()
    }

    var documentContextBeforeInput: String? { inner.documentContextBeforeInput }
    var documentContextAfterInput: String? { inner.documentContextAfterInput }
    var hasDocumentText: Bool { inner.hasDocumentText }
    var needsInputModeSwitchKey: Bool { inner.needsInputModeSwitchKey }
    var hasFullAccess: Bool { inner.hasFullAccess }

    var text: String { inner.text }

    func clear() {
        inner.clear()
        onChange?()
    }
}

/// A self-contained keyboard session: its own engine, its own in-memory text
/// buffer. Used to preview a preset without touching the user's configuration.
final class PreviewSession: ObservableObject {

    let model: KeyboardViewModel
    let proxy: ObservingTextProxy

    @Published private(set) var typed: String = ""

    init(configuration: KeyboardConfiguration, theme: KeyboardTheme? = nil) {
        let proxy = ObservingTextProxy()
        self.proxy = proxy
        self.model = KeyboardViewModel(configuration: configuration, proxy: proxy)
        if let theme {
            self.model.previewThemeOverride = theme
        }
        proxy.onChange = { [weak self] in
            guard let self else { return }
            let text = self.proxy.text
            if text != self.typed { self.typed = text }
        }
    }

    func clear() {
        proxy.clear()
    }
}

/// The real keyboard view, sized to fit the layout it is showing.
struct KeyboardSizedPreview: View {

    @ObservedObject var model: KeyboardViewModel
    var isLandscape: Bool = false
    var maximumHeight: CGFloat = 480
    var showsNotice: Bool = true

    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        KeyboardRootView(
            model: model,
            isLandscape: isLandscape,
            showsBackground: true,
            bottomInset: 0,
            showsNotice: showsNotice
        )
        .frame(height: height)
        .background(KeyraWidthReporter(width: $measuredWidth))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Keyboard preview"))
    }

    private var height: CGFloat {
        let width = measuredWidth > 1 ? measuredWidth : 390
        let natural = model.preferredHeight(width: Double(width), isLandscape: isLandscape, bottomInset: 0)
        return max(48, min(maximumHeight, CGFloat(natural)))
    }
}

/// The preview panel used in the layout editor: the keyboard, what it typed, and
/// a reset button.
struct KeyboardPreviewCard: View {

    @EnvironmentObject private var store: AppStore
    var maximumHeight: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live preview")
                    .font(.headline)
                Spacer()
                Text("\(store.editingLayout.rows.count) rows · \(store.editingLayout.keyCount) keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Text(store.previewText.isEmpty ? "Tap the preview keyboard — what it types appears here." : store.previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(store.previewText.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            KeyboardSizedPreview(model: store.previewModel, maximumHeight: maximumHeight)

            HStack {
                Button {
                    store.clearPreviewText()
                } label: {
                    Label("Clear", systemImage: "delete.left")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)

                Button {
                    store.typeIntoPreview("Keyra")
                } label: {
                    Label("Type a sample", systemImage: "keyboard")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text("This is the real keyboard engine and the real layout data — the preview runs your key actions, Shift, Caps Lock, layout switching and long presses exactly as the extension does.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

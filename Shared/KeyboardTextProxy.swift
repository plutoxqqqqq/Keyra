import Foundation

/// The small slice of `UITextDocumentProxy` the keyboard engine actually needs.
///
/// The engine talks to this protocol instead of UIKit directly, which means the
/// exact same action code runs in three places: the real keyboard extension, the
/// host app's live preview, and the unit tests. Nothing is faked — the extension
/// adapter just forwards to Apple's `UITextDocumentProxy`.
protocol KeyboardTextProxy: AnyObject {

    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)

    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var hasDocumentText: Bool { get }

    /// Mirrors `UIInputViewController.needsInputModeSwitchKey`.
    var needsInputModeSwitchKey: Bool { get }
    /// Mirrors `UIInputViewController.hasFullAccess` (required for shared
    /// container access in a keyboard extension).
    var hasFullAccess: Bool { get }
}

/// A complete, correct in-memory implementation of the text proxy.
///
/// Used by the unit tests and by the host app's live preview, so typing in the
/// preview exercises the real engine and the real insertion rules.
final class InMemoryTextProxy: KeyboardTextProxy {

    /// Safety cap so a pathological layout (or a stuck key) cannot grow the
    /// preview buffer without limit.
    static let maximumLength = 4096

    private(set) var text: String
    private var caret: Int

    var needsInputModeSwitchKey: Bool
    var hasFullAccess: Bool

    init(text: String = "", needsInputModeSwitchKey: Bool = true, hasFullAccess: Bool = true) {
        self.text = text
        self.caret = text.count
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
        self.hasFullAccess = hasFullAccess
    }

    // MARK: - Proxy

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        var characters = Array(self.text)
        let clampedCaret = max(0, min(caret, characters.count))
        let incoming = Array(text)
        characters.insert(contentsOf: incoming, at: clampedCaret)
        if characters.count > InMemoryTextProxy.maximumLength {
            characters = Array(characters.prefix(InMemoryTextProxy.maximumLength))
        }
        self.text = String(characters)
        caret = min(characters.count, clampedCaret + incoming.count)
    }

    func deleteBackward() {
        guard caret > 0 else { return }
        var characters = Array(text)
        let index = min(caret, characters.count)
        guard index > 0 else { return }
        characters.remove(at: index - 1)
        text = String(characters)
        caret = index - 1
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        // iOS itself limits how far this can move; clamp to a sane range.
        let bounded = max(-512, min(512, offset))
        let characters = Array(text)
        caret = max(0, min(characters.count, caret + bounded))
    }

    var documentContextBeforeInput: String? {
        let characters = Array(text)
        guard caret > 0, caret <= characters.count else { return nil }
        return String(characters[0..<caret])
    }

    var documentContextAfterInput: String? {
        let characters = Array(text)
        guard caret < characters.count else { return nil }
        return String(characters[caret..<characters.count])
    }

    var hasDocumentText: Bool { !text.isEmpty }

    // MARK: - Test / preview helpers

    var caretIndex: Int { caret }

    func replaceText(_ newValue: String) {
        text = newValue
        caret = newValue.count
    }

    func clear() {
        text = ""
        caret = 0
    }
}

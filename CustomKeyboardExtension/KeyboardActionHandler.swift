import UIKit

/// Forwards the keyboard engine's text operations to Apple's public
/// `UITextDocumentProxy`.
///
/// The proxy object is deliberately *not* cached: Apple documents that it is only
/// valid while the input view is visible, so every call goes through the live
/// view controller.
final class KeyboardInputAdapter: KeyboardTextProxy {

    weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    // MARK: - KeyboardTextProxy

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        controller?.textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard offset != 0 else { return }
        controller?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    var documentContextBeforeInput: String? {
        controller?.textDocumentProxy.documentContextBeforeInput
    }

    var documentContextAfterInput: String? {
        controller?.textDocumentProxy.documentContextAfterInput
    }

    var hasDocumentText: Bool {
        controller?.textDocumentProxy.hasText ?? false
    }

    var needsInputModeSwitchKey: Bool {
        controller?.needsInputModeSwitchKey ?? true
    }

    var hasFullAccess: Bool {
        controller?.hasFullAccess ?? false
    }
}

/// Plays the optional key feedback using public APIs only.
///
/// * Haptics use `UIImpactFeedbackGenerator` (documented as usable from keyboard
///   extensions). Generators are prepared so the first tap is not late.
/// * Sounds use `UIDevice.playInputClick()`, the documented way for a custom
///   keyboard to play the system key click, which requires the input view
///   controller to adopt `UIInputViewAudioFeedback`.
final class KeyboardFeedbackPlayer {

    private var lightGenerator: UIImpactFeedbackGenerator?
    private var mediumGenerator: UIImpactFeedbackGenerator?
    private var strongGenerator: UIImpactFeedbackGenerator?

    /// Called when the keyboard appears so the Taptic Engine is warmed up.
    func prepare() {
        prepareGeneratorsIfNeeded()
        lightGenerator?.prepare()
        mediumGenerator?.prepare()
        strongGenerator?.prepare()
    }

    func playHaptic(_ strength: HapticStrength) {
        guard let style = strength.impactStyle else { return }
        let generator = generator(for: style)
        generator.impactOccurred()
        generator.prepare()
    }

    func playKeyClick() {
        UIDevice.current.playInputClick()
    }

    private func prepareGeneratorsIfNeeded() {
        if lightGenerator == nil { lightGenerator = UIImpactFeedbackGenerator(style: .light) }
        if mediumGenerator == nil { mediumGenerator = UIImpactFeedbackGenerator(style: .medium) }
        if strongGenerator == nil { strongGenerator = UIImpactFeedbackGenerator(style: .heavy) }
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        prepareGeneratorsIfNeeded()
        switch style {
        case .light:
            return lightGenerator ?? UIImpactFeedbackGenerator(style: .light)
        case .heavy:
            return strongGenerator ?? UIImpactFeedbackGenerator(style: .heavy)
        default:
            return mediumGenerator ?? UIImpactFeedbackGenerator(style: .medium)
        }
    }
}

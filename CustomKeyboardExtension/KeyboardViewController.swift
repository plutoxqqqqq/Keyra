import UIKit
import SwiftUI

/// The keyboard extension's principal class.
///
/// Responsibilities (UIKit's half of the split):
/// * own `UIInputViewController` / `UITextDocumentProxy` / lifecycle,
/// * ask for the right input-view height based on the layout's real geometry,
/// * load the shared configuration off the main thread and hand it to the
///   shared view model,
/// * execute effects that need UIKit (next keyboard, haptics, click sound),
/// * report a heartbeat so the host app can show what is really happening.
///
/// Everything visible is SwiftUI, rendered by `KeyboardRootView` — the same view
/// the host app's preview uses.
final class KeyboardViewController: UIInputViewController {

    // MARK: - Properties

    private var model: KeyboardViewModel?
    private var inputAdapter: KeyboardInputAdapter?
    private var hostingController: UIHostingController<KeyboardRootView>?
    private let feedback = KeyboardFeedbackPlayer()
    private var store: KeyboardConfigurationStore = KeyboardConfigurationStore.defaultStore()
    private var lastLoadedConfiguration: KeyboardConfiguration?
    private var heightConstraint: NSLayoutConstraint?
    private var lastAppliedHeight: Double = 0
    private var isLandscape: Bool = false
    private var hasReportedStatus = false

    private var topPadding: Double { 6 }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false

        let adapter = KeyboardInputAdapter(controller: self)
        inputAdapter = adapter

        // Start from the built-in configuration so the very first frame is
        // already a working keyboard, then swap in the stored one.
        let initial = KeyboardDefaults.configuration()
        let viewModel = KeyboardViewModel(
            configuration: initial,
            proxy: adapter,
            onEffect: { [weak self] effect in
                self?.handle(effect: effect)
            }
        )
        model = viewModel
        lastLoadedConfiguration = initial

        installKeyboardView()

        // Loading touches the file system and decodes JSON: never on the main
        // thread, and never able to block the first render.
        reloadConfigurationFromStore(announceResult: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateOrientationFlag()
        model?.showNotice("")
        hasReportedStatus = false
        reloadConfigurationFromStore(announceResult: false)
        model?.refreshRenderedLayout()
        feedback.prepare()
        reportStatusIfPossible()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportStatusIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateOrientationFlag()
        updateHeightConstraint()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateOrientationFlag()
            self?.updateHeightConstraint()
        }
    }

    deinit {
        heightConstraint?.isActive = false
    }

    // MARK: - View installation

    private func installKeyboardView() {
        guard let model else { return }

        let root = KeyboardRootView(
            model: model,
            isLandscape: isLandscape,
            showsBackground: true,
            bottomInset: 0,
            showsNotice: true
        )
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(topPadding)),
            hosting.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: CGFloat(preferredInputViewHeight()))
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
    }

    /// The height the keyboard asks iOS for: the layout's real content height
    /// plus the home-indicator inset, never more than a fraction of the screen.
    private func preferredInputViewHeight() -> Double {
        guard let model else { return 216 }

        let width = Double(view.bounds.width) > 1 ? Double(view.bounds.width) : Double(screenWidthEstimate)
        let content = model.preferredHeight(width: width, isLandscape: isLandscape, topInset: topPadding, bottomInset: 0)
        let withSafeArea = content + Double(view.safeAreaInsets.bottom)
        return KeyboardMetrics.clampedKeyboardHeight(withSafeArea, screenHeight: availableScreenHeight)
    }

    private func updateHeightConstraint() {
        guard let heightConstraint else { return }
        let desired = preferredInputViewHeight()
        guard abs(desired - lastAppliedHeight) > 0.5 else { return }
        lastAppliedHeight = desired
        heightConstraint.constant = CGFloat(desired)
    }

    private func updateOrientationFlag() {
        let width = Double(view.bounds.width)
        let height = Double(view.bounds.height)
        let landscape = width > height && height > 1
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        rebuildRootView()
    }

    /// Rebuilds the SwiftUI root so orientation-dependent geometry is refreshed.
    /// The view model is reused, so Shift state and the active layer survive.
    private func rebuildRootView() {
        guard let model, let hosting = hostingController else { return }
        hosting.rootView = KeyboardRootView(
            model: model,
            isLandscape: isLandscape,
            showsBackground: true,
            bottomInset: 0,
            showsNotice: true
        )
    }

    // MARK: - Configuration

    private func reloadConfigurationFromStore(announceResult: Bool) {
        let store = self.store

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = store.load()
            DispatchQueue.main.async {
                guard let self, let model = self.model else { return }

                // Only reload when something actually changed: recreating the
                // layout on every appearance would cost frames for nothing.
                let isSameConfiguration = self.lastLoadedConfiguration == result.configuration
                self.lastLoadedConfiguration = result.configuration

                if !isSameConfiguration {
                    model.reload(configuration: result.configuration)
                }

                if announceResult, let issue = result.issues.first {
                    model.showNotice(issue.title)
                }
                self.reportStatus(result: result)
            }
        }
    }

    // MARK: - Effects

    private func handle(effect: KeyboardEffect) {
        switch effect {
        case .nextInputMode:
            advanceToNextInputMode()

        case .haptic:
            if let strength = model?.settings.haptics {
                feedback.playHaptic(strength)
            }

        case .keyClick:
            feedback.playKeyClick()

        case .layoutChanged:
            reportStatusIfPossible()

        case .configurationReloaded:
            break

        case .notice:
            // Surfaced by the view model's notice strip.
            break
        }
    }

    // MARK: - Status heartbeat

    private func reportStatus(result: ConfigurationLoadResult) {
        guard let model else { return }
        let status = KeyboardRuntimeStatus(
            appGroupReachable: store.sharedContainerAvailable,
            configurationSource: result.source,
            configurationGeneration: result.configuration.generation,
            layoutCount: result.configuration.layouts.count,
            keyCount: model.layout.keyCount,
            activeLayoutName: model.layout.name,
            needsInputModeSwitchKey: inputAdapter?.needsInputModeSwitchKey ?? false,
            hasFullAccess: inputAdapter?.hasFullAccess ?? false,
            extensionVersion: KeyraBuildInfo.versionString,
            note: note(for: result)
        )
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            store.saveStatus(status)
        }
        hasReportedStatus = true
    }

    private func reportStatusIfPossible() {
        guard let configuration = lastLoadedConfiguration else { return }
        guard !hasReportedStatus else { return }
        reportStatus(result: ConfigurationLoadResult(
            configuration: configuration,
            source: store.sharedContainerAvailable ? .sharedContainer : .localFallback,
            issues: [],
            didRecoverFromCorruption: false,
            needsSave: false,
            locationDescription: store.locationDescription,
            sharedContainerAvailable: store.sharedContainerAvailable,
            sharedContainerDiagnosis: nil
        ))
    }

    private func note(for result: ConfigurationLoadResult) -> String? {
        if !store.sharedContainerAvailable {
            return "App Group container unavailable"
        }
        if result.didRecoverFromCorruption {
            return "Recovered from unreadable configuration"
        }
        if inputAdapter?.hasFullAccess == false {
            return "Full Access is off"
        }
        return nil
    }

    // MARK: - Screen metrics

    /// Screen height used only to cap how tall the keyboard may ask to be.
    private var availableScreenHeight: Double {
        if let windowHeight = view.window?.bounds.height, windowHeight > 200 {
            return Double(windowHeight)
        }
        // `UIScreen.main` is the only API that reports the device size before the
        // window exists. It is marked deprecated in newer SDKs, so it is isolated
        // here behind a safe fallback.
        let screenHeight = Double(UIScreen.main.bounds.height)
        return screenHeight > 200 ? screenHeight : 844
    }

    private var screenWidthEstimate: Double {
        let screenWidth = Double(UIScreen.main.bounds.width)
        return screenWidth > 200 ? screenWidth : 390
    }
}

// MARK: - Key click sound support

extension KeyboardViewController: UIInputViewAudioFeedback {
    /// Enables `UIDevice.playInputClick()` while the keyboard is visible, which
    /// is the documented way for a custom keyboard to play the system click.
    var enableInputClicksWhenVisible: Bool { true }
}

// MARK: - Build information

/// Reads this bundle's version without touching `UIApplication`, which is not
/// available to app extensions.
enum KeyraBuildInfo {

    static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

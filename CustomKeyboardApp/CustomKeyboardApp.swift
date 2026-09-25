import SwiftUI

/// Keyra — the host application.
///
/// The app is the *builder*: it owns the keyboard configuration, provides the
/// layout / row / key / theme editors, and persists everything into the shared
/// container that the keyboard extension reads.
@main
struct CustomKeyboardApp: App {

    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Color(keyra: store.activeTheme.pressedKeyColor))
                .task {
                    store.refreshKeyboardStatus()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                store.refreshKeyboardStatus()
            case .background, .inactive:
                // Never risk losing an edit: flush any pending debounced save.
                store.saveNow()
            @unknown default:
                break
            }
        }
    }
}

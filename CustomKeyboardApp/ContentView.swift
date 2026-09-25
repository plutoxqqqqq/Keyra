import SwiftUI

/// Root of the host app: My Keyboards, Themes, Presets and Setup.
struct ContentView: View {

    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            KeyboardListView()
                .tabItem { Label("Keyboards", systemImage: "keyboard") }
                .tag(0)

            NavigationStack {
                ThemeEditorView()
            }
            .tabItem { Label("Themes", systemImage: "paintpalette") }
            .tag(1)

            NavigationStack {
                PresetsView()
            }
            .tabItem { Label("Presets", systemImage: "square.grid.2x2") }
            .tag(2)

            NavigationStack {
                SetupView()
            }
            .tabItem { Label("Setup", systemImage: "gearshape") }
            .tag(3)
        }
        .overlay(alignment: .bottom) {
            if let banner = store.banner {
                BannerView(banner: banner) {
                    store.banner = nil
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.banner?.id)
    }
}

/// Floating banner used for import results, save problems and confirmations.
struct BannerView: View {

    let banner: AppBanner
    var onDismiss: () -> Void

    private var color: Color {
        switch banner.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .accentColor
        }
    }

    private var symbol: String {
        switch banner.severity {
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(banner.detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
    }
}

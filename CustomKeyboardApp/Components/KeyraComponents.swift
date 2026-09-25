import SwiftUI
import UIKit

// MARK: - Cards

/// A titled, rounded container used across the app.
struct KeyraCard<Content: View>: View {

    var title: String?
    var systemImage: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundColor(.secondary)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            content
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A labelled value, used by the diagnostics screens.
struct KeyraValueRow: View {

    let label: String
    let value: String
    var monospaced: Bool = false
    var tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .foregroundColor(tint ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

/// A small coloured pill (status, counts, severity).
struct KeyraPill: View {

    let text: String
    var severity: KeyboardIssueSeverity?
    var systemImage: String?

    private var color: Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .accentColor
        case .none: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

/// The list of validation problems for a keyboard.
struct KeyraIssueList: View {

    let issues: [KeyboardIssue]

    var body: some View {
        if issues.isEmpty {
            KeyraCard(title: "Checks", systemImage: "checkmark.seal") {
                Text("No problems found. This keyboard is ready to use.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        } else {
            KeyraCard(title: "Checks", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: issue.severity.symbolName)
                                    .foregroundColor(color(for: issue.severity))
                                    .font(.footnote)
                                Text(issue.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text(issue.detail)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func color(for severity: KeyboardIssueSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .accentColor
        }
    }
}

// MARK: - Colour editing

/// Hex field plus a system colour picker, both writing to the same model value.
struct KeyraColorField: View {

    let title: String
    @Binding var color: KeyboardColor
    var allowAlpha: Bool = true

    @State private var hexText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColorPicker(title, selection: pickerBinding, supportsOpacity: allowAlpha)

            HStack(spacing: 8) {
                TextField("#RRGGBB", text: $hexText)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .onSubmit(applyHex)
                    .frame(maxWidth: 140)

                Button("Apply", action: applyHex)
                    .font(.footnote)
                    .buttonStyle(.bordered)

                Spacer()

                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
            }
        }
        .onAppear { hexText = color.hexString }
        .onChange(of: color) { newValue in
            if KeyboardColor(hex: hexText)?.hexString != newValue.hexString {
                hexText = newValue.hexString
            }
        }
    }

    private var pickerBinding: Binding<Color> {
        Binding(
            get: { color.swiftUIColor },
            set: { newValue in
                color = KeyboardColor(uiColor: UIColor(newValue))
                hexText = color.hexString
            }
        )
    }

    private func applyHex() {
        if let parsed = KeyboardColor(hex: hexText) {
            color = parsed
        }
        hexText = color.hexString
    }
}

// MARK: - Key chips

/// Compact representation of a key used in row summaries.
struct KeyraKeyChip: View {

    let key: KeyboardKey
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(key.label.isEmpty ? "?" : key.label)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(key.action.type.displayName)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: 42)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .accessibilityLabel(Text(key.spokenLabel))
    }
}

// MARK: - Copyable text

struct KeyraCopyButton: View {

    let text: String
    var label: String = "Copy"
    @State private var didCopy = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                didCopy = false
            }
        } label: {
            Label(didCopy ? "Copied" : label, systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .font(.footnote)
        }
        .buttonStyle(.bordered)
    }
}

/// Ordered instructions, each copyable — used by the setup screen.
struct KeyraStepList: View {

    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    Text(steps[index])
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Measuring helper

/// Reports the width it is laid out with (used to size live previews exactly).
struct KeyraWidthReporter: View {

    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { newValue in width = newValue }
        }
    }
}

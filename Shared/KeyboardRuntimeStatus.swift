import Foundation

/// A small heartbeat the keyboard extension writes so the host app can show the
/// truth about what is actually happening on device.
///
/// PRIVACY: this record deliberately contains **no user-typed text, no
/// keystrokes, no timing of individual presses and no host-app information**.
/// It only describes the keyboard's own configuration state, which is exactly
/// what the setup screen needs to explain why (for example) the App Group
/// container is unreachable.
struct KeyboardRuntimeStatus: Codable, Equatable {

    var lastLoadedAt: Date
    /// Whether the *extension* could reach the App Group container.
    var appGroupReachable: Bool
    var configurationSource: ConfigurationSource
    var configurationGeneration: Int
    var layoutCount: Int
    var keyCount: Int
    var activeLayoutName: String?
    /// `needsInputModeSwitchKey` for the text field being edited.
    var needsInputModeSwitchKey: Bool
    /// `hasFullAccess` for the keyboard extension.
    var hasFullAccess: Bool
    var extensionVersion: String?
    /// Short machine-ish note (never user text), e.g. "App Group unavailable".
    var note: String?

    init(
        lastLoadedAt: Date = Date(),
        appGroupReachable: Bool,
        configurationSource: ConfigurationSource,
        configurationGeneration: Int,
        layoutCount: Int,
        keyCount: Int,
        activeLayoutName: String?,
        needsInputModeSwitchKey: Bool,
        hasFullAccess: Bool,
        extensionVersion: String?,
        note: String? = nil
    ) {
        self.lastLoadedAt = lastLoadedAt
        self.appGroupReachable = appGroupReachable
        self.configurationSource = configurationSource
        self.configurationGeneration = configurationGeneration
        self.layoutCount = layoutCount
        self.keyCount = keyCount
        self.activeLayoutName = activeLayoutName
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
        self.hasFullAccess = hasFullAccess
        self.extensionVersion = extensionVersion
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case lastLoadedAt, appGroupReachable, configurationSource, configurationGeneration
        case layoutCount, keyCount, activeLayoutName, needsInputModeSwitchKey
        case hasFullAccess, extensionVersion, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastLoadedAt = container.keyraOptional(Date.self, forKey: .lastLoadedAt) ?? Date(timeIntervalSince1970: 0)
        appGroupReachable = container.keyraBool(.appGroupReachable, false)
        configurationSource = container.keyraValue(.configurationSource, ConfigurationSource.builtInDefaults)
        configurationGeneration = container.keyraInt(.configurationGeneration, 0)
        layoutCount = container.keyraInt(.layoutCount, 0)
        keyCount = container.keyraInt(.keyCount, 0)
        activeLayoutName = container.keyraNonEmptyString(.activeLayoutName)
        needsInputModeSwitchKey = container.keyraBool(.needsInputModeSwitchKey, false)
        hasFullAccess = container.keyraBool(.hasFullAccess, false)
        extensionVersion = container.keyraNonEmptyString(.extensionVersion)
        note = container.keyraNonEmptyString(.note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastLoadedAt, forKey: .lastLoadedAt)
        try container.encode(appGroupReachable, forKey: .appGroupReachable)
        try container.encode(configurationSource, forKey: .configurationSource)
        try container.encode(configurationGeneration, forKey: .configurationGeneration)
        try container.encode(layoutCount, forKey: .layoutCount)
        try container.encode(keyCount, forKey: .keyCount)
        if let activeLayoutName { try container.encode(activeLayoutName, forKey: .activeLayoutName) }
        try container.encode(needsInputModeSwitchKey, forKey: .needsInputModeSwitchKey)
        try container.encode(hasFullAccess, forKey: .hasFullAccess)
        if let extensionVersion { try container.encode(extensionVersion, forKey: .extensionVersion) }
        if let note { try container.encode(note, forKey: .note) }
    }

    /// One-line summary for the setup screen.
    var summary: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if lastLoadedAt.timeIntervalSince1970 <= 0 {
            return "The keyboard has not reported in yet."
        }
        let layout = activeLayoutName ?? "a layout"
        return "Last opened \(formatter.string(from: lastLoadedAt)) using “\(layout)” (\(keyCount) keys)."
    }
}

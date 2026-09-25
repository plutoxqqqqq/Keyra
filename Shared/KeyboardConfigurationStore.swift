import Foundation

// MARK: - Where a value came from

enum ConfigurationSource: String, Codable, Equatable {
    /// Read from the App Group container shared with the keyboard extension.
    case sharedContainer
    /// Read from this process's own container (no App Group available).
    case localFallback
    /// Nothing readable on disk; built-in presets were used.
    case builtInDefaults

    var displayName: String {
        switch self {
        case .sharedContainer: return "Shared with the keyboard"
        case .localFallback: return "App-only storage"
        case .builtInDefaults: return "Built-in defaults"
        }
    }
}

/// Result of a load attempt. Always contains a usable configuration.
struct ConfigurationLoadResult {
    var configuration: KeyboardConfiguration
    var source: ConfigurationSource
    var issues: [KeyboardIssue]
    /// The stored data could not be decoded at all.
    var didRecoverFromCorruption: Bool
    /// Sanitising changed something; the caller should save the repaired copy.
    var needsSave: Bool
    /// Human readable description of where the data lives.
    var locationDescription: String
    var sharedContainerAvailable: Bool
    /// Exactly why the shared container was not used, when it was not.
    var sharedContainerDiagnosis: String?
}

enum ConfigurationStoreError: LocalizedError {
    case noWritableLocation
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWritableLocation:
            return "No writable storage location is available."
        case .writeFailed(let reason):
            return "Could not save the keyboard configuration: \(reason)"
        }
    }
}

// MARK: - Storage abstraction

/// A place that can hold named files — either the App Group container (shared
/// with the keyboard extension) or this process's own writable container.
protocol KeyboardSharedStorage: AnyObject {
    /// Human readable location, shown in the setup / diagnostics screen.
    var locationDescription: String { get }
    /// `true` only when this really is the App Group container.
    var isShared: Bool { get }
    var directoryURL: URL? { get }

    func readData(fileName: String) -> Data?
    func writeData(_ data: Data, fileName: String) throws
}

/// File backed storage (atomic writes, lazily created directory).
final class FileKeyboardStorage: KeyboardSharedStorage {

    let directoryURL: URL?
    let isShared: Bool
    let locationDescription: String
    private let fileManager: FileManager

    init(directoryURL: URL?, isShared: Bool, locationDescription: String, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.isShared = isShared
        self.locationDescription = locationDescription
        self.fileManager = fileManager
    }

    func readData(fileName: String) -> Data? {
        guard let url = fileURL(fileName) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        // A keyboard extension must launch instantly. A configuration larger than
        // this is not a real keyboard, so it is treated as unreadable rather than
        // parsed on the keyboard's critical path.
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber, size.intValue > KeyboardConfigurationStore.maximumReadableBytes {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func writeData(_ data: Data, fileName: String) throws {
        guard let directory = directoryURL, let url = fileURL(fileName) else {
            throw ConfigurationStoreError.noWritableLocation
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ConfigurationStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func fileURL(_ fileName: String) -> URL? {
        guard let directory = directoryURL else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}

/// Storage that lives only in memory. Used by unit tests so they never touch the
/// real container, and never leave state behind between runs.
final class InMemoryKeyboardStorage: KeyboardSharedStorage {

    private var files: [String: Data]
    let isShared: Bool
    let locationDescription: String
    var directoryURL: URL? { nil }

    init(files: [String: Data] = [:], isShared: Bool = true, locationDescription: String = "In-memory storage") {
        self.files = files
        self.isShared = isShared
        self.locationDescription = locationDescription
    }

    func readData(fileName: String) -> Data? {
        files[fileName]
    }

    func writeData(_ data: Data, fileName: String) throws {
        files[fileName] = data
    }

    func contains(fileName: String) -> Bool {
        files[fileName] != nil
    }
}

// MARK: - Store

/// Reads and writes the keyboard configuration and the runtime status file.
///
/// Behaviour that matters:
/// * The App Group container is used when it is actually reachable (which
///   requires the entitlement to be signed *and*, for a keyboard extension,
///   "Allow Full Access" to be granted).
/// * When it is not reachable the store falls back to this process's own
///   container and reports that honestly instead of pretending to be shared.
/// * Loading can never fail: corrupt data is quarantined and replaced by the
///   built-in presets, and the keyboard keeps working.
final class KeyboardConfigurationStore {

    /// Refuse to parse anything larger than this on the keyboard's launch path.
    static let maximumReadableBytes = 4 * 1024 * 1024

    static let configurationFileName = "keyboard-config.json"
    static let statusFileName = "keyboard-status.json"
    static let corruptBackupFileName = "keyboard-config.corrupt.json"

    /// Info.plist key that carries the App Group identifier, so the runtime value
    /// is always the exact string that was signed.
    static let containerIDInfoPlistKey = "KeyraSharedContainerID"
    /// Used only if the Info.plist value is missing (e.g. exotic build pipelines).
    static let fallbackContainerID = "group.com.keyra.CustomKeyboard"

    let storage: KeyboardSharedStorage
    let configurationFileName: String
    let statusFileName: String

    init(
        storage: KeyboardSharedStorage,
        configurationFileName: String = KeyboardConfigurationStore.configurationFileName,
        statusFileName: String = KeyboardConfigurationStore.statusFileName
    ) {
        self.storage = storage
        self.configurationFileName = configurationFileName
        self.statusFileName = statusFileName
    }

    var sharedContainerAvailable: Bool { storage.isShared }

    var locationDescription: String { storage.locationDescription }

    // MARK: Container identity

    /// The App Group identifier this build was signed with.
    static func containerIdentifier(bundle: Bundle = .main) -> String {
        if let value = bundle.object(forInfoDictionaryKey: containerIDInfoPlistKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return fallbackContainerID
    }

    /// Resolves the storage this process should use, and explains itself.
    static func resolveStorage(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> (storage: KeyboardSharedStorage, diagnosis: String?) {

        let identifier = containerIdentifier(bundle: bundle)

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return (
                FileKeyboardStorage(
                    directoryURL: containerURL,
                    isShared: true,
                    locationDescription: "App Group “\(identifier)”",
                    fileManager: fileManager
                ),
                nil
            )
        }

        // Fall back to a per-process directory. This still works (the host app can
        // edit and persist layouts) but the keyboard extension cannot see it.
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Keyra", isDirectory: true)

        let diagnosis = """
        The App Group container “\(identifier)” is not available to this process. \
        It requires (1) the App Group entitlement to be present in the signed app, and \
        (2) for the keyboard extension, “Allow Full Access” to be enabled in Settings. \
        The app is using its own container instead, so the keyboard will fall back to its \
        built-in presets until the entitlement is signed.
        """

        return (
            FileKeyboardStorage(
                directoryURL: directory,
                isShared: false,
                locationDescription: "App container (~/…/Application Support/Keyra)",
                fileManager: fileManager
            ),
            diagnosis
        )
    }

    static func defaultStore(bundle: Bundle = .main, fileManager: FileManager = .default) -> KeyboardConfigurationStore {
        let resolved = resolveStorage(bundle: bundle, fileManager: fileManager)
        return KeyboardConfigurationStore(storage: resolved.storage)
    }

    /// Diagnostic-only variant that reports why the container was not shared.
    static func defaultStoreWithDiagnosis(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> (store: KeyboardConfigurationStore, diagnosis: String?) {
        let resolved = resolveStorage(bundle: bundle, fileManager: fileManager)
        return (KeyboardConfigurationStore(storage: resolved.storage), resolved.diagnosis)
    }

    static func inMemory(seed: KeyboardConfiguration? = nil) -> KeyboardConfigurationStore {
        var files: [String: Data] = [:]
        if let seed, let data = try? KeyboardJSON.encoder().encode(seed) {
            files[configurationFileName] = data
        }
        return KeyboardConfigurationStore(storage: InMemoryKeyboardStorage(files: files))
    }

    // MARK: Load

    func load() -> ConfigurationLoadResult {
        let shared = storage.isShared
        let diagnosis = shared ? nil : KeyboardConfigurationStore.resolveStorage().diagnosis

        guard let data = storage.readData(fileName: configurationFileName), !data.isEmpty else {
            return ConfigurationLoadResult(
                configuration: KeyboardDefaults.fallbackConfiguration(),
                source: .builtInDefaults,
                issues: [KeyboardIssue(
                    severity: .info,
                    title: "Starting from the built-in keyboards",
                    detail: "Nothing has been saved yet, so Keyra loaded its presets: QWERTY, Symbols, Math, Emoji and Coding."
                )],
                didRecoverFromCorruption: false,
                needsSave: false,
                locationDescription: storage.locationDescription,
                sharedContainerAvailable: shared,
                sharedContainerDiagnosis: diagnosis
            )
        }

        // 1. Try a full configuration document.
        if let decoded = KeyboardJSON.decode(KeyboardConfiguration.self, from: data) {
            let repaired = KeyboardValidator.sanitize(decoded)
            return ConfigurationLoadResult(
                configuration: repaired.configuration,
                source: shared ? .sharedContainer : .localFallback,
                issues: repaired.issues,
                didRecoverFromCorruption: false,
                needsSave: !repaired.issues.isEmpty,
                locationDescription: storage.locationDescription,
                sharedContainerAvailable: shared,
                sharedContainerDiagnosis: diagnosis
            )
        }

        // 2. Maybe it is a single exported layout (or an export envelope).
        if let layout = JSONImportExport.decodeLooseLayout(from: data) {
            var configuration = KeyboardDefaults.fallbackConfiguration()
            var scratchIssues: [KeyboardIssue] = []
            let sanitized = KeyboardValidator.sanitizeLayout(layout, issues: &scratchIssues)
            configuration.layouts.append(sanitized)
            configuration.activeLayoutID = sanitized.id
            configuration.generation = max(1, configuration.generation)
            let repaired = KeyboardValidator.sanitize(configuration)
            return ConfigurationLoadResult(
                configuration: repaired.configuration,
                source: shared ? .sharedContainer : .localFallback,
                issues: repaired.issues + scratchIssues + [KeyboardIssue(
                    severity: .warning,
                    title: "Recovered a single keyboard",
                    detail: "The saved file contained one keyboard rather than a full configuration. It was added as “\(sanitized.name)”."
                )],
                didRecoverFromCorruption: true,
                needsSave: true,
                locationDescription: storage.locationDescription,
                sharedContainerAvailable: shared,
                sharedContainerDiagnosis: diagnosis
            )
        }

        // 3. Nothing worked: quarantine the payload and use the presets.
        quarantine(data)

        return ConfigurationLoadResult(
            configuration: KeyboardDefaults.fallbackConfiguration(),
            source: .builtInDefaults,
            issues: [KeyboardIssue(
                severity: .error,
                title: "Saved settings could not be read",
                detail: "The stored configuration was not valid JSON for Keyra. The built-in keyboards were loaded instead, and a copy of the unreadable file was kept as \(KeyboardConfigurationStore.corruptBackupFileName)."
            )],
            didRecoverFromCorruption: true,
            needsSave: false,
            locationDescription: storage.locationDescription,
            sharedContainerAvailable: shared,
            sharedContainerDiagnosis: diagnosis
        )
    }

    /// Keeps one copy of unreadable data so a user can inspect or recover it.
    private func quarantine(_ data: Data) {
        try? storage.writeData(data, fileName: KeyboardConfigurationStore.corruptBackupFileName)
    }

    // MARK: Save

    @discardableResult
    func save(_ configuration: KeyboardConfiguration) throws -> KeyboardConfiguration {
        var repaired = KeyboardValidator.sanitize(configuration).configuration
        repaired.schemaVersion = KeyboardConfiguration.currentSchemaVersion
        repaired.generation = max(configuration.generation + 1, repaired.generation + 1)
        repaired.updatedAt = Date()

        // Encoded on the calling thread but only ever a few kilobytes; the host
        // app debounces saves and the extension never saves the configuration.
        let data = try KeyboardJSON.encoder().encode(repaired)
        try storage.writeData(data, fileName: configurationFileName)
        return repaired
    }

    // MARK: Status (keyboard → app heartbeat)

    func loadStatus() -> KeyboardRuntimeStatus? {
        guard let data = storage.readData(fileName: statusFileName) else { return nil }
        return KeyboardJSON.decode(KeyboardRuntimeStatus.self, from: data)
    }

    func saveStatus(_ status: KeyboardRuntimeStatus) {
        guard let data = try? KeyboardJSON.encoder().encode(status) else { return }
        try? storage.writeData(data, fileName: statusFileName)
    }
}

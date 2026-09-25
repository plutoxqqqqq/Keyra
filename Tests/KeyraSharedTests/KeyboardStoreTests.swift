import XCTest
@testable import KeyraShared

final class KeyboardStoreTests: XCTestCase {

    private func makeStore(files: [String: Data] = [:], shared: Bool = true) -> (KeyboardConfigurationStore, InMemoryKeyboardStorage) {
        let storage = InMemoryKeyboardStorage(files: files, isShared: shared)
        return (KeyboardConfigurationStore(storage: storage), storage)
    }

    // MARK: - Saving and loading

    func testSaveThenLoadRoundTrips() throws {
        let (store, _) = makeStore()
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts[0].name = "My Keyboard"
        configuration.layouts[0].rows[0].keys[0].label = "Z"

        let saved = try store.save(configuration)
        XCTAssertEqual(saved.schemaVersion, KeyboardConfiguration.currentSchemaVersion)
        XCTAssertEqual(saved.generation, configuration.generation + 1)
        XCTAssertNotNil(saved.updatedAt)

        let result = store.load()
        XCTAssertEqual(result.source, .sharedContainer)
        XCTAssertFalse(result.didRecoverFromCorruption)
        XCTAssertEqual(result.configuration.layouts.first?.name, "My Keyboard")
        XCTAssertEqual(result.configuration.layouts.first?.rows.first?.keys.first?.label, "Z")
        XCTAssertEqual(result.configuration.generation, saved.generation)
        XCTAssertTrue(result.sharedContainerAvailable)
    }

    func testSaveIncrementsGenerationEveryTime() throws {
        let (store, _) = makeStore()
        var configuration = KeyboardDefaults.configuration()
        let first = try store.save(configuration)
        configuration = first
        let second = try store.save(configuration)
        XCTAssertEqual(second.generation, first.generation + 1)
    }

    func testSaveSanitisesBeforeWriting() throws {
        let (store, _) = makeStore()
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts[0].rows[0].keys[0].width = -50
        configuration.layouts[0].rows[0].keys[1].width = .nan

        let saved = try store.save(configuration)
        let widths = saved.layouts[0].rows[0].keys.map { $0.width }
        for width in widths {
            XCTAssertTrue(width.isFinite)
            XCTAssertGreaterThanOrEqual(width, KeyboardLimits.minKeyWidthWeight)
        }
    }

    func testLoadingAnEmptyContainerUsesTheBuiltInKeyboards() {
        let (store, _) = makeStore()
        let result = store.load()
        XCTAssertEqual(result.source, .builtInDefaults)
        XCTAssertFalse(result.configuration.layouts.isEmpty)
        XCTAssertTrue(result.configuration.layouts.first?.name == KeyboardDefaults.qwertyName)
        XCTAssertFalse(result.issues.isEmpty, "the user should be told where the content came from")
    }

    func testLoadFallsBackOnCorruptDataAndQuarantinesIt() {
        let garbage = Data("this is not json at all".utf8)
        let (store, storage) = makeStore(files: [KeyboardConfigurationStore.configurationFileName: garbage])

        let result = store.load()
        XCTAssertTrue(result.didRecoverFromCorruption)
        XCTAssertFalse(result.configuration.layouts.isEmpty, "the keyboard must still work")
        XCTAssertTrue(result.issues.contains { $0.severity == .error })
        XCTAssertTrue(storage.contains(fileName: KeyboardConfigurationStore.corruptBackupFileName),
                      "the unreadable payload should be preserved for recovery")
        XCTAssertEqual(storage.readData(fileName: KeyboardConfigurationStore.configurationFileName), garbage,
                       "the original file must not be destroyed")
    }

    func testLoadRecoversASingleExportedLayout() throws {
        let layout = KeyboardDefaults.math()
        let envelope = KeyboardExportEnvelope(kind: "layout", layout: layout)
        let data = try KeyboardJSON.encoder().encode(envelope)

        let (store, _) = makeStore(files: [KeyboardConfigurationStore.configurationFileName: data])
        let result = store.load()
        XCTAssertTrue(result.didRecoverFromCorruption == false)
        XCTAssertTrue(result.configuration.layouts.contains { $0.name == layout.name },
                      "an exported layout stored as the config should be recovered")
        XCTAssertTrue(result.needsSave)
    }

    func testNeedsSaveIsReportedWhenRepairsHappened() throws {
        var configuration = KeyboardDefaults.configuration()
        configuration.themes = []
        let data = try KeyboardJSON.encoder().encode(configuration)

        let (store, _) = makeStore(files: [KeyboardConfigurationStore.configurationFileName: data])
        let result = store.load()
        XCTAssertFalse(result.configuration.themes.isEmpty, "missing themes must be restored")
        XCTAssertTrue(result.needsSave)
    }

    func testOversizedConfigurationIsRefusedInsteadOfParsed() throws {
        // The size guard lives in the real file storage, so exercise it there.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyra-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileStorage = FileKeyboardStorage(directoryURL: directory, isShared: true, locationDescription: "test")
        let big = Data(repeating: 0x41, count: KeyboardConfigurationStore.maximumReadableBytes + 1024)
        try fileStorage.writeData(big, fileName: KeyboardConfigurationStore.configurationFileName)

        let store = KeyboardConfigurationStore(storage: fileStorage)
        let result = store.load()
        XCTAssertEqual(result.source, .builtInDefaults,
                       "an absurdly large file must not be parsed on the keyboard's launch path")
        XCTAssertFalse(result.configuration.layouts.isEmpty)

        // A normal sized file is read back normally.
        let small = Data("{\"layouts\":[]}".utf8)
        try fileStorage.writeData(small, fileName: KeyboardConfigurationStore.configurationFileName)
        XCTAssertEqual(store.load().configuration.layouts.isEmpty, false,
                       "empty layouts are repaired into a usable keyboard")
    }

    // MARK: - File storage

    func testFileStorageWritesAtomicallyAndReadsBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyra-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = FileKeyboardStorage(directoryURL: directory, isShared: true, locationDescription: "temp")
        XCTAssertNil(storage.readData(fileName: "missing.json"))

        try storage.writeData(Data("hello".utf8), fileName: "a.json")
        XCTAssertEqual(storage.readData(fileName: "a.json"), Data("hello".utf8))

        // A directory that does not exist yet is created on demand.
        let nested = FileKeyboardStorage(
            directoryURL: directory.appendingPathComponent("nested/deeper", isDirectory: true),
            isShared: true,
            locationDescription: "nested"
        )
        try nested.writeData(Data("nested".utf8), fileName: "b.json")
        XCTAssertEqual(nested.readData(fileName: "b.json"), Data("nested".utf8))
    }

    // MARK: - Shared container honesty

    func testContainerIdentifierFallsBackWhenTheInfoPlistKeyIsMissing() {
        // The test bundle has no KeyraSharedContainerID key.
        let identifier = KeyboardConfigurationStore.containerIdentifier(bundle: Bundle(for: type(of: self)))
        XCTAssertEqual(identifier, KeyboardConfigurationStore.fallbackContainerID)
        XCTAssertTrue(identifier.hasPrefix("group."))
    }

    func testResolveStorageReportsWhenTheAppGroupIsUnavailable() {
        // In this test process the App Group is not entitled, so the store must
        // say so rather than pretending the keyboard can see the data.
        let resolved = KeyboardConfigurationStore.resolveStorage(bundle: Bundle(for: type(of: self)))
        XCTAssertFalse(resolved.storage.isShared,
                       "a process without the entitlement must not report a shared container")
        XCTAssertNotNil(resolved.diagnosis, "the reason should be explained to the user")
        XCTAssertFalse(resolved.storage.locationDescription.isEmpty)
    }

    // MARK: - Status heartbeat

    func testStatusRoundTrip() {
        let (store, _) = makeStore()
        XCTAssertNil(store.loadStatus())

        let status = KeyboardRuntimeStatus(
            appGroupReachable: true,
            configurationSource: .sharedContainer,
            configurationGeneration: 7,
            layoutCount: 5,
            keyCount: 42,
            activeLayoutName: "QWERTY",
            needsInputModeSwitchKey: true,
            hasFullAccess: true,
            extensionVersion: "1.0 (1)",
            note: nil
        )
        store.saveStatus(status)

        let loaded = store.loadStatus()
        XCTAssertEqual(loaded?.configurationGeneration, 7)
        XCTAssertEqual(loaded?.keyCount, 42)
        XCTAssertEqual(loaded?.activeLayoutName, "QWERTY")
        XCTAssertTrue(loaded?.summary.contains("QWERTY") ?? false)
    }

    func testStatusContainingNoUserText() throws {
        let status = KeyboardRuntimeStatus(
            appGroupReachable: false,
            configurationSource: .builtInDefaults,
            configurationGeneration: 1,
            layoutCount: 1,
            keyCount: 10,
            activeLayoutName: "Starter",
            needsInputModeSwitchKey: false,
            hasFullAccess: false,
            extensionVersion: nil,
            note: "App Group unavailable"
        )
        let data = try KeyboardJSON.encoder().encode(status)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.lowercased().contains("text"))
        XCTAssertFalse(text.lowercased().contains("typed"))
        XCTAssertTrue(text.contains("App Group unavailable"))
    }

    func testInMemoryStoreFactorySeedsAConfiguration() {
        let configuration = KeyboardDefaults.configuration()
        let store = KeyboardConfigurationStore.inMemory(seed: configuration)
        let result = store.load()
        XCTAssertEqual(result.configuration.layouts.count, configuration.layouts.count)
        XCTAssertEqual(result.source, .sharedContainer)
    }
}

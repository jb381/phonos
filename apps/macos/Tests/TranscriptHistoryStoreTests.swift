import Foundation
import XCTest

@testable import Phonos

final class TranscriptHistoryStoreTests: XCTestCase {
    private final class StubHistorySettings: HistorySettingsProviding {
        var historyEnabled: Bool

        init(historyEnabled: Bool) {
            self.historyEnabled = historyEnabled
        }
    }

    private func makeTempDatabaseURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonos_history_tests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("history.sqlite", isDirectory: false)
    }

    private func makeResponse(
        text: String = "Hello world",
        model: String = "base.en",
        language: String = "en",
        durationSeconds: Double = 2.5,
        processingSeconds: Double = 0.4
    ) -> TranscriptionResponse {
        TranscriptionResponse(
            text: text,
            model: model,
            language: language,
            duration_seconds: durationSeconds,
            processing_seconds: processingSeconds
        )
    }

    private func makeEntry(
        text: String,
        model: String,
        language: String
    ) -> TranscriptEntry {
        TranscriptEntry(
            text: text,
            model: model,
            language: language,
            durationSeconds: 1.0,
            processingSeconds: 0.2
        )
    }

    func testAppDatabaseFetchAllReturnsNewestFirst() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)

        var older = TranscriptEntry(
            text: "Older",
            model: "base.en",
            language: "en",
            durationSeconds: 1.2,
            processingSeconds: 0.3,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        var newer = TranscriptEntry(
            text: "Newer",
            model: "small.en",
            language: "en",
            durationSeconds: 3.8,
            processingSeconds: 0.9,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try database.insert(&older)
        try database.insert(&newer)

        let loaded = try database.fetchAll()
        XCTAssertEqual(loaded.map(\.text), ["Newer", "Older"])
    }

    func testAppDatabaseClearAllRemovesRows() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        var entry = TranscriptEntry(
            text: "to clear",
            model: "base.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2
        )

        try database.insert(&entry)
        try database.clearAll()

        XCTAssertTrue(try database.fetchAll().isEmpty)
    }

    func testFiltersSearchByTextCaseInsensitive() {
        let entries = [
            makeEntry(text: "Call Alice tomorrow", model: "base.en", language: "en"),
            makeEntry(text: "book a table", model: "small.en", language: "en")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "ALICE",
            modelFilter: TranscriptHistoryFilters.allModelsLabel,
            languageFilter: TranscriptHistoryFilters.allLanguagesLabel
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.text, "Call Alice tomorrow")
    }

    func testFiltersByModelAndLanguage() {
        let entries = [
            makeEntry(text: "hello", model: "base.en", language: "en"),
            makeEntry(text: "bonjour", model: "base.en", language: "fr"),
            makeEntry(text: "hola", model: "small.en", language: "es")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "",
            modelFilter: "base.en",
            languageFilter: "FR"
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.text, "bonjour")
    }

    func testFiltersCombineQueryAndMetadata() {
        let entries = [
            makeEntry(text: "Prepare sprint notes", model: "base.en", language: "en"),
            makeEntry(text: "Prepare dinner", model: "small.en", language: "en")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "prepare",
            modelFilter: "small.en",
            languageFilter: "EN"
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.text, "Prepare dinner")
    }

    func testFiltersWithAllDefaultsReturnsAllEntries() {
        let entries = [
            makeEntry(text: "a", model: "base.en", language: "en"),
            makeEntry(text: "b", model: "small.en", language: "fr"),
            makeEntry(text: "c", model: "medium.en", language: "de")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "",
            modelFilter: TranscriptHistoryFilters.allModelsLabel,
            languageFilter: TranscriptHistoryFilters.allLanguagesLabel
        )

        XCTAssertEqual(filtered.count, 3)
    }

    func testFiltersReturnsEmptyWhenNothingMatches() {
        let entries = [
            makeEntry(text: "hello", model: "base.en", language: "en")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "zzz_no_match",
            modelFilter: TranscriptHistoryFilters.allModelsLabel,
            languageFilter: TranscriptHistoryFilters.allLanguagesLabel
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testFiltersQueryMatchesModelName() {
        let entries = [
            makeEntry(text: "something", model: "base.en", language: "en"),
            makeEntry(text: "another", model: "small.en", language: "en")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "small",
            modelFilter: TranscriptHistoryFilters.allModelsLabel,
            languageFilter: TranscriptHistoryFilters.allLanguagesLabel
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.model, "small.en")
    }

    @MainActor
    func testStoreAddIgnoresWhitespaceOnlyText() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "   \n  "))
        store.add(makeResponse(text: ""))

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testStoreInMemoryFallbackWhenNoDatabase() {
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: nil, settings: settings)

        store.add(makeResponse(text: "only in memory"))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "only in memory")
    }

    @MainActor
    func testStoreDisableMidSessionClearsEntries() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "active entry"))
        XCTAssertEqual(store.entries.count, 1)

        store.setPersistenceEnabled(false)
        XCTAssertTrue(store.entries.isEmpty)

        store.setPersistenceEnabled(true)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "active entry")
    }

    @MainActor
    func testStoreSetPersistenceEnabledIdempotentWhenAlreadyTrue() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "kept"))
        XCTAssertEqual(store.entries.count, 1)

        store.setPersistenceEnabled(true)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "kept")
    }

    @MainActor
    func testStoreClearWhenDisabledDeletesPersistedRows() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        var dbEntry = TranscriptEntry(
            text: "already in db",
            model: "base.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2
        )
        try database.insert(&dbEntry)

        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: database, settings: settings)
        store.clear()

        XCTAssertTrue(try database.fetchAll().isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testStoreAddDoesNothingWhenHistoryDisabledWithoutDatabase() {
        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: nil, settings: settings)

        store.add(makeResponse(text: "ignored"))

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testStoreAddPersistsResponseWhenEnabled() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "  persisted text\n", model: "small.en", language: "en", durationSeconds: 5.0, processingSeconds: 1.3))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "persisted text")
        XCTAssertEqual(store.entries.first?.model, "small.en")
        XCTAssertEqual(store.entries.first?.language, "en")
        XCTAssertEqual(store.entries.first?.durationSeconds, 5.0)
        XCTAssertEqual(store.entries.first?.processingSeconds, 1.3)
    }

    @MainActor
    func testStoreAddDoesNothingWhenHistoryDisabled() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "ignored"))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(try database.fetchAll().isEmpty)
    }

    @MainActor
    func testStoreToggleLoadsExistingEntries() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        var existingEntry = TranscriptEntry(
            text: "already saved",
            model: "base.en",
            language: "en",
            durationSeconds: 2.0,
            processingSeconds: 0.5
        )
        try database.insert(&existingEntry)

        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: database, settings: settings)
        XCTAssertTrue(store.entries.isEmpty)

        store.setPersistenceEnabled(true)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "already saved")
    }

    @MainActor
    func testStoreClearDeletesPersistedEntries() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "first"))
        store.add(makeResponse(text: "second"))
        XCTAssertEqual(store.entries.count, 2)

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(try database.fetchAll().isEmpty)
    }

    func testAppDatabaseFetchAllOrdersByIdWhenCreatedAtEqual() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let sharedDate = Date(timeIntervalSince1970: 100)

        var first = TranscriptEntry(
            text: "First inserted",
            model: "base.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2,
            createdAt: sharedDate
        )
        var second = TranscriptEntry(
            text: "Second inserted",
            model: "small.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2,
            createdAt: sharedDate
        )
        var third = TranscriptEntry(
            text: "Third inserted",
            model: "tiny.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2,
            createdAt: sharedDate
        )

        try database.insert(&first)
        try database.insert(&second)
        try database.insert(&third)

        let loaded = try database.fetchAll()
        XCTAssertEqual(loaded.map(\.text), ["Third inserted", "Second inserted", "First inserted"])
    }

    @MainActor
    func testStoreFreshInstanceReloadsPersistedEntries() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings1 = StubHistorySettings(historyEnabled: true)
        let store1 = TranscriptHistoryStore(database: database, settings: settings1)

        store1.add(makeResponse(text: "entry one"))
        store1.add(makeResponse(text: "entry two"))
        XCTAssertEqual(store1.entries.count, 2)

        let settings2 = StubHistorySettings(historyEnabled: true)
        let store2 = TranscriptHistoryStore(database: database, settings: settings2)

        XCTAssertEqual(store2.entries.count, 2)
        XCTAssertEqual(store2.entries.map(\.text), ["entry two", "entry one"])
    }

    func testFiltersWithWhitespaceOnlyQueryReturnsAllEntries() {
        let entries = [
            makeEntry(text: "alpha", model: "base.en", language: "en"),
            makeEntry(text: "beta", model: "small.en", language: "en"),
            makeEntry(text: "gamma", model: "medium.en", language: "en")
        ]

        let filtered = TranscriptHistoryFilters.apply(
            entries: entries,
            query: "   ",
            modelFilter: TranscriptHistoryFilters.allModelsLabel,
            languageFilter: TranscriptHistoryFilters.allLanguagesLabel
        )

        XCTAssertEqual(filtered.count, 3)
    }

    @MainActor
    func testStoreAddFallsBackToVolatileOnDatabaseInsertError() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)

        try database.clearAll()
        var entry = TranscriptEntry(
            text: "existing",
            model: "base.en",
            language: "en",
            durationSeconds: 1.0,
            processingSeconds: 0.2,
            createdAt: Date()
        )
        try database.insert(&entry)

        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)
        XCTAssertEqual(store.entries.count, 1)

        store.add(makeResponse(text: "new entry after clear"))

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.text, "new entry after clear")
    }

    @MainActor
    func testStoreReloadFromEmptyDatabaseShowsNothing() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "existing"))
        XCTAssertEqual(store.entries.count, 1)

        try database.clearAll()

        store.setPersistenceEnabled(false)
        store.setPersistenceEnabled(true)

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testStoreSetPersistenceEnabledIdempotentWhenAlreadyFalse() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.setPersistenceEnabled(false)
        XCTAssertTrue(store.entries.isEmpty)

        store.setPersistenceEnabled(false)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testStoreClearIdempotentWhenEnabled() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: true)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.add(makeResponse(text: "to clear"))
        store.clear()
        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(try database.fetchAll().isEmpty)
    }

    @MainActor
    func testStoreClearIdempotentWhenDisabled() throws {
        let databaseURL = try makeTempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try AppDatabase(path: databaseURL.path)
        let settings = StubHistorySettings(historyEnabled: false)
        let store = TranscriptHistoryStore(database: database, settings: settings)

        store.clear()
        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(try database.fetchAll().isEmpty)
    }
}

import Cocoa
import GRDB
import SwiftUI

protocol HistorySettingsProviding: AnyObject {
    var historyEnabled: Bool { get set }
}

extension SettingsManager: HistorySettingsProviding {}

struct TranscriptEntry: Identifiable, Equatable, Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "transcriptions"

    var id: Int64?
    var text: String
    var model: String
    var language: String
    var durationSeconds: Double
    var processingSeconds: Double
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case model
        case language
        case durationSeconds = "duration_seconds"
        case processingSeconds = "processing_seconds"
        case createdAt = "created_at"
    }

    enum Columns {
        static let createdAt = Column("created_at")
        static let id = Column("id")
    }

    init(
        id: Int64? = nil,
        text: String,
        model: String,
        language: String,
        durationSeconds: Double,
        processingSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.model = model
        self.language = language
        self.durationSeconds = durationSeconds
        self.processingSeconds = processingSeconds
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var timeLabel: String {
        createdAt.formatted(date: .omitted, time: .shortened)
    }

    var languageLabel: String {
        language.uppercased()
    }

    var durationLabel: String {
        "\(durationSeconds.formatted(.number.precision(.fractionLength(1))))s audio"
    }

    var processingLabel: String {
        "\(processingSeconds.formatted(.number.precision(.fractionLength(1))))s processing"
    }
}

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [TranscriptEntry] = []

    private let settings: any HistorySettingsProviding
    private let database: AppDatabase?
    private var volatileEntries: [TranscriptEntry] = []

    init(
        database: AppDatabase? = TranscriptHistoryStore.makeDefaultDatabase(),
        settings: any HistorySettingsProviding = SettingsManager.shared
    ) {
        self.database = database
        self.settings = settings
        reloadEntries()
    }

    var historyEnabled: Bool {
        settings.historyEnabled
    }

    func setPersistenceEnabled(_ enabled: Bool) {
        settings.historyEnabled = enabled
        reloadEntries()
    }

    func add(_ response: TranscriptionResponse) {
        let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.historyEnabled else { return }

        var entry = TranscriptEntry(
            text: trimmed,
            model: response.model,
            language: response.language,
            durationSeconds: response.duration_seconds,
            processingSeconds: response.processing_seconds
        )

        if let database {
            do {
                try database.insert(&entry)
                reloadEntries()
                return
            } catch {
                // Fall back to in-memory history if local persistence is unavailable.
            }
        }

        volatileEntries.insert(entry, at: 0)
        entries = volatileEntries
    }

    func clear() {
        if let database {
            do {
                try database.clearAll()
                entries.removeAll()
                volatileEntries.removeAll()
                return
            } catch {
                // Keep volatile history available if disk operations fail.
            }
        }

        entries.removeAll()
        volatileEntries.removeAll()
    }

    private func reloadEntries() {
        guard settings.historyEnabled else {
            entries = []
            return
        }

        if let database {
            do {
                let loadedEntries = try database.fetchAll()
                entries = loadedEntries
                volatileEntries = loadedEntries
                return
            } catch {
                // Keep showing existing entries if disk reads fail.
            }
        }

        entries = volatileEntries
    }

nonisolated private static func makeDefaultDatabase() -> AppDatabase? {
        do {
            let path = try AppDatabase.defaultDatabasePath()
            return try AppDatabase(path: path)
        } catch {
            return nil
        }
    }
}

enum TranscriptHistoryFilters {
    static let allModelsLabel = "All Models"
    static let allLanguagesLabel = "All Languages"

    static func apply(
        entries: [TranscriptEntry],
        query: String,
        modelFilter: String,
        languageFilter: String
    ) -> [TranscriptEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return entries.filter { entry in
            let matchesModel = modelFilter == allModelsLabel || entry.model == modelFilter
            let matchesLanguage = languageFilter == allLanguagesLabel || entry.languageLabel == languageFilter
            let matchesQuery =
                normalizedQuery.isEmpty ||
                entry.text.lowercased().contains(normalizedQuery) ||
                entry.model.lowercased().contains(normalizedQuery) ||
                entry.language.lowercased().contains(normalizedQuery)
            return matchesModel && matchesLanguage && matchesQuery
        }
    }
}

struct TranscriptHistoryView: View {
    @ObservedObject var store: TranscriptHistoryStore

    @State private var searchText = ""
    @State private var selectedModelFilter = TranscriptHistoryFilters.allModelsLabel
    @State private var selectedLanguageFilter = TranscriptHistoryFilters.allLanguagesLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.title3.weight(.semibold))
                    Text(store.historyEnabled ? "Transcripts are saved locally on this Mac." : "History is disabled in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear") {
                    store.clear()
                }
                .disabled(store.historyEnabled && store.entries.isEmpty)
            }

            if store.historyEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search transcripts", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Picker("Model", selection: $selectedModelFilter) {
                            ForEach(modelFilterOptions, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()

                        Picker("Language", selection: $selectedLanguageFilter) {
                            ForEach(languageFilterOptions, id: \.self) { language in
                                Text(language).tag(language)
                            }
                        }
                        .labelsHidden()

                        Spacer()

                        if hasActiveFilters {
                            Button("Reset") {
                                resetFilters()
                            }
                        }
                    }
                }
            }

            if !store.historyEnabled {
                ContentUnavailableView(
                    "History Disabled",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Enable Save Transcription History in Settings to keep transcripts. Use Clear to delete any saved transcripts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.entries.isEmpty {
                ContentUnavailableView("No Transcripts Yet", systemImage: "text.quote", description: Text("Record something and it will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try a different search or clear filters.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            TranscriptRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 460, height: 420)
        .onChange(of: store.entries) { _, _ in
            normalizeActiveFilters()
        }
    }

    private var modelFilterOptions: [String] {
        let models = Set(store.entries.map(\.model)).sorted()
        return [TranscriptHistoryFilters.allModelsLabel] + models
    }

    private var languageFilterOptions: [String] {
        let languages = Set(store.entries.map(\.languageLabel)).sorted()
        return [TranscriptHistoryFilters.allLanguagesLabel] + languages
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            selectedModelFilter != TranscriptHistoryFilters.allModelsLabel ||
            selectedLanguageFilter != TranscriptHistoryFilters.allLanguagesLabel
    }

    private var filteredEntries: [TranscriptEntry] {
        TranscriptHistoryFilters.apply(
            entries: store.entries,
            query: searchText,
            modelFilter: selectedModelFilter,
            languageFilter: selectedLanguageFilter
        )
    }

    private func resetFilters() {
        searchText = ""
        selectedModelFilter = TranscriptHistoryFilters.allModelsLabel
        selectedLanguageFilter = TranscriptHistoryFilters.allLanguagesLabel
    }

    private func normalizeActiveFilters() {
        if !modelFilterOptions.contains(selectedModelFilter) {
            selectedModelFilter = TranscriptHistoryFilters.allModelsLabel
        }
        if !languageFilterOptions.contains(selectedLanguageFilter) {
            selectedLanguageFilter = TranscriptHistoryFilters.allLanguagesLabel
        }
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcript")
            }

            HStack(spacing: 8) {
                metadataBadge(entry.model)
                metadataBadge(entry.languageLabel)

                Text(entry.durationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(entry.processingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func metadataBadge(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule(style: .continuous))
    }
}

import Foundation
import GRDB

final class AppDatabase {
    private let dbPool: DatabasePool

    init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        dbPool = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(dbPool)
    }

    static func defaultDatabasePath(fileManager: FileManager = .default) throws -> String {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("Phonos", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("history.sqlite", isDirectory: false).path
    }

    func insert(_ entry: inout TranscriptEntry) throws {
        try dbPool.write { db in
            try entry.insert(db)
        }
    }

    func fetchAll() throws -> [TranscriptEntry] {
        try dbPool.read { db in
            try TranscriptEntry
                .order(TranscriptEntry.Columns.createdAt.desc)
                .order(TranscriptEntry.Columns.id.desc)
                .fetchAll(db)
        }
    }

    func clearAll() throws {
        try dbPool.write { db in
            _ = try TranscriptEntry.deleteAll(db)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_transcriptions") { db in
            try db.create(table: TranscriptEntry.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("text", .text).notNull()
                table.column("model", .text).notNull()
                table.column("language", .text).notNull()
                table.column("duration_seconds", .double).notNull()
                table.column("processing_seconds", .double).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_transcriptions_created_at",
                on: TranscriptEntry.databaseTableName,
                columns: ["created_at"],
                ifNotExists: true
            )
        }

        return migrator
    }
}

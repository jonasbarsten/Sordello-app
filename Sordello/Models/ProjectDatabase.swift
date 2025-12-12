//
//  ProjectDatabase.swift
//  Sordello
//
//  Per-project database manager using GRDB
//  Each Ableton project gets its own database at <project>/.sordello/db/sordello.db
//  This ensures all metadata travels with the project when moved between computers
//
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation
import GRDB

/// Manages a per-project SQLite database using GRDB
/// Each project folder has its own database at .sordello/db/sordello.db
/// nonisolated: GRDB's DatabaseQueue is thread-safe, safe to use from any thread
nonisolated class ProjectDatabase {

    /// The database connection
    private(set) var dbQueue: DatabaseQueue?

    /// Path to the database file
    private(set) var databasePath: String?

    /// Path to the project folder this database belongs to
    let projectPath: String

    /// Whether the database is ready
    private(set) var isReady = false

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    // MARK: - Database Setup

    /// Initialize the database for this project
    /// Creates .sordello/db/ directory and database file if they don't exist
    func setup() throws {
        let fileManager = FileManager.default
        let projectUrl = URL(fileURLWithPath: projectPath)

        // Create .sordello/db/ directory
        let sordelloDir = projectUrl.appendingPathComponent(".sordello")
        let dbDir = sordelloDir.appendingPathComponent("db")

        try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("sordello.db").path
        self.databasePath = dbPath

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Run migrations
        try migrate()

        isReady = true
        print("ProjectDatabase: Ready at \(dbPath)")
    }

    /// Close the database connection
    func close() {
        dbQueue = nil
        isReady = false
        print("ProjectDatabase: Closed for \(projectPath)")
    }

    /// Run database migrations
    private func migrate() throws {
        guard let db = dbQueue else { return }

        var migrator = DatabaseMigrator()

        // v1: Initial schema
        migrator.registerMigration("v1") { db in
            // Projects table (mainly for metadata, path is this project)
            try db.create(table: "projects") { t in
                t.primaryKey("path", .text)
                t.column("lastUpdated", .datetime).notNull()
            }

            // LiveSets table
            try db.create(table: "live_sets") { t in
                t.primaryKey("path", .text)
                t.column("projectPath", .text)
                    .references("projects", column: "path", onDelete: .cascade)
                t.column("category", .text).notNull()
                t.column("liveVersion", .text).notNull().defaults(to: "Unknown")
                t.column("comment", .text)
                t.column("lastUpdated", .datetime).notNull()
                t.column("fileModificationDate", .datetime)
                t.column("isParsed", .boolean).notNull().defaults(to: false)
                t.column("backupTimestamp", .datetime)
                t.column("parentLiveSetPath", .text)
                t.column("sourceLiveSetName", .text)
                t.column("sourceGroupId", .integer)
                t.column("sourceGroupName", .text)
                t.column("extractedAt", .datetime)
            }

            // Tracks table
            try db.create(table: "tracks") { t in
                t.column("liveSetPath", .text)
                    .references("live_sets", column: "path", onDelete: .cascade)
                t.column("trackId", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("originalName", .text).notNull()
                t.column("isModified", .boolean).notNull().defaults(to: false)
                t.column("type", .text).notNull()
                t.column("parentGroupId", .integer)
                t.column("sortIndex", .text).notNull().defaults(to: "a")
                t.column("subprojectPath", .text)
                t.column("bounceReady", .boolean).notNull().defaults(to: false)
                t.column("color", .integer).notNull().defaults(to: 0)
                t.column("isFrozen", .boolean).notNull().defaults(to: false)
                t.column("trackDelay", .double).notNull().defaults(to: 0)
                t.column("isDelayInSamples", .boolean).notNull().defaults(to: false)
                t.column("audioInputJSON", .text)
                t.column("audioOutputJSON", .text)
                t.column("midiInputJSON", .text)
                t.column("midiOutputJSON", .text)

                // Composite primary key
                t.primaryKey(["liveSetPath", "trackId"])
            }

            // ConnectedDevices table (for OSC connections)
            try db.create(table: "connected_devices") { t in
                t.primaryKey("instanceId", .text)
                t.column("projectPath", .text)
                    .references("projects", column: "path", onDelete: .cascade)
                t.column("liveVersion", .text).notNull()
                t.column("connectedAt", .datetime).notNull()
            }

            // Indexes for common queries
            try db.create(index: "live_sets_projectPath", on: "live_sets", columns: ["projectPath"])
            try db.create(index: "live_sets_category", on: "live_sets", columns: ["category"])
            try db.create(index: "tracks_liveSetPath", on: "tracks", columns: ["liveSetPath"])
            try db.create(index: "tracks_parentGroupId", on: "tracks", columns: ["parentGroupId"])
        }

        // v2: Add autoVersionEnabled to live_sets
        migrator.registerMigration("v2") { db in
            try db.alter(table: "live_sets") { t in
                t.add(column: "autoVersionEnabled", .boolean).notNull().defaults(to: true)
            }
        }

        // v3: Rename sourceGroupId/Name to sourceTrackId/Name
        migrator.registerMigration("v3") { db in
            try db.alter(table: "live_sets") { t in
                t.rename(column: "sourceGroupId", to: "sourceTrackId")
                t.rename(column: "sourceGroupName", to: "sourceTrackName")
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Project Operations

    func getOrCreateProject() throws -> Project {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.write { db in
            if let existing = try Project.fetchOne(db, key: projectPath) {
                return existing
            }
            let project = Project(path: projectPath)
            try project.insert(db)
            return project
        }
    }

    func updateProject(_ project: Project) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try project.update(db)
        }
    }

    func fetchProject() throws -> Project? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try Project.fetchOne(db, key: projectPath)
        }
    }

    // MARK: - LiveSet Operations

    func insertLiveSet(_ liveSet: LiveSet) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            let ls = liveSet
            try ls.insert(db)
        }
    }

    func updateLiveSet(_ liveSet: LiveSet) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try liveSet.update(db)
        }
    }

    func deleteLiveSet(path: String) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try LiveSet.deleteOne(db, key: path)
        }
    }

    func fetchLiveSet(path: String) throws -> LiveSet? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet.fetchOne(db, key: path)
        }
    }

    func fetchAllLiveSets() throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .order(Column("category"), Column("path"))
                .fetchAll(db)
        }
    }

    func fetchMainLiveSets() throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.main.rawValue)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    func fetchSubprojectLiveSets() throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.liveSetTrackVersion.rawValue)
                .fetchAll(db)
        }
    }

    func fetchBackupLiveSets() throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.backup.rawValue)
                .order(Column("backupTimestamp").desc)
                .fetchAll(db)
        }
    }

    func fetchVersionLiveSets(forParentPath parentPath: String) throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("category") == FileCategory.version.rawValue)
                .filter(Column("parentLiveSetPath") == parentPath)
                .order(Column("path").desc)
                .fetchAll(db)
        }
    }

    func deleteAllLiveSets() throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .deleteAll(db)
        }
    }

    // MARK: - Track Operations

    func insertTrack(_ track: LiveSetTrack) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            let t = track
            try t.insert(db)
        }
    }

    func updateTrack(_ track: LiveSetTrack) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try track.update(db)
        }
    }

    func deleteTracksForLiveSet(liveSetPath: String) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .deleteAll(db)
        }
    }

    func fetchTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchRootTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("parentGroupId") == nil)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchChildTracks(forLiveSetPath liveSetPath: String, parentGroupId: Int) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("parentGroupId") == parentGroupId)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchTrack(liveSetPath: String, trackId: Int) throws -> LiveSetTrack? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("trackId") == trackId)
                .fetchOne(db)
        }
    }

    func fetchGroupTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("type") == TrackType.group.rawValue)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    // MARK: - Batch Operations

    func insertTracks(_ tracks: [LiveSetTrack]) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            for track in tracks {
                try track.insert(db)
            }
        }
    }

    func saveLiveSetWithTracks(_ liveSet: LiveSet, tracks: [LiveSetTrack]) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            // Update or insert LiveSet
            try liveSet.save(db)

            // Delete existing tracks
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSet.path)
                .deleteAll(db)

            // Insert new tracks
            for var track in tracks {
                track.liveSetPath = liveSet.path
                try track.insert(db)
            }
        }
    }

    // MARK: - Async Observation (use with for-await loops)

    /// Observe all LiveSets in this project
    func observeLiveSets() -> ValueObservation<ValueReducers.Fetch<[LiveSet]>> {
        ValueObservation.tracking { [projectPath] db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .order(Column("category"), Column("path"))
                .fetchAll(db)
        }
    }

    /// Observe main LiveSets
    func observeMainLiveSets() -> ValueObservation<ValueReducers.Fetch<[LiveSet]>> {
        ValueObservation.tracking { [projectPath] db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.main.rawValue)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    /// Observe tracks for a LiveSet
    func observeTracks(forLiveSetPath liveSetPath: String) -> ValueObservation<ValueReducers.Fetch<[LiveSetTrack]>> {
        ValueObservation.tracking { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    /// Observe root tracks for a LiveSet
    func observeRootTracks(forLiveSetPath liveSetPath: String) -> ValueObservation<ValueReducers.Fetch<[LiveSetTrack]>> {
        ValueObservation.tracking { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("parentGroupId") == nil)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    /// Observe child tracks of a group
    func observeChildTracks(forLiveSetPath liveSetPath: String, parentGroupId: Int) -> ValueObservation<ValueReducers.Fetch<[LiveSetTrack]>> {
        ValueObservation.tracking { db in
            try LiveSetTrack
                .filter(Column("liveSetPath") == liveSetPath)
                .filter(Column("parentGroupId") == parentGroupId)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    /// Observe version LiveSets for a parent
    func observeVersionLiveSets(forParentPath parentPath: String) -> ValueObservation<ValueReducers.Fetch<[LiveSet]>> {
        ValueObservation.tracking { db in
            try LiveSet
                .filter(Column("category") == FileCategory.version.rawValue)
                .filter(Column("parentLiveSetPath") == parentPath)
                .order(Column("path").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Error Types

    enum DatabaseError: Error, LocalizedError {
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Project database not connected"
            }
        }
    }
}

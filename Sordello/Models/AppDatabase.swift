//
//  AppDatabase.swift
//  Sordello
//
//  Database manager for GRDB - replaces SwiftData ModelContainer
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation
import GRDB

/// Manages the app's SQLite database using GRDB
final class AppDatabase {
    static let shared = AppDatabase()

    /// The database connection
    private(set) var dbQueue: DatabaseQueue?

    /// Whether the database is ready
    private(set) var isReady = false

    private init() {}

    // MARK: - Database Setup

    /// Initialize the database (call from app startup)
    func setup() throws {
        // Store in Application Support
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.setupFailed("Could not find Application Support directory")
        }

        // Create app directory if needed
        let appDir = appSupport.appendingPathComponent(K.app.supportDir)
        try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbPath = appDir.appendingPathComponent(K.app.dbFile).path

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Run migrations
        try migrate()

        isReady = true
        print("AppDatabase: Ready at \(dbPath)")
    }

    /// Run database migrations
    private func migrate() throws {
        guard let db = dbQueue else { return }

        var migrator = DatabaseMigrator()

        // v1: Initial schema
        migrator.registerMigration("v1") { db in
            // Projects table
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
                t.column("sourceTrackId", .integer)
                t.column("sourceTrackName", .text)
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

            // ConnectedDevices table
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

        try migrator.migrate(db)
    }

    /// Clear all data (for fresh start on each launch, like SwiftData was doing)
    func clearAllData() throws {
        guard let db = dbQueue else { return }

        try db.write { db in
            try LiveSetTrack.deleteAll(db)
            try LiveSet.deleteAll(db)
            try Project.deleteAll(db)
            try ConnectedDevice.deleteAll(db)
        }
        print("AppDatabase: Cleared all data")
    }

    // MARK: - Project Operations

    func getOrCreateProject(path: String) throws -> Project {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.write { db in
            if let existing = try Project.fetchOne(db, key: path) {
                return existing
            }
            let project = Project(path: path)
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

    func fetchProject(path: String) throws -> Project? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try Project.fetchOne(db, key: path)
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

    func fetchLiveSets(forProjectPath projectPath: String) throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .fetchAll(db)
        }
    }

    func fetchMainLiveSets(forProjectPath projectPath: String) throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.main.rawValue)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    func fetchSubprojectLiveSets(forProjectPath projectPath: String) throws -> [LiveSet] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.liveSetTrackVersion.rawValue)
                .fetchAll(db)
        }
    }

    func fetchBackupLiveSets(forProjectPath projectPath: String) throws -> [LiveSet] {
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

    func deleteLiveSetsForProject(projectPath: String) throws {
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

    /// Observe projects - returns AsyncValueObservation for use with for-await
    func observeProjects() -> ValueObservation<ValueReducers.Fetch<[Project]>> {
        ValueObservation.tracking { db in
            try Project
                .order(Column("lastUpdated").desc)
                .fetchAll(db)
        }
    }

    /// Observe LiveSets for a project
    func observeLiveSets(forProjectPath projectPath: String) -> ValueObservation<ValueReducers.Fetch<[LiveSet]>> {
        ValueObservation.tracking { db in
            try LiveSet
                .filter(Column("projectPath") == projectPath)
                .order(Column("category"), Column("path"))
                .fetchAll(db)
        }
    }

    /// Observe main LiveSets for a project
    func observeMainLiveSets(forProjectPath projectPath: String) -> ValueObservation<ValueReducers.Fetch<[LiveSet]>> {
        ValueObservation.tracking { db in
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
        case setupFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Database not connected"
            case .setupFailed(let reason):
                return "Database setup failed: \(reason)"
            }
        }
    }
}

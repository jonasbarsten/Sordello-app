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
        let dbDir = projectUrl.appendingPathComponent(K.sordello.dbPath)

        try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent(K.sordello.dbFile).path
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

        // v1: Initial schema with ProjectItems (replaces LiveSets)
        migrator.registerMigration("v1_project_items") { db in
            // Projects table (mainly for metadata, path is this project)
            try db.create(table: "projects") { t in
                t.primaryKey("path", .text)
                t.column("lastUpdated", .datetime).notNull()
            }

            // ProjectItems table (any file or directory in the project)
            try db.create(table: "project_items") { t in
                t.primaryKey("path", .text)
                t.column("projectPath", .text)
                    .references("projects", column: "path", onDelete: .cascade)
                t.column("itemType", .text).notNull()  // directory, als, wav, mid, etc.
                t.column("category", .text).notNull()
                t.column("comment", .text)
                t.column("lastUpdated", .datetime).notNull()
                t.column("fileModificationDate", .datetime)
                t.column("isParsed", .boolean).notNull().defaults(to: false)
                t.column("backupTimestamp", .datetime)
                t.column("parentItemPath", .text)
                t.column("autoVersionEnabled", .boolean).notNull().defaults(to: true)
                // ALS-specific fields (nullable, only used for .als files)
                t.column("liveVersion", .text)
                t.column("sourceLiveSetName", .text)
                t.column("sourceTrackId", .integer)
                t.column("sourceTrackName", .text)
                t.column("extractedAt", .datetime)
            }

            // Tracks table (for .als files)
            try db.create(table: "tracks") { t in
                t.column("projectItemPath", .text)
                    .references("project_items", column: "path", onDelete: .cascade)
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
                t.primaryKey(["projectItemPath", "trackId"])
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
            try db.create(index: "project_items_projectPath", on: "project_items", columns: ["projectPath"])
            try db.create(index: "project_items_category", on: "project_items", columns: ["category"])
            try db.create(index: "project_items_itemType", on: "project_items", columns: ["itemType"])
            try db.create(index: "tracks_projectItemPath", on: "tracks", columns: ["projectItemPath"])
            try db.create(index: "tracks_parentGroupId", on: "tracks", columns: ["parentGroupId"])
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

    // MARK: - ProjectItem Operations

    func insertProjectItem(_ item: ProjectItem) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try item.insert(db)
        }
    }

    func updateProjectItem(_ item: ProjectItem) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try item.update(db)
        }
    }

    func deleteProjectItem(path: String) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try ProjectItem.deleteOne(db, key: path)
        }
    }

    func fetchProjectItem(path: String) throws -> ProjectItem? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem.fetchOne(db, key: path)
        }
    }

    func fetchAllProjectItems() throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .order(Column("category"), Column("path"))
                .fetchAll(db)
        }
    }

    func fetchProjectItems(ofType itemType: ItemType) throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .filter(Column("itemType") == itemType.rawValue)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    func fetchMainProjectItems() throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.main.rawValue)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    func fetchSubprojectItems() throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.liveSetTrackVersion.rawValue)
                .fetchAll(db)
        }
    }

    func fetchBackupProjectItems() throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .filter(Column("category") == FileCategory.backup.rawValue)
                .order(Column("backupTimestamp").desc)
                .fetchAll(db)
        }
    }

    func fetchVersionProjectItems(forParentPath parentPath: String) throws -> [ProjectItem] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try ProjectItem
                .filter(Column("category") == FileCategory.version.rawValue)
                .filter(Column("parentItemPath") == parentPath)
                .order(Column("path").desc)
                .fetchAll(db)
        }
    }

    func deleteAllProjectItems() throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try ProjectItem
                .filter(Column("projectPath") == projectPath)
                .deleteAll(db)
        }
    }

    // MARK: - Backwards Compatibility Aliases

    func insertLiveSet(_ liveSet: LiveSet) throws { try insertProjectItem(liveSet) }
    func updateLiveSet(_ liveSet: LiveSet) throws { try updateProjectItem(liveSet) }
    func deleteLiveSet(path: String) throws { try deleteProjectItem(path: path) }
    func fetchLiveSet(path: String) throws -> LiveSet? { try fetchProjectItem(path: path) }
    func fetchAllLiveSets() throws -> [LiveSet] { try fetchAllProjectItems() }
    func fetchMainLiveSets() throws -> [LiveSet] { try fetchMainProjectItems() }
    func fetchSubprojectLiveSets() throws -> [LiveSet] { try fetchSubprojectItems() }
    func fetchBackupLiveSets() throws -> [LiveSet] { try fetchBackupProjectItems() }
    func fetchVersionLiveSets(forParentPath parentPath: String) throws -> [LiveSet] { try fetchVersionProjectItems(forParentPath: parentPath) }
    func deleteAllLiveSets() throws { try deleteAllProjectItems() }

    // MARK: - Track Operations

    func insertTrack(_ track: LiveSetTrack) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try track.insert(db)
        }
    }

    func updateTrack(_ track: LiveSetTrack) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            try track.update(db)
        }
    }

    func deleteTracksForProjectItem(projectItemPath: String) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .deleteAll(db)
        }
    }

    func fetchTracks(forProjectItemPath projectItemPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchRootTracks(forProjectItemPath projectItemPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .filter(Column("parentGroupId") == nil)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchChildTracks(forProjectItemPath projectItemPath: String, parentGroupId: Int) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .filter(Column("parentGroupId") == parentGroupId)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    func fetchTrack(projectItemPath: String, trackId: Int) throws -> LiveSetTrack? {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .filter(Column("trackId") == trackId)
                .fetchOne(db)
        }
    }

    func fetchGroupTracks(forProjectItemPath projectItemPath: String) throws -> [LiveSetTrack] {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        return try db.read { db in
            try LiveSetTrack
                .filter(Column("projectItemPath") == projectItemPath)
                .filter(Column("type") == TrackType.group.rawValue)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    // MARK: - Track Backwards Compatibility Aliases

    func deleteTracksForLiveSet(liveSetPath: String) throws { try deleteTracksForProjectItem(projectItemPath: liveSetPath) }
    func fetchTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] { try fetchTracks(forProjectItemPath: liveSetPath) }
    func fetchRootTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] { try fetchRootTracks(forProjectItemPath: liveSetPath) }
    func fetchChildTracks(forLiveSetPath liveSetPath: String, parentGroupId: Int) throws -> [LiveSetTrack] { try fetchChildTracks(forProjectItemPath: liveSetPath, parentGroupId: parentGroupId) }
    func fetchTrack(liveSetPath: String, trackId: Int) throws -> LiveSetTrack? { try fetchTrack(projectItemPath: liveSetPath, trackId: trackId) }
    func fetchGroupTracks(forLiveSetPath liveSetPath: String) throws -> [LiveSetTrack] { try fetchGroupTracks(forProjectItemPath: liveSetPath) }

    // MARK: - Batch Operations

    func insertTracks(_ tracks: [LiveSetTrack]) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            for track in tracks {
                try track.insert(db)
            }
        }
    }

    func saveProjectItemWithTracks(_ item: ProjectItem, tracks: [LiveSetTrack]) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            // Update or insert ProjectItem
            try item.save(db)

            // Delete existing tracks
            try LiveSetTrack
                .filter(Column("projectItemPath") == item.path)
                .deleteAll(db)

            // Insert new tracks
            for var track in tracks {
                track.projectItemPath = item.path
                try track.insert(db)
            }
        }
    }

    func saveLiveSetWithTracks(_ liveSet: LiveSet, tracks: [LiveSetTrack]) throws {
        try saveProjectItemWithTracks(liveSet, tracks: tracks)
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

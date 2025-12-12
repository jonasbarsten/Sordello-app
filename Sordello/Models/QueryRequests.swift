//
//  QueryRequests.swift
//  Sordello
//
//  ValueObservationQueryable requests for @Query property wrapper
//

import Foundation
import GRDB
import GRDBQuery

// MARK: - LiveSet Requests

struct MainLiveSetsRequest: ValueObservationQueryable {
    let projectPath: String

    static var defaultValue: [LiveSet] { [] }

    func fetch(_ db: Database) throws -> [LiveSet] {
        try LiveSet
            .filter(Column("projectPath") == projectPath)
            .filter(Column("category") == FileCategory.main.rawValue)
            .order(Column("path"))
            .fetchAll(db)
    }
}

struct VersionLiveSetsRequest: ValueObservationQueryable {
    let projectPath: String

    static var defaultValue: [LiveSet] { [] }

    func fetch(_ db: Database) throws -> [LiveSet] {
        try LiveSet
            .filter(Column("projectPath") == projectPath)
            .filter(Column("category") == FileCategory.version.rawValue)
            .order(Column("path").desc)
            .fetchAll(db)
    }
}

struct SubprojectLiveSetsRequest: ValueObservationQueryable {
    let projectPath: String

    static var defaultValue: [LiveSet] { [] }

    func fetch(_ db: Database) throws -> [LiveSet] {
        try LiveSet
            .filter(Column("projectPath") == projectPath)
            .filter(Column("category") == FileCategory.liveSetTrackVersion.rawValue)
            .order(Column("path"))
            .fetchAll(db)
    }
}

struct BackupLiveSetsRequest: ValueObservationQueryable {
    let projectPath: String

    static var defaultValue: [LiveSet] { [] }

    func fetch(_ db: Database) throws -> [LiveSet] {
        try LiveSet
            .filter(Column("projectPath") == projectPath)
            .filter(Column("category") == FileCategory.backup.rawValue)
            .order(Column("backupTimestamp").desc)
            .fetchAll(db)
    }
}

struct SingleLiveSetRequest: ValueObservationQueryable {
    let path: String

    static var defaultValue: LiveSet? { nil }

    func fetch(_ db: Database) throws -> LiveSet? {
        try LiveSet.fetchOne(db, key: path)
    }
}

// MARK: - Track Requests

struct RootTracksRequest: ValueObservationQueryable {
    let liveSetPath: String

    static var defaultValue: [LiveSetTrack] { [] }

    func fetch(_ db: Database) throws -> [LiveSetTrack] {
        try LiveSetTrack
            .filter(Column("liveSetPath") == liveSetPath)
            .filter(Column("parentGroupId") == nil)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

struct ChildTracksRequest: ValueObservationQueryable {
    let liveSetPath: String
    let parentGroupId: Int

    static var defaultValue: [LiveSetTrack] { [] }

    func fetch(_ db: Database) throws -> [LiveSetTrack] {
        try LiveSetTrack
            .filter(Column("liveSetPath") == liveSetPath)
            .filter(Column("parentGroupId") == parentGroupId)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

struct AllTracksRequest: ValueObservationQueryable {
    let liveSetPath: String

    static var defaultValue: [LiveSetTrack] { [] }

    func fetch(_ db: Database) throws -> [LiveSetTrack] {
        try LiveSetTrack
            .filter(Column("liveSetPath") == liveSetPath)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

struct TrackVersionsRequest: ValueObservationQueryable {
    let projectPath: String
    let sourceLiveSetName: String
    let sourceTrackId: Int

    static var defaultValue: [LiveSet] { [] }

    func fetch(_ db: Database) throws -> [LiveSet] {
        try LiveSet
            .filter(Column("projectPath") == projectPath)
            .filter(Column("category") == FileCategory.liveSetTrackVersion.rawValue)
            .filter(Column("sourceLiveSetName") == sourceLiveSetName)
            .filter(Column("sourceTrackId") == sourceTrackId)
            .order(Column("extractedAt").desc)
            .fetchAll(db)
    }
}

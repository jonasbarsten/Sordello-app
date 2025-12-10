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
            .filter(Column("category") == LiveSetCategory.main.rawValue)
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
            .filter(Column("category") == LiveSetCategory.version.rawValue)
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
            .filter(Column("category") == LiveSetCategory.subproject.rawValue)
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
            .filter(Column("category") == LiveSetCategory.backup.rawValue)
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

    static var defaultValue: [Track] { [] }

    func fetch(_ db: Database) throws -> [Track] {
        try Track
            .filter(Column("liveSetPath") == liveSetPath)
            .filter(Column("parentGroupId") == nil)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

struct ChildTracksRequest: ValueObservationQueryable {
    let liveSetPath: String
    let parentGroupId: Int

    static var defaultValue: [Track] { [] }

    func fetch(_ db: Database) throws -> [Track] {
        try Track
            .filter(Column("liveSetPath") == liveSetPath)
            .filter(Column("parentGroupId") == parentGroupId)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

struct AllTracksRequest: ValueObservationQueryable {
    let liveSetPath: String

    static var defaultValue: [Track] { [] }

    func fetch(_ db: Database) throws -> [Track] {
        try Track
            .filter(Column("liveSetPath") == liveSetPath)
            .order(Column("sortIndex"))
            .fetchAll(db)
    }
}

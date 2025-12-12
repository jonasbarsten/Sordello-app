//
//  GRDBModels.swift
//  Sordello
//
//  GRDB models replacing SwiftData
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation
import GRDB

// MARK: - Enums

/// Track type in Ableton
enum TrackType: String, Codable, DatabaseValueConvertible {
    case audio = "AudioTrack"
    case midi = "MidiTrack"
    case group = "GroupTrack"
    case returnTrack = "ReturnTrack"
}

/// Sort order for lists
enum SortOrder: String, Codable {
    case ascending
    case descending
}

// MARK: - GRDB Models

/// Represents an Ableton Live Project folder
struct Project: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable, Hashable {
    static let databaseTableName = "projects"

    /// Primary key - folder path
    var id: String { path }
    var path: String
    var lastUpdated: Date

    /// Computed: Project name (folder name without " Project" suffix)
    var name: String {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        return folderName.replacingOccurrences(of: " Project", with: "")
    }

    init(path: String) {
        self.path = path
        self.lastUpdated = Date()
    }

    // MARK: - Associations
    static let liveSets = hasMany(LiveSet.self)
    static let devices = hasMany(ConnectedDevice.self)

    var liveSets: QueryInterfaceRequest<LiveSet> {
        request(for: Project.liveSets)
    }

    var devices: QueryInterfaceRequest<ConnectedDevice> {
        request(for: Project.devices)
    }
}

/// Represents an individual .als file (Live Set)
nonisolated struct LiveSet: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable, ProjectFile, Hashable {
    static let databaseTableName = "live_sets"
    static let fileExtension = "als"

    /// Primary key - file path
    var id: String { path }
    var path: String

    /// Foreign key to project
    var projectPath: String?

    var category: FileCategory
    var liveVersion: String
    var comment: String?
    var lastUpdated: Date

    /// File modification date on disk (for detecting changes)
    var fileModificationDate: Date?

    /// Whether the .als file has been parsed (tracks extracted)
    var isParsed: Bool

    /// For backup files: extracted timestamp from filename for sorting
    var backupTimestamp: Date?

    /// For version files: the parent LiveSet's path
    var parentLiveSetPath: String?

    /// Subproject metadata
    var sourceLiveSetName: String?
    var sourceTrackId: Int?
    var sourceTrackName: String?
    var extractedAt: Date?

    /// Whether to auto-create versions when this LiveSet is saved (main LiveSets only)
    var autoVersionEnabled: Bool

    /// Computed: Name from path
    var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Computed: Has subproject metadata
    var hasMetadata: Bool {
        sourceLiveSetName != nil && sourceTrackId != nil
    }

    init(path: String, category: FileCategory) {
        self.path = path
        self.category = category
        self.liveVersion = "Unknown"
        self.lastUpdated = Date()
        self.isParsed = false
        self.autoVersionEnabled = true

        // Extract backup timestamp if this is a backup
        if category == .backup {
            self.backupTimestamp = Self.extractBackupTimestamp(from: path)
        }
    }

    /// Extract timestamp from backup filename format: "Name [YYYY-MM-DD HHMMSS].als"
    static func extractBackupTimestamp(from path: String) -> Date? {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let pattern = #"\[(\d{4}-\d{2}-\d{2}) (\d{6})\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let dateRange = Range(match.range(at: 1), in: name),
              let timeRange = Range(match.range(at: 2), in: name) else {
            return nil
        }

        let dateStr = String(name[dateRange])
        let timeStr = String(name[timeRange])

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.date(from: "\(dateStr) \(timeStr)")
    }

    // MARK: - Associations
    static let project = belongsTo(Project.self)
    static let tracks = hasMany(LiveSetTrack.self)

    var project: QueryInterfaceRequest<Project> {
        request(for: LiveSet.project)
    }

    var tracks: QueryInterfaceRequest<LiveSetTrack> {
        request(for: LiveSet.tracks)
    }
}

/// Represents a track in an Ableton Live Set
struct LiveSetTrack: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tracks"

    /// Compound primary key: liveSetPath + trackId
    var id: String { "\(liveSetPath ?? ""):\(trackId)" }

    /// Foreign key to LiveSet
    var liveSetPath: String?

    /// Ableton track ID (unique within a LiveSet)
    var trackId: Int
    var name: String

    /// Original name from the .als file (for detecting changes)
    var originalName: String

    /// Stored flag for efficient querying of modified tracks
    var isModified: Bool

    var type: TrackType

    /// Parent group track ID (-1 or nil means root level)
    var parentGroupId: Int?

    /// Lexicographic fractional index for visual ordering
    var sortIndex: String

    /// Link to subproject if this group was extracted
    var subprojectPath: String?
    var bounceReady: Bool

    /// Track properties
    var color: Int
    var isFrozen: Bool
    var trackDelay: Double
    var isDelayInSamples: Bool

    /// Routing (stored as JSON strings)
    var audioInputJSON: String?
    var audioOutputJSON: String?
    var midiInputJSON: String?
    var midiOutputJSON: String?

    /// Computed: Is this a group track
    var isGroup: Bool {
        type == .group
    }

    /// Computed: Is this a root level track
    var isRootLevel: Bool {
        parentGroupId == nil || parentGroupId == -1
    }

    /// Computed: Has the name been changed from the original
    var hasNameChange: Bool {
        name != originalName && !originalName.isEmpty
    }

    /// Get a human-readable color name for the Ableton color index
    var colorName: String {
        let colors = [
            "Rose", "Red", "Orange", "Light Orange", "Light Yellow",
            "Yellow", "Lime", "Green", "Mint", "Cyan",
            "Sky", "Light Blue", "Blue", "Purple", "Violet",
            "Magenta", "Pink", "Light Gray", "Medium Gray", "Dark Gray"
        ]
        guard color >= 0 && color < colors.count else { return "Unknown" }
        return colors[color]
    }

    init(trackId: Int, name: String, type: TrackType, parentGroupId: Int?) {
        self.trackId = trackId
        self.name = name
        self.originalName = name
        self.type = type
        self.parentGroupId = parentGroupId == -1 ? nil : parentGroupId
        self.sortIndex = "a"
        self.isModified = false
        self.bounceReady = false
        self.color = 0
        self.isFrozen = false
        self.trackDelay = 0
        self.isDelayInSamples = false
    }

    // MARK: - Routing Helpers

    struct RoutingInfo: Codable, Sendable {
        let target: String
        let displayName: String
        let channel: String
    }

    var audioInput: RoutingInfo? {
        get {
            guard let json = audioInputJSON else { return nil }
            return try? JSONDecoder().decode(RoutingInfo.self, from: Data(json.utf8))
        }
        set {
            audioInputJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var audioOutput: RoutingInfo? {
        get {
            guard let json = audioOutputJSON else { return nil }
            return try? JSONDecoder().decode(RoutingInfo.self, from: Data(json.utf8))
        }
        set {
            audioOutputJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var midiInput: RoutingInfo? {
        get {
            guard let json = midiInputJSON else { return nil }
            return try? JSONDecoder().decode(RoutingInfo.self, from: Data(json.utf8))
        }
        set {
            midiInputJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var midiOutput: RoutingInfo? {
        get {
            guard let json = midiOutputJSON else { return nil }
            return try? JSONDecoder().decode(RoutingInfo.self, from: Data(json.utf8))
        }
        set {
            midiOutputJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    // MARK: - Associations
    static let liveSet = belongsTo(LiveSet.self)

    var liveSet: QueryInterfaceRequest<LiveSet> {
        request(for: LiveSetTrack.liveSet)
    }
}

/// Represents a connected M4L device
struct ConnectedDevice: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "connected_devices"

    /// Primary key
    var id: String { instanceId }
    var instanceId: String

    /// Foreign key to project
    var projectPath: String?

    var liveVersion: String
    var connectedAt: Date

    var projectName: String {
        guard let path = projectPath else { return "Unknown" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    init(instanceId: String, projectPath: String, liveVersion: String) {
        self.instanceId = instanceId
        self.projectPath = projectPath
        self.liveVersion = liveVersion
        self.connectedAt = Date()
    }

    // MARK: - Associations
    static let project = belongsTo(Project.self)

    var project: QueryInterfaceRequest<Project> {
        request(for: ConnectedDevice.project)
    }
}

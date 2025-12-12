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

/// Type of item in the project (file or directory)
enum ItemType: String, Codable, DatabaseValueConvertible, Sendable {
    case directory
    case als          // Ableton Live Set
    case wav          // WAV audio
    case aif          // AIFF audio
    case mp3          // MP3 audio
    case flac         // FLAC audio
    case ogg          // OGG audio
    case mid          // MIDI file
    case other        // Any other file type

    /// Create from file extension
    nonisolated static func from(extension ext: String) -> ItemType {
        switch ext.lowercased() {
        case "als": return .als
        case "wav": return .wav
        case "aif", "aiff": return .aif
        case "mp3": return .mp3
        case "flac": return .flac
        case "ogg": return .ogg
        case "mid", "midi": return .mid
        default: return .other
        }
    }

    /// Create from path
    nonisolated static func from(path: String, isDirectory: Bool) -> ItemType {
        if isDirectory { return .directory }
        let ext = URL(fileURLWithPath: path).pathExtension
        return from(extension: ext)
    }
}

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
    static let projectItems = hasMany(ProjectItem.self)
    static let devices = hasMany(ConnectedDevice.self)

    var projectItems: QueryInterfaceRequest<ProjectItem> {
        request(for: Project.projectItems)
    }

    var devices: QueryInterfaceRequest<ConnectedDevice> {
        request(for: Project.devices)
    }

    // Alias for backwards compatibility
    var liveSets: QueryInterfaceRequest<ProjectItem> {
        projectItems
    }
}

/// Represents any file or directory tracked in a project
struct ProjectItem: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable, Hashable {
    static let databaseTableName = "project_items"

    /// Primary key - file path
    var id: String { path }
    var path: String

    /// Foreign key to project
    var projectPath: String?

    /// Type of item (directory, als, wav, mid, etc.)
    var itemType: ItemType

    var category: FileCategory
    var comment: String?
    var lastUpdated: Date

    /// File modification date on disk (for detecting changes)
    var fileModificationDate: Date?

    /// Whether the file has been parsed (e.g., tracks extracted from .als)
    var isParsed: Bool

    /// For backup files: extracted timestamp from filename for sorting
    var backupTimestamp: Date?

    /// For version files: the parent item's path
    var parentItemPath: String?

    // MARK: - ALS-specific fields (only used when itemType == .als)

    /// Ableton Live version (only for .als files)
    var liveVersion: String?

    /// Subproject metadata (only for .als files)
    var sourceLiveSetName: String?
    var sourceTrackId: Int?
    var sourceTrackName: String?
    var extractedAt: Date?

    /// Whether to auto-create versions when this item is saved
    var autoVersionEnabled: Bool

    /// Computed: Name from path
    var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Computed: File extension
    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    /// Computed: Is this an Ableton Live Set
    var isLiveSet: Bool {
        itemType == .als
    }

    /// Computed: Is this a directory
    var isDirectory: Bool {
        itemType == .directory
    }

    /// Computed: Has subproject metadata
    var hasMetadata: Bool {
        sourceLiveSetName != nil && sourceTrackId != nil
    }

    init(path: String, projectPath: String? = nil, category: FileCategory, itemType: ItemType? = nil, isParsed: Bool = false) {
        self.path = path
        self.projectPath = projectPath
        self.category = category
        self.itemType = itemType ?? ItemType.from(path: path, isDirectory: false)
        self.lastUpdated = Date()
        self.isParsed = isParsed
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
    static let tracks = hasMany(LiveSetTrack.self, using: LiveSetTrack.projectItemForeignKey)

    var project: QueryInterfaceRequest<Project> {
        request(for: ProjectItem.project)
    }

    var tracks: QueryInterfaceRequest<LiveSetTrack> {
        request(for: ProjectItem.tracks)
    }
}

// MARK: - Type alias for backwards compatibility during migration
typealias LiveSet = ProjectItem

/// Represents a track in an Ableton Live Set
struct LiveSetTrack: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tracks"

    /// Compound primary key: projectItemPath + trackId
    var id: String { "\(projectItemPath ?? ""):\(trackId)" }

    /// Foreign key to ProjectItem
    var projectItemPath: String?

    /// Alias for backwards compatibility
    var liveSetPath: String? {
        get { projectItemPath }
        set { projectItemPath = newValue }
    }

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
    static let projectItemForeignKey = ForeignKey(["projectItemPath"])
    static let projectItem = belongsTo(ProjectItem.self, using: projectItemForeignKey)

    var projectItem: QueryInterfaceRequest<ProjectItem> {
        request(for: LiveSetTrack.projectItem)
    }

    // Alias for backwards compatibility
    var liveSet: QueryInterfaceRequest<ProjectItem> {
        projectItem
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

//
//  SwiftDataModels.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation
import SwiftData

// MARK: - Enums

/// Category of a Live Set within a project
enum SDLiveSetCategory: String, Codable, CaseIterable {
    case main       // Main .als files in root
    case subproject // Files starting with .subproject-
    case version    // Files starting with .version-
    case backup     // Files in Backup/ folder
}

/// Track type in Ableton
enum SDTrackType: String, Codable {
    case audio = "AudioTrack"
    case midi = "MidiTrack"
    case group = "GroupTrack"
    case returnTrack = "ReturnTrack"
}

/// Sort order for lists
enum SDSortOrder: String, Codable {
    case ascending
    case descending
}

// MARK: - SwiftData Models

/// Represents an Ableton Live Project folder
@Model
final class SDProject {
    /// Unique identifier - folder path
    @Attribute(.unique) var path: String
    var lastUpdated: Date = Date()

    /// Relationships
    @Relationship(deleteRule: .cascade, inverse: \SDLiveSet.project)
    var liveSets: [SDLiveSet] = []

    @Relationship(deleteRule: .cascade, inverse: \SDConnectedDevice.project)
    var devices: [SDConnectedDevice] = []

    /// Computed: Project name (folder name without " Project" suffix)
    var name: String {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        return folderName.replacingOccurrences(of: " Project", with: "")
    }

    init(path: String) {
        self.path = path
        self.lastUpdated = Date()
    }
}

/// Represents an individual .als file (Live Set)
@Model
final class SDLiveSet {
    /// Unique identifier - file path
    @Attribute(.unique) var path: String

    /// Category stored as raw string for predicate support
    var categoryRaw: String = SDLiveSetCategory.main.rawValue

    var liveVersion: String = "Unknown"
    var comment: String?
    var lastUpdated: Date = Date()

    /// File modification date on disk (for detecting changes)
    var fileModificationDate: Date?

    /// For backup files: extracted timestamp from filename for sorting
    var backupTimestamp: Date?

    /// For version files: the parent LiveSet's path
    var parentLiveSetPath: String?

    /// Subproject metadata
    var sourceLiveSetName: String?
    var sourceGroupId: Int?
    var sourceGroupName: String?
    var extractedAt: Date?

    /// Relationships
    var project: SDProject?

    @Relationship(deleteRule: .cascade, inverse: \SDTrack.liveSet)
    var tracks: [SDTrack] = []

    /// Computed: Category enum
    var category: SDLiveSetCategory {
        get { SDLiveSetCategory(rawValue: categoryRaw) ?? .main }
        set { categoryRaw = newValue.rawValue }
    }

    /// Computed: Name from path
    var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Computed: Has subproject metadata
    var hasMetadata: Bool {
        sourceLiveSetName != nil && sourceGroupId != nil
    }

    init(path: String, category: SDLiveSetCategory) {
        self.path = path
        self.categoryRaw = category.rawValue
        self.lastUpdated = Date()

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
}

/// Represents a track in an Ableton project
@Model
final class SDTrack {
    /// Ableton track ID (unique within a LiveSet)
    var trackId: Int = 0
    var name: String = ""

    /// Track type stored as raw string for predicate support
    var typeRaw: String = SDTrackType.audio.rawValue

    /// Parent group track ID (-1 or nil means root level)
    var parentGroupId: Int?

    /// Link to subproject if this group was extracted
    var subprojectPath: String?
    var bounceReady: Bool = false

    /// Track properties
    var color: Int = 0
    var isFrozen: Bool = false
    var trackDelay: Double = 0
    var isDelayInSamples: Bool = false

    /// Routing (stored as JSON strings for simplicity)
    var audioInputJSON: String?
    var audioOutputJSON: String?
    var midiInputJSON: String?
    var midiOutputJSON: String?

    /// Relationships
    var liveSet: SDLiveSet?

    /// Computed: Track type enum
    var type: SDTrackType {
        get { SDTrackType(rawValue: typeRaw) ?? .audio }
        set { typeRaw = newValue.rawValue }
    }

    /// Computed: Is this a group track
    var isGroup: Bool {
        type == .group
    }

    /// Computed: Is this a root level track
    var isRootLevel: Bool {
        parentGroupId == nil || parentGroupId == -1
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

    init(trackId: Int, name: String, type: SDTrackType, parentGroupId: Int?) {
        self.trackId = trackId
        self.name = name
        self.typeRaw = type.rawValue
        self.parentGroupId = parentGroupId == -1 ? nil : parentGroupId
    }

    // MARK: - Routing Helpers

    struct RoutingInfo: Codable {
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
}

/// Represents a connected M4L device
@Model
final class SDConnectedDevice {
    @Attribute(.unique) var instanceId: String
    var projectPath: String = ""
    var liveVersion: String = ""
    var connectedAt: Date = Date()

    /// Relationships
    var project: SDProject?

    var projectName: String {
        URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
    }

    init(instanceId: String, projectPath: String, liveVersion: String) {
        self.instanceId = instanceId
        self.projectPath = projectPath
        self.liveVersion = liveVersion
        self.connectedAt = Date()
    }
}

// MARK: - App State (Non-persisted UI state)

/// UI state that doesn't need persistence - kept in memory
@Observable
final class UIState {
    static let shared = UIState()

    var selectedProjectPath: String?
    var selectedLiveSetPath: String?
    var selectedTrackId: Int?
    var isInspectorVisible: Bool = false
    var liveSetSortOrder: SDSortOrder = .ascending
    var expandedLiveSets: Set<String> = []

    private init() {}
}

// MARK: - Predicates

/// Predicate builders for querying SwiftData
enum SDPredicates {
    /// LiveSets for a specific project
    static func liveSets(forProjectPath projectPath: String) -> Predicate<SDLiveSet> {
        #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath
        }
    }

    /// Main LiveSets for a project
    static func mainLiveSets(forProjectPath projectPath: String) -> Predicate<SDLiveSet> {
        let mainCategory = SDLiveSetCategory.main.rawValue
        return #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == mainCategory
        }
    }

    /// Subproject LiveSets for a project
    static func subprojectLiveSets(forProjectPath projectPath: String) -> Predicate<SDLiveSet> {
        let subprojectCategory = SDLiveSetCategory.subproject.rawValue
        return #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == subprojectCategory
        }
    }

    /// Backup LiveSets for a project
    static func backupLiveSets(forProjectPath projectPath: String) -> Predicate<SDLiveSet> {
        let backupCategory = SDLiveSetCategory.backup.rawValue
        return #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == backupCategory
        }
    }

    /// Version LiveSets for a specific parent LiveSet
    static func versionLiveSets(forParentPath parentPath: String) -> Predicate<SDLiveSet> {
        let versionCategory = SDLiveSetCategory.version.rawValue
        return #Predicate<SDLiveSet> { liveSet in
            liveSet.categoryRaw == versionCategory && liveSet.parentLiveSetPath == parentPath
        }
    }

    /// Tracks for a specific LiveSet
    static func tracks(forLiveSetPath liveSetPath: String) -> Predicate<SDTrack> {
        #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath
        }
    }

    /// Root level tracks for a LiveSet
    static func rootTracks(forLiveSetPath liveSetPath: String) -> Predicate<SDTrack> {
        #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.parentGroupId == nil
        }
    }

    /// Child tracks of a group
    static func childTracks(forLiveSetPath liveSetPath: String, parentGroupId: Int) -> Predicate<SDTrack> {
        #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.parentGroupId == parentGroupId
        }
    }

    /// Tracks of a specific type in a LiveSet
    static func tracks(forLiveSetPath liveSetPath: String, type: SDTrackType) -> Predicate<SDTrack> {
        let typeRaw = type.rawValue
        return #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.typeRaw == typeRaw
        }
    }
}

// MARK: - Sort Descriptors

/// Sort descriptor builders
enum SDSortDescriptors {
    /// Main LiveSets sorted by name
    static func liveSetsByName(ascending: Bool = true) -> SortDescriptor<SDLiveSet> {
        SortDescriptor(\SDLiveSet.path, order: ascending ? .forward : .reverse)
    }

    /// Backup LiveSets sorted by timestamp
    static var backupsByTimestamp: SortDescriptor<SDLiveSet> {
        SortDescriptor(\SDLiveSet.backupTimestamp, order: .reverse)
    }

    /// Tracks by trackId (preserves order from .als file)
    static var tracksByTrackId: SortDescriptor<SDTrack> {
        SortDescriptor(\SDTrack.trackId, order: .forward)
    }
}

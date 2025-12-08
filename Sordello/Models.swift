//
//  Models.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation

/// Represents a connected M4L device
struct ConnectedDevice: Identifiable, Hashable {
    let id: String  // instanceId from M4L
    let projectPath: String
    let liveVersion: String
    let connectedAt: Date

    var projectName: String {
        URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
    }
}

/// Routing information for a track
struct TrackRouting: Hashable {
    let target: String       // Raw target value (e.g., "AudioOut/Master")
    let displayName: String  // Upper display string (e.g., "Master")
    let channel: String      // Lower display string (e.g., "1/2")
}

/// Represents a track in an Ableton project
struct Track: Identifiable, Hashable {
    let id: Int  // Ableton track ID
    let name: String
    let type: TrackType
    let parentGroupId: Int?  // -1 or nil means root level
    var children: [Track] = []
    var subprojectPath: String? = nil
    var bounceReady: Bool = false

    // Additional track properties for inspector
    var color: Int = 0                      // Ableton color index
    var isFrozen: Bool = false              // Track freeze status
    var trackDelay: Double = 0              // Track delay in ms
    var isDelayInSamples: Bool = false      // Whether delay is sample-based
    var audioInput: TrackRouting?           // Audio input routing
    var audioOutput: TrackRouting?          // Audio output routing
    var midiInput: TrackRouting?            // MIDI input routing
    var midiOutput: TrackRouting?           // MIDI output routing

    enum TrackType: String, Hashable {
        case audio = "AudioTrack"
        case midi = "MidiTrack"
        case group = "GroupTrack"
        case returnTrack = "ReturnTrack"
    }

    var isGroup: Bool {
        type == .group
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
}

/// Category of a Live Set within a project
enum LiveSetCategory: String, CaseIterable {
    case main       // Main .als files in root
    case subproject // Files starting with .subproject-
    case version    // Files starting with .version-
    case backup     // Files in Backup/ folder
}

/// Metadata for a subproject, stored in companion -meta.json file
struct SubprojectMetadata: Codable {
    let sourceLiveSetName: String   // Name of the source LiveSet
    let sourceGroupId: Int          // ID of the group track that was extracted
    let sourceGroupName: String     // Name of the group at extraction time
    let extractedAt: Date           // When the subproject was created

    /// Generate the metadata filename for a subproject
    static func metadataFileName(for subprojectPath: String) -> String {
        let url = URL(fileURLWithPath: subprojectPath)
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName)-meta.json"
    }
}

/// Represents an individual .als file (Live Set)
@Observable
class LiveSet: Identifiable, Hashable {
    let id: String  // File path as ID
    let path: String
    let category: LiveSetCategory
    var liveVersion: String = "Unknown"
    var tracks: [Track] = []
    var versions: [LiveSet] = []  // Version files linked to this LiveSet
    var comment: String?  // Optional comment for version files
    var metadata: SubprojectMetadata?  // Metadata for subprojects (source group info)
    var lastUpdated: Date = Date()

    var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Root level tracks (not inside any group)
    var rootTracks: [Track] {
        tracks.filter { $0.parentGroupId == nil || $0.parentGroupId == -1 }
    }

    /// Get all groups in the Live Set
    var groups: [Track] {
        tracks.filter { $0.isGroup }
    }

    /// Extract timestamp from backup filename format: "Name [YYYY-MM-DD HHMMSS].als"
    var backupTimestamp: Date? {
        guard category == .backup else { return nil }

        // Look for pattern [YYYY-MM-DD HHMMSS] at end of name
        let pattern = #"\[(\d{4}-\d{2}-\d{2}) (\d{6})\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let dateRange = Range(match.range(at: 1), in: name),
              let timeRange = Range(match.range(at: 2), in: name) else {
            return nil
        }

        let dateStr = String(name[dateRange])  // "2024-03-15"
        let timeStr = String(name[timeRange])  // "232647"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.date(from: "\(dateStr) \(timeStr)")
    }

    init(path: String, category: LiveSetCategory) {
        self.id = path
        self.path = path
        self.category = category
    }

    static func == (lhs: LiveSet, rhs: LiveSet) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Build hierarchical track structure from flat list (supports infinite nesting)
    func buildHierarchy() {
        var childrenByParent: [Int: [Track]] = [:]
        for track in tracks {
            let parentId = track.parentGroupId ?? -1
            childrenByParent[parentId, default: []].append(track)
        }

        func buildTrackWithChildren(_ track: Track) -> Track {
            var result = track
            result.children = []
            if track.isGroup {
                let children = childrenByParent[track.id] ?? []
                result.children = children.map { buildTrackWithChildren($0) }
            }
            return result
        }

        tracks = tracks.map { buildTrackWithChildren($0) }
    }

    /// Link group tracks to their extracted subprojects
    func linkTracksToSubprojects(project: Project) {
        // Build a map of source group ID -> subproject path for subprojects from this LiveSet
        var subprojectsByGroupId: [Int: String] = [:]
        for subproject in project.subprojectLiveSets {
            if let metadata = subproject.metadata,
               metadata.sourceLiveSetName == self.name {
                subprojectsByGroupId[metadata.sourceGroupId] = subproject.path
            }
        }

        guard !subprojectsByGroupId.isEmpty else { return }

        // Recursively update tracks to link them to subprojects
        func linkTrack(_ track: Track) -> Track {
            var result = track
            if track.isGroup, let subprojectPath = subprojectsByGroupId[track.id] {
                result.subprojectPath = subprojectPath
                print("Linked group '\(track.name)' (ID: \(track.id)) to subproject")
            }
            result.children = track.children.map { linkTrack($0) }
            return result
        }

        tracks = tracks.map { linkTrack($0) }
    }
}

/// Represents an Ableton Live Project folder
@Observable
class Project: Identifiable, Hashable {
    let id: String  // Folder path as ID
    let path: String  // Path to the project folder
    var liveSets: [LiveSet] = []
    var devices: [ConnectedDevice] = []
    var lastUpdated: Date = Date()

    var name: String {
        // Remove " Project" suffix if present
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        return folderName.replacingOccurrences(of: " Project", with: "")
    }

    /// Main Live Sets (sorted by name)
    var mainLiveSets: [LiveSet] {
        liveSets.filter { $0.category == .main }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Subproject Live Sets
    var subprojectLiveSets: [LiveSet] {
        liveSets.filter { $0.category == .subproject }
    }

    /// Backup Live Sets (sorted by timestamp, newest first)
    var backupLiveSets: [LiveSet] {
        liveSets
            .filter { $0.category == .backup }
            .sorted { ($0.backupTimestamp ?? .distantPast) > ($1.backupTimestamp ?? .distantPast) }
    }

    init(path: String) {
        self.id = path
        self.path = path
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Sort order for lists
enum SortOrder: String {
    case ascending
    case descending
}

/// Main app state managing all connected projects
@Observable
class AppState {
    static let shared = AppState()

    var projects: [Project] = []
    var selectedProject: Project?
    var selectedLiveSet: LiveSet?
    var selectedTrack: Track?
    var isInspectorVisible: Bool = false  // Inspector visibility toggle
    var liveSetSortOrder: SortOrder = .ascending  // Sort order for main live sets

    init() {}

    /// Find or create a project for the given folder path
    func getOrCreateProject(folderPath: String) -> Project {
        if let existing = projects.first(where: { $0.path == folderPath }) {
            return existing
        }
        let project = Project(path: folderPath)
        projects.append(project)
        return project
    }

    /// Register a new device (from M4L)
    func registerDevice(_ device: ConnectedDevice) {
        // Extract folder path from als path
        let alsUrl = URL(fileURLWithPath: device.projectPath)
        let folderPath = alsUrl.deletingLastPathComponent().path
        let project = getOrCreateProject(folderPath: folderPath)
        if !project.devices.contains(where: { $0.id == device.id }) {
            project.devices.append(device)
        }
        project.lastUpdated = Date()
    }

    /// Unregister a device
    func unregisterDevice(instanceId: String) {
        for project in projects {
            project.devices.removeAll { $0.id == instanceId }
        }
    }

    /// Find device by instance ID
    func findDevice(instanceId: String) -> (Project, ConnectedDevice)? {
        for project in projects {
            if let device = project.devices.first(where: { $0.id == instanceId }) {
                return (project, device)
            }
        }
        return nil
    }
}

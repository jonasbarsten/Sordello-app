//
//  ProjectManager.swift
//  Sordello
//
//  Created by Jonas Barsten on 10/12/2025.
//

import SwiftUI
import AppKit
import GRDB

/// Parsing progress for a project
struct ParsingProgress: Sendable {
    var total: Int
    var completed: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var isComplete: Bool {
        total > 0 && completed >= total
    }
}

/// Manages project opening and file access
/// Uses per-project GRDB databases for persistence
@Observable
final class ProjectManager {
    static let shared = ProjectManager()

    /// Per-project databases keyed by project path
    private var projectDatabases: [String: ProjectDatabase] = [:]

    /// Per-project version control (file-based)
    private var versionControls: [String: VersionControl] = [:]

    /// List of currently open project paths (for UI)
    private(set) var openProjectPaths: [String] = []

    /// Parsing progress per project (for UI progress bars)
    var parsingProgress: [String: ParsingProgress] = [:]

    /// Get the database for a project
    func database(forProjectPath path: String) -> ProjectDatabase? {
        return projectDatabases[path]
    }

    /// Get the version control for a project
    func versionControl(forProjectPath path: String) -> VersionControl? {
        return versionControls[path]
    }

    /// Start tracking parsing progress for a project
    @MainActor
    func startParsingProgress(for projectPath: String, total: Int) {
        parsingProgress[projectPath] = ParsingProgress(total: total, completed: 0)
    }

    /// Update parsing progress for a project
    @MainActor
    func updateParsingProgress(for projectPath: String, completed: Int) {
        guard var progress = parsingProgress[projectPath] else { return }
        progress.completed = completed
        parsingProgress[projectPath] = progress
    }

    /// Clear parsing progress for a project (when done)
    @MainActor
    func clearParsingProgress(for projectPath: String) {
        parsingProgress.removeValue(forKey: projectPath)
    }


    /// Get all open projects with their data
    func getOpenProjects() -> [Project] {
        var projects: [Project] = []
        for path in openProjectPaths {
            if let db = projectDatabases[path],
               let project = try? db.fetchProject() {
                projects.append(project)
            }
        }
        return projects.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Get a project by its path
    func getProject(byPath path: String) -> Project? {
        guard let db = projectDatabases[path] else { return nil }
        return try? db.fetchProject()
    }

    private init() {}

    /// Open a project folder using NSOpenPanel
    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Ableton Live Project"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select an Ableton Live Project folder"

        if panel.runModal() == .OK, let url = panel.url {
            // Validate it's an Ableton Live Project folder
            guard FileScanner.isValidAbletonProject(at: url) else {
                showInvalidProjectAlert(for: url)
                return
            }

            // Create security-scoped bookmark for the directory (gives us write access)
            BookmarkManager.shared.saveBookmark(for: url)
            loadProject(at: url)
        }
    }

    /// Show alert for invalid project folder
    private func showInvalidProjectAlert(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "No Live Sets Found"
        alert.informativeText = "The selected folder doesn't contain any .als files."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Load a project folder and scan for .als files - writes to per-project GRDB database
    func loadProject(at folderUrl: URL) {
        // Start accessing for initial load
        let accessing = folderUrl.startAccessingSecurityScopedResource()

        // Fix any _subproject files first
//        fixSubprojectFilenames(in: folderUrl)

        do {
            // Create or get the project database at .sordello/db/sordello.db
            let projectDb: ProjectDatabase
            if let existing = projectDatabases[folderUrl.path] {
                projectDb = existing
            } else {
                projectDb = ProjectDatabase(projectPath: folderUrl.path)
                try projectDb.setup()
                projectDatabases[folderUrl.path] = projectDb
            }

            // Initialize version control (file-based) at .sordello/versions/
            if versionControls[folderUrl.path] == nil {
                let vc = VersionControl(projectPath: folderUrl.path)
                try vc.initializeIfNeeded()
                versionControls[folderUrl.path] = vc
            }

            // Get or create the project record
            let project = try projectDb.getOrCreateProject()

            // Check if we already have LiveSets (database existed with data)
            let existingLiveSets = try projectDb.fetchAllLiveSets()

            if existingLiveSets.isEmpty {
                // Fresh database - do full scan
                print("Fresh project database, doing full scan...")
                let liveSetPaths = try FileScanner.scanAndSaveLiveSets(in: folderUrl, for: project, db: projectDb)
                parseAllLiveSetsInBackground(liveSetPaths: liveSetPaths, projectPath: project.path)
            } else {
                // Existing data - do incremental update to preserve parsed data
                print("Existing project database with \(existingLiveSets.count) LiveSets, doing incremental update...")
                let result = try FileScanner.incrementalUpdate(in: folderUrl, for: project, db: projectDb)
                handleIncrementalUpdateResults(result, project: project, db: projectDb)
            }

            // Add to open projects list if not already there
            if !openProjectPaths.contains(project.path) {
                openProjectPaths.append(project.path)
            }

            // Note: UI state selection is handled by the views observing openProjectPaths changes
        } catch {
            print("Failed to load project: \(error)")
        }

        if accessing { folderUrl.stopAccessingSecurityScopedResource() }

        // Watch the folder for changes
        let projectPath = folderUrl.path
        FileWatcher.shared.watchFile(at: projectPath) {
            // Small delay to let file operations complete
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                ProjectManager.shared.reloadProject(folderPath: projectPath)
            }
        }
    }

    /// Parse all LiveSets in background using AlsHandler
    private func parseAllLiveSetsInBackground(liveSetPaths: [String], projectPath: String) {
        guard let bookmarkData = BookmarkManager.shared.getBookmarkData(for: projectPath),
              let projectDb = projectDatabases[projectPath] else {
            print("No bookmark or database found for project: \(projectPath)")
            return
        }

        print("Starting parallel parsing of \(liveSetPaths.count) LiveSets...")
        AlsHandler.parseAllInBackground(paths: liveSetPaths, bookmarkData: bookmarkData, db: projectDb, projectPath: projectPath)
    }

    /// Internal parsing method using AlsHandler
    private func parseLiveSetInternal(_ liveSet: LiveSet) {
        guard let projectPath = liveSet.projectPath,
              let projectDb = projectDatabases[projectPath] else {
            print("Failed to save parsed LiveSet: no project database found")
            return
        }

        _ = AlsHandler.parseAndSave(liveSet, to: projectDb)
    }

    /// Parse a specific LiveSet
    func parseLiveSet(_ liveSet: LiveSet) {
        guard let projectPath = liveSet.projectPath else { return }

        BookmarkManager.shared.accessFile(at: projectPath) { _ in
            self.parseLiveSetInternal(liveSet)
            self.linkTracksToSubprojects(liveSet: liveSet, projectPath: projectPath)
        }
    }

    /// Link group tracks to their extracted subprojects
    private func linkTracksToSubprojects(liveSet: LiveSet, projectPath: String) {
        guard let projectDb = projectDatabases[projectPath] else { return }

        do {
            // Find subprojects for this LiveSet
            let subprojects = try projectDb.fetchSubprojectLiveSets()

            // Build map of source track ID -> subproject path
            var subprojectsByTrackId: [Int: String] = [:]
            for subproject in subprojects {
                if let sourceTrackId = subproject.sourceTrackId,
                   subproject.sourceLiveSetName == liveSet.name {
                    subprojectsByTrackId[sourceTrackId] = subproject.path
                }
            }

            guard !subprojectsByTrackId.isEmpty else { return }

            // Update tracks
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            for var track in tracks where track.isGroup {
                if let subprojectPath = subprojectsByTrackId[track.trackId] {
                    track.subprojectPath = subprojectPath
                    try projectDb.updateTrack(track)
                    print("Linked group '\(track.name)' (ID: \(track.trackId)) to subproject")
                }
            }
        } catch {
            print("Failed to link tracks to subprojects: \(error)")
        }
    }

    /// Reload a project folder after changes
    private func reloadProject(folderPath: String) {
        BookmarkManager.shared.accessFile(at: folderPath) { folderUrl in
            do {
                guard let projectDb = self.projectDatabases[folderPath],
                      let project = try projectDb.fetchProject() else { return }
                let result = try FileScanner.incrementalUpdate(in: folderUrl, for: project, db: projectDb)
                self.handleIncrementalUpdateResults(result, project: project, db: projectDb)
            } catch {
                print("Failed to reload project: \(error)")
            }
        }
    }

    /// Handle the results of an incremental update - parse changed files and manage versions
    private func handleIncrementalUpdateResults(_ result: FileScanner.IncrementalUpdateResult, project: Project, db: ProjectDatabase) {
        let toReparse = result.allToReparse
        guard !toReparse.isEmpty else {
            print("No files changed")
            return
        }

        print("Re-parsing \(toReparse.count) LiveSet(s)...")
        for liveSet in toReparse {
            autoreleasepool {
                parseLiveSetInternal(liveSet)
            }
        }

        // Re-link subprojects for main LiveSets that changed
        for liveSet in toReparse where liveSet.category == .main {
            linkTracksToSubprojects(liveSet: liveSet, projectPath: project.path)
        }

        // Auto-save versions of CHANGED main LiveSets only (not new files)
        if let vc = versionControls[project.path] {
            for liveSet in result.changed where liveSet.category == .main && liveSet.autoVersionEnabled {
                do {
                    let versionPath = vc.versionPath(for: liveSet.path)
                    try vc.createCopy(of: liveSet.path, to: versionPath)
                } catch {
                    print("VersionControl: Failed to save version of \(liveSet.name): \(error)")
                }
            }
        }
    }

    /// Rescan a project folder to update the live sets list
    func rescanProject(projectPath: String) {
        BookmarkManager.shared.accessFile(at: projectPath) { folderUrl in
            do {
                guard let projectDb = self.projectDatabases[projectPath],
                      let project = try projectDb.fetchProject() else { return }
                let liveSetPaths = try FileScanner.scanAndSaveLiveSets(in: folderUrl, for: project, db: projectDb)
                self.parseAllLiveSetsInBackground(liveSetPaths: liveSetPaths, projectPath: projectPath)
            } catch {
                print("Failed to rescan project: \(error)")
            }
        }
    }

    /// Create a version of a LiveSet
    func createVersion(of liveSet: LiveSet) {
        guard let projectPath = liveSet.projectPath,
              let vc = versionControls[projectPath],
              let projectDb = projectDatabases[projectPath] else { return }

        // Generate version path
        let versionPath = vc.versionPath(for: liveSet.path)

        // Insert a copy immediately so it appears in UI
        var copy = liveSet
        copy.path = versionPath
        copy.category = .version
        copy.parentLiveSetPath = liveSet.path
        copy.isParsed = false
        try? projectDb.insertLiveSet(copy)

        // Create file on disk in background, then trigger reload
        Task {
            do {
                try await vc.createCopyAsync(of: liveSet.path, to: versionPath)
                self.reloadProject(folderPath: projectPath)
            } catch {
                print("Failed to create version: \(error.localizedDescription)")
            }
        }
    }

    /// Create a version of a track (extracts it to a new .als file)
    func createLiveSetTrackVersion(liveSetPath: String, trackId: Int, trackName: String, projectPath: String) {
        // Get project path and original LiveSet
        guard let vc = versionControls[projectPath],
              let projectDb = projectDatabases[projectPath],
              let originalLiveSet = try? projectDb.fetchLiveSet(path: liveSetPath) else { return }

        // Generate output path
        let outputPath = vc.liveSetTrackVersionPath(for: liveSetPath, trackId: trackId)

        // Insert a placeholder as copy of original (inherits fileModificationDate for change detection)
        var placeholder = originalLiveSet
        placeholder.path = outputPath
        placeholder.category = .liveSetTrackVersion
        placeholder.parentLiveSetPath = liveSetPath
        placeholder.sourceLiveSetName = originalLiveSet.name
        placeholder.sourceTrackId = trackId
        placeholder.sourceTrackName = trackName
        placeholder.extractedAt = Date()
        placeholder.isParsed = false
        try? projectDb.insertLiveSet(placeholder)

        // Extract in background
        Task {
            // Access the project folder for file operations
            guard let bookmarkData = BookmarkManager.shared.getBookmarkData(for: projectPath),
                  let resolved = BookmarkManager.resolveBookmark(bookmarkData) else {
                print("Failed to access project folder")
                return
            }
            defer {
                if resolved.needsStopAccess {
                    resolved.url.stopAccessingSecurityScopedResource()
                }
            }

            // Create parent directories
            let outputUrl = URL(fileURLWithPath: outputPath)
            let parentDir = outputUrl.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Extract the track
            let extractor = AlsExtractor()
            let result = extractor.extractTrack(from: liveSetPath, trackId: trackId, to: outputPath)

            if result.success {
                print("Created track version: \(outputUrl.lastPathComponent) (\(result.tracksExtracted) tracks)")
                self.reloadProject(folderPath: projectPath)
            } else {
                print("Failed to create track version: \(result.error ?? "unknown error")")
                // Remove placeholder on failure
                try? projectDb.deleteLiveSet(path: outputPath)
            }
        }
    }

    /// Save a comment for a LiveSet
    func saveComment(for liveSet: LiveSet, comment: String) {
        guard let projectPath = liveSet.projectPath else { return }

        let url = URL(fileURLWithPath: liveSet.path)
        let baseName = url.deletingPathExtension().lastPathComponent
        let commentFileName = "\(baseName)-comment.txt"
        let folderUrl = url.deletingLastPathComponent()
        let commentUrl = folderUrl.appendingPathComponent(commentFileName)

        BookmarkManager.shared.accessFile(at: projectPath) { _ in
            do {
                let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedComment.isEmpty {
                    // Delete the comment file if comment is empty
                    if FileManager.default.fileExists(atPath: commentUrl.path) {
                        try FileManager.default.removeItem(at: commentUrl)
                        print("Deleted comment file: \(commentFileName)")
                    }
                } else {
                    // Write the comment to file
                    try trimmedComment.write(to: commentUrl, atomically: true, encoding: .utf8)
                    print("Saved comment: \(commentFileName)")
                }

                // Update LiveSet in database
                guard let projectDb = self.projectDatabases[projectPath] else { return }
                var updatedLiveSet = liveSet
                updatedLiveSet.comment = trimmedComment.isEmpty ? nil : trimmedComment
                try projectDb.updateLiveSet(updatedLiveSet)
            } catch {
                print("Failed to save comment: \(error.localizedDescription)")
            }
        }
    }
}

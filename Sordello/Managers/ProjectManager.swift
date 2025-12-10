//
//  ProjectManager.swift
//  Sordello
//
//  Created by Jonas Barsten on 10/12/2025.
//

import SwiftUI
import AppKit
import GRDB

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

    /// Get the database for a project
    func database(forProjectPath path: String) -> ProjectDatabase? {
        return projectDatabases[path]
    }

    /// Get the version control for a project
    func versionControl(forProjectPath path: String) -> VersionControl? {
        return versionControls[path]
    }

    /// Get the current project's database (convenience for UI state)
    var currentDatabase: ProjectDatabase? {
        guard let path = UIState.shared.selectedProjectPath else { return nil }
        return projectDatabases[path]
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
                let toReparse = try FileScanner.incrementalUpdate(in: folderUrl, for: project, db: projectDb)
                handleIncrementalUpdateResults(toReparse, project: project, db: projectDb)
            }

            // Sync any orphaned version files to the database
            if let vc = versionControls[folderUrl.path] {
                let mainLiveSets = try projectDb.fetchMainLiveSets()
                try vc.syncVersionsToDatabase(db: projectDb, mainLiveSets: mainLiveSets)
            }

            // Add to open projects list if not already there
            if !openProjectPaths.contains(project.path) {
                openProjectPaths.append(project.path)
            }

            // Select the project in UI state
            UIState.shared.selectedProjectPath = project.path

            // Auto-select the first main LiveSet
            if let firstMain = try projectDb.fetchMainLiveSets().first {
                UIState.shared.selectedLiveSetPath = firstMain.path
            }
        } catch {
            print("Failed to load project: \(error)")
        }

        if accessing { folderUrl.stopAccessingSecurityScopedResource() }

        // Watch the folder for changes
        FileWatcher.shared.watchFile(at: folderUrl.path) { [weak self] in
            print("Folder changed: \(folderUrl.path)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.reloadProject(folderPath: folderUrl.path)
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
        AlsHandler.parseAllInBackground(paths: liveSetPaths, bookmarkData: bookmarkData, db: projectDb)
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

            // Build map of source group ID -> subproject path
            var subprojectsByGroupId: [Int: String] = [:]
            for subproject in subprojects {
                if let sourceGroupId = subproject.sourceGroupId,
                   subproject.sourceLiveSetName == liveSet.name {
                    subprojectsByGroupId[sourceGroupId] = subproject.path
                }
            }

            guard !subprojectsByGroupId.isEmpty else { return }

            // Update tracks
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            for var track in tracks where track.isGroup {
                if let subprojectPath = subprojectsByGroupId[track.trackId] {
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
                let toReparse = try FileScanner.incrementalUpdate(in: folderUrl, for: project, db: projectDb)
                self.handleIncrementalUpdateResults(toReparse, project: project, db: projectDb)
            } catch {
                print("Failed to reload project: \(error)")
            }
        }
    }

    /// Handle the results of an incremental update - parse changed files and manage versions
    private func handleIncrementalUpdateResults(_ toReparse: [LiveSet], project: Project, db: ProjectDatabase) {
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

        // Auto-save versions of changed main LiveSets (if enabled)
        if let vc = versionControls[project.path] {
            for liveSet in toReparse where liveSet.category == .main && liveSet.autoVersionEnabled {
                do {
                    try vc.commitLiveSet(at: liveSet.path, db: db)
                } catch {
                    print("VersionControl: Failed to save version of \(liveSet.name): \(error)")
                }
            }
        }
    }

    /// Extract a group as a subproject (uses bookmark for folder access)
    func extractSubproject(from liveSetPath: String, groupId: Int, groupName: String, sourceLiveSetName: String, to outputPath: String, projectPath: String, completion: @escaping (String?) -> Void) {
//        Task.detached { [weak self] in
//            guard let self = self else { return }
//            await MainActor.run { [self] in
//                self.accessFile(at: projectPath) { folderUrl in
//                    let extractor = AlsExtractor()
//                    let result = extractor.extractGroup(from: liveSetPath, groupId: groupId, to: outputPath)
//
//                    if result.success, let outputPath = result.outputPath {
//                        // Save metadata JSON file
//                        let baseName = URL(fileURLWithPath: outputPath).deletingPathExtension().lastPathComponent
//                        let metadataFileName = "\(baseName)-meta.json"
//                        let metadataUrl = folderUrl.appendingPathComponent(metadataFileName)
//
//                        let metadata: [String: Any] = [
//                            "sourceLiveSetName": sourceLiveSetName,
//                            "sourceGroupId": groupId,
//                            "sourceGroupName": groupName,
//                            "extractedAt": ISO8601DateFormatter().string(from: Date())
//                        ]
//
//                        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
//                            try? jsonData.write(to: metadataUrl)
//                            print("Saved metadata: \(metadataFileName)")
//                        }
//
//                        completion(outputPath)
//                    } else {
//                        print("Extraction failed: \(result.error ?? "unknown error")")
//                        completion(nil)
//                    }
//                }
//            }
//        }
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

    /// Create a version of a LiveSet by copying it with a timestamp
    func createVersion(of liveSet: LiveSet, comment: String? = nil) {
        guard let projectPath = liveSet.projectPath else { return }

        BookmarkManager.shared.accessFile(at: projectPath) { folderUrl in
            let fileManager = FileManager.default
            let sourceUrl = URL(fileURLWithPath: liveSet.path)

            // Generate timestamp: YYYY-MM-DDTHH-MM-SSZ
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let timestamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")

            // Create version filename: .version-{liveSetName}-{timestamp}.als
            let versionBaseName = ".version-\(liveSet.name)-\(timestamp)"
            let versionFileName = "\(versionBaseName).als"
            let destinationUrl = folderUrl.appendingPathComponent(versionFileName)

            do {
                try fileManager.copyItem(at: sourceUrl, to: destinationUrl)
                print("Created version: \(versionFileName)")

                // Save comment file if provided
                if let comment = comment, !comment.isEmpty {
                    let commentFileName = "\(versionBaseName)-comment.txt"
                    let commentUrl = folderUrl.appendingPathComponent(commentFileName)
                    try comment.write(to: commentUrl, atomically: true, encoding: .utf8)
                    print("Created comment file: \(commentFileName)")
                }

                // Rescan project to show new version
                self.rescanProject(projectPath: projectPath)
            } catch {
                print("Failed to create version: \(error.localizedDescription)")
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

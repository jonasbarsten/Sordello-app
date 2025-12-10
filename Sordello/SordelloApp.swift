//
//  SordelloApp.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GRDB

@main
struct SordelloApp: App {

    init() {
        // Per-project databases are created when projects are opened
        // No global app database initialization needed
    }

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project...") {
                    ProjectManager.shared.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("GRDB Test Windows") {
                    openWindow(id: "grdb-test")
                    openWindow(id: "grdb-observer")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        // Test window for GRDB proof of concept
        WindowGroup("GRDB Test", id: "grdb-test") {
            GRDBTestView()
        }
        .defaultSize(width: 500, height: 600)

        // Observer window - proves reactive updates work across windows
        WindowGroup("GRDB Observer", id: "grdb-observer") {
            GRDBObserverWindow()
        }
        .defaultSize(width: 400, height: 500)
    }
}

/// Manages project opening and file access
/// Uses per-project GRDB databases for persistence
@Observable
final class ProjectManager {
    static let shared = ProjectManager()

    /// Store security-scoped bookmarks for file access
    private var bookmarks: [String: Data] = [:]

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
            guard isValidAbletonProject(at: url) else {
                showInvalidProjectAlert(for: url)
                return
            }

            // Create security-scoped bookmark for the directory (gives us write access)
            saveBookmark(for: url)
            loadProject(at: url)
        }
    }

    /// Check if a folder contains at least one .als file
    private func isValidAbletonProject(at url: URL) -> Bool {
        let fileManager = FileManager.default

        if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            return contents.contains { $0.pathExtension.lowercased() == "als" }
        }

        return false
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

    /// Save a security-scoped bookmark for a URL
    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarks[url.path] = bookmark
            print("Saved bookmark for: \(url.path)")
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }

    /// Access a file using its security-scoped bookmark
    func accessFile(at path: String, action: (URL) -> Void) {
        guard let bookmark = bookmarks[path] else {
            print("No bookmark found for: \(path)")
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, need to recreate
                saveBookmark(for: url)
            }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to start accessing security-scoped resource")
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            action(url)
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
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
                try scanAndSaveLiveSets(in: folderUrl, for: project, db: projectDb)
            } else {
                // Existing data - do incremental update to preserve parsed data
                print("Existing project database with \(existingLiveSets.count) LiveSets, doing incremental update...")
                try incrementalUpdate(in: folderUrl, for: project, db: projectDb)
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

    /// Scan folder and save LiveSets to project database
    private func scanAndSaveLiveSets(in folderUrl: URL, for project: Project, db: ProjectDatabase) throws {
        let fileManager = FileManager.default

        // Delete existing LiveSets for this project
        try db.deleteAllLiveSets()

        var mainLiveSetPaths: [String: LiveSet] = [:]

        // Scan root folder for .als files
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                if fileName.hasPrefix(".subproject-") {
                    var liveSet = LiveSet(path: fileUrl.path, category: .subproject)
                    liveSet.projectPath = project.path
                    loadSubprojectMetadata(for: &liveSet, folderUrl: folderUrl)
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    try db.insertLiveSet(liveSet)

                } else if fileName.hasPrefix(".version-") {
                    // Version files are handled after main LiveSets
                    continue

                } else {
                    var liveSet = LiveSet(path: fileUrl.path, category: .main)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    try db.insertLiveSet(liveSet)
                    mainLiveSetPaths[liveSet.name] = liveSet
                }
            }
        }

        // Scan for version files and link them to parents
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                if fileName.hasPrefix(".version-"),
                   let parentName = extractParentName(from: fileName),
                   let parentLiveSet = mainLiveSetPaths[parentName] {
                    var liveSet = LiveSet(path: fileUrl.path, category: .version)
                    liveSet.projectPath = project.path
                    liveSet.parentLiveSetPath = parentLiveSet.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    try db.insertLiveSet(liveSet)
                }
            }
        }

        // Scan Backup folder
        let backupUrl = folderUrl.appendingPathComponent("Backup")
        if let backupContents = try? fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: nil) {
            for fileUrl in backupContents where fileUrl.pathExtension.lowercased() == "als" {
                var liveSet = LiveSet(path: fileUrl.path, category: .backup)
                liveSet.projectPath = project.path
                liveSet.comment = loadComment(for: fileUrl)
                liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                try db.insertLiveSet(liveSet)
            }
        }

        // Update project timestamp
        var updatedProject = project
        updatedProject.lastUpdated = Date()
        try db.updateProject(updatedProject)

        let liveSets = try db.fetchAllLiveSets()
        print("Saved project with \(liveSets.count) LiveSets to project database")

        // Start background parsing
        let liveSetPaths = liveSets.map { $0.path }
        parseAllLiveSetsInBackground(liveSetPaths: liveSetPaths, projectPath: project.path)
    }

    /// Parse all LiveSets in background
    private func parseAllLiveSetsInBackground(liveSetPaths: [String], projectPath: String) {
        guard let bookmarkData = bookmarks[projectPath],
              let projectDb = projectDatabases[projectPath] else {
            print("No bookmark or database found for project: \(projectPath)")
            return
        }

        print("Starting parallel parsing of \(liveSetPaths.count) LiveSets...")

        Task {
            do {
                try await parseAllLiveSetsInBackgroundImpl(
                    liveSetPaths: liveSetPaths,
                    projectPath: projectPath,
                    bookmarkData: bookmarkData,
                    projectDb: projectDb
                )
            } catch {
                print("Background parsing failed: \(error)")
            }
        }
    }

    /// Background parsing implementation
    @concurrent
    private func parseAllLiveSetsInBackgroundImpl(
        liveSetPaths: [String],
        projectPath: String,
        bookmarkData: Data,
        projectDb: ProjectDatabase
    ) async throws {
        let startTime = Date()

        // Resolve bookmark for security-scoped access
        var isStale = false
        guard let folderUrl = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("Failed to resolve bookmark for parsing")
            return
        }

        guard folderUrl.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        defer { folderUrl.stopAccessingSecurityScopedResource() }

        // Parse and save each file
        var completedCount = 0
        let parser = AlsParser()

        for path in liveSetPaths {
            let result = await parser.parse(atPath: path)
            completedCount += 1

            guard result.success else {
                print("[\(completedCount)/\(liveSetPaths.count)] Failed: \(URL(fileURLWithPath: path).lastPathComponent)")
                continue
            }

            // Get existing LiveSet from database
            guard var liveSet = try projectDb.fetchLiveSet(path: result.path) else { continue }
            guard !liveSet.isParsed else { continue }

            // Update LiveSet with parsed data
            liveSet.liveVersion = result.liveVersion ?? "Unknown"
            liveSet.isParsed = true
            liveSet.lastUpdated = Date()

            // Create Track objects
            var tracks: [Track] = []
            for parsedTrack in result.tracks {
                var track = Track(
                    trackId: parsedTrack.trackId,
                    name: parsedTrack.name,
                    type: parsedTrack.type,
                    parentGroupId: parsedTrack.parentGroupId
                )
                track.liveSetPath = liveSet.path
                track.sortIndex = parsedTrack.sortIndex
                track.color = parsedTrack.color
                track.isFrozen = parsedTrack.isFrozen
                track.trackDelay = parsedTrack.trackDelay
                track.isDelayInSamples = parsedTrack.isDelayInSamples
                track.audioInput = parsedTrack.audioInput
                track.audioOutput = parsedTrack.audioOutput
                track.midiInput = parsedTrack.midiInput
                track.midiOutput = parsedTrack.midiOutput
                tracks.append(track)
            }

            // Save to database (GRDB is thread-safe)
            try projectDb.saveLiveSetWithTracks(liveSet, tracks: tracks)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("Parsed \(completedCount)/\(liveSetPaths.count) files in \(elapsed.formatted(.number.precision(.fractionLength(1))))s")

        // Link tracks to subprojects
        let mainLiveSets = try projectDb.fetchMainLiveSets()
        await MainActor.run {
            for liveSet in mainLiveSets {
                self.linkTracksToSubprojects(liveSet: liveSet, projectPath: projectPath)
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)
        print("Finished background parsing in \(totalTime.formatted(.number.precision(.fractionLength(1))))s")
    }

    /// Internal parsing method
    private func parseLiveSetInternal(_ liveSet: LiveSet) {
        let alsUrl = URL(fileURLWithPath: liveSet.path)

        let parser = AlsParser()
        let result = parser.parse(at: alsUrl)
        guard result.success else {
            print("Failed to parse Live Set \(liveSet.name): \(result.errorMessage ?? "unknown error")")
            return
        }

        // Parse tracks
        let parsedTracks = result.tracks

        var updatedLiveSet = liveSet
        updatedLiveSet.liveVersion = result.liveVersion ?? "Unknown"
        updatedLiveSet.isParsed = true
        updatedLiveSet.lastUpdated = Date()

        var tracks: [Track] = []
        for parsedTrack in parsedTracks {
            var track = Track(
                trackId: parsedTrack.trackId,
                name: parsedTrack.name,
                type: parsedTrack.type,
                parentGroupId: parsedTrack.parentGroupId
            )
            track.liveSetPath = liveSet.path
            track.sortIndex = parsedTrack.sortIndex
            track.color = parsedTrack.color
            track.isFrozen = parsedTrack.isFrozen
            track.trackDelay = parsedTrack.trackDelay
            track.isDelayInSamples = parsedTrack.isDelayInSamples

            if let routing = parsedTrack.audioInput {
                track.audioInput = Track.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
            }
            if let routing = parsedTrack.audioOutput {
                track.audioOutput = Track.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
            }
            if let routing = parsedTrack.midiInput {
                track.midiInput = Track.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
            }
            if let routing = parsedTrack.midiOutput {
                track.midiOutput = Track.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
            }

            tracks.append(track)
        }

        guard let projectPath = liveSet.projectPath,
              let projectDb = projectDatabases[projectPath] else {
            print("Failed to save parsed LiveSet: no project database found")
            return
        }

        do {
            try projectDb.saveLiveSetWithTracks(updatedLiveSet, tracks: tracks)
            print("Parsed \(tracks.count) tracks from \(liveSet.name) (Live \(updatedLiveSet.liveVersion))")
        } catch {
            print("Failed to save parsed LiveSet: \(error)")
        }
    }

    /// Load subproject metadata from companion JSON file
    private func loadSubprojectMetadata(for liveSet: inout LiveSet, folderUrl: URL) {
        let baseName = URL(fileURLWithPath: liveSet.path).deletingPathExtension().lastPathComponent
        let metadataFileName = "\(baseName)-meta.json"
        let metadataUrl = folderUrl.appendingPathComponent(metadataFileName)

        guard let metadataData = try? Data(contentsOf: metadataUrl) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let metadata = try? decoder.decode(SubprojectMetadataDTO.self, from: metadataData) {
            liveSet.sourceLiveSetName = metadata.sourceLiveSetName
            liveSet.sourceGroupId = metadata.sourceGroupId
            liveSet.sourceGroupName = metadata.sourceGroupName
            liveSet.extractedAt = metadata.extractedAt
        }
    }

    /// DTO for reading subproject metadata JSON
    private struct SubprojectMetadataDTO: Codable {
        let sourceLiveSetName: String
        let sourceGroupId: Int
        let sourceGroupName: String
        let extractedAt: Date
    }

    /// Rename any _subproject files to .subproject (Live substitutes . with _ on Save As)
//    private func fixSubprojectFilenames(in folderUrl: URL) {
//        let fileManager = FileManager.default
//
//        guard let contents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) else {
//            return
//        }
//
//        for fileUrl in contents {
//            let fileName = fileUrl.lastPathComponent
//
//            // Check for _subproject .als files
//            if fileName.hasPrefix("_subproject-") && fileName.hasSuffix(".als") {
//                let newFileName = "." + fileName.dropFirst() // Replace _ with .
//                let newUrl = folderUrl.appendingPathComponent(newFileName)
//
//                do {
//                    // Remove existing file if it exists (overwrite)
//                    if fileManager.fileExists(atPath: newUrl.path) {
//                        try fileManager.removeItem(at: newUrl)
//                        print("Removed existing: \(newFileName)")
//                    }
//
//                    try fileManager.moveItem(at: fileUrl, to: newUrl)
//                    print("Renamed: \(fileName) -> \(newFileName)")
//
//                    // Also rename the corresponding -meta.json file if it exists
//                    let oldMetaName = fileName.replacingOccurrences(of: ".als", with: "-meta.json")
//                    let newMetaName = newFileName.replacingOccurrences(of: ".als", with: "-meta.json")
//                    let oldMetaUrl = folderUrl.appendingPathComponent(oldMetaName)
//                    let newMetaUrl = folderUrl.appendingPathComponent(newMetaName)
//
//                    if fileManager.fileExists(atPath: oldMetaUrl.path) {
//                        if fileManager.fileExists(atPath: newMetaUrl.path) {
//                            try fileManager.removeItem(at: newMetaUrl)
//                        }
//                        try fileManager.moveItem(at: oldMetaUrl, to: newMetaUrl)
//                        print("Renamed: \(oldMetaName) -> \(newMetaName)")
//                    }
//                } catch {
//                    print("Failed to rename \(fileName): \(error.localizedDescription)")
//                }
//            }
//        }
//    }

    /// Load comment from companion -comment.txt file
    private func loadComment(for alsUrl: URL) -> String? {
        let baseName = alsUrl.deletingPathExtension().lastPathComponent
        let commentUrl = alsUrl.deletingLastPathComponent().appendingPathComponent("\(baseName)-comment.txt")
        if let commentData = try? Data(contentsOf: commentUrl),
           let comment = String(data: commentData, encoding: .utf8) {
            return comment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Extract parent LiveSet name from version filename
    /// Format: .version-{parentName}-{timestamp}.als
    private func extractParentName(from fileName: String) -> String? {
        var name = fileName
        if name.hasPrefix(".version-") {
            name = String(name.dropFirst(".version-".count))
        }
        if name.hasSuffix(".als") {
            name = String(name.dropLast(".als".count))
        }

        if let range = name.range(of: #"-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z?$"#, options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }

        return nil
    }

    /// Parse a specific LiveSet
    func parseLiveSet(_ liveSet: LiveSet) {
        guard let projectPath = liveSet.projectPath else { return }

        accessFile(at: projectPath) { _ in
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

    /// Get file modification date
    private func getFileModificationDate(for fileUrl: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.modificationDate] as? Date
    }

    /// Reload a project folder after changes
    private func reloadProject(folderPath: String) {
        accessFile(at: folderPath) { folderUrl in
            // Fix filenames first
//            self.fixSubprojectFilenames(in: folderUrl)

            do {
                guard let projectDb = self.projectDatabases[folderPath],
                      let project = try projectDb.fetchProject() else { return }
                try self.incrementalUpdate(in: folderUrl, for: project, db: projectDb)
            } catch {
                print("Failed to reload project: \(error)")
            }
        }
    }

    /// Incrementally update LiveSets - only re-parse changed files
    private func incrementalUpdate(in folderUrl: URL, for project: Project, db: ProjectDatabase) throws {
        let fileManager = FileManager.default

        // Build map of existing LiveSets by path
        let existingLiveSets = try db.fetchAllLiveSets()
        var existingByPath: [String: LiveSet] = [:]
        for liveSet in existingLiveSets {
            existingByPath[liveSet.path] = liveSet
        }

        // Collect current files on disk
        var currentFilePaths: Set<String> = []
        var changedLiveSets: [LiveSet] = []
        var newLiveSets: [LiveSet] = []

        // Scan root folder
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent
                let filePath = fileUrl.path
                currentFilePaths.insert(filePath)

                let currentModDate = getFileModificationDate(for: fileUrl)

                if var existing = existingByPath[filePath] {
                    // Check if file was modified (1 second tolerance for float precision)
                    if let storedDate = existing.fileModificationDate,
                       let currentDate = currentModDate,
                       currentDate.timeIntervalSince(storedDate) > 1.0 {
                        existing.fileModificationDate = currentDate
                        try db.updateLiveSet(existing)
                        changedLiveSets.append(existing)
                        print("File changed: \(existing.name)")
                    }
                } else {
                    // New file
                    let category: LiveSetCategory
                    if fileName.hasPrefix(".subproject-") {
                        category = .subproject
                    } else if fileName.hasPrefix(".version-") {
                        category = .version
                    } else {
                        category = .main
                    }

                    var liveSet = LiveSet(path: filePath, category: category)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate

                    if category == .subproject {
                        loadSubprojectMetadata(for: &liveSet, folderUrl: folderUrl)
                    } else if category == .version {
                        // Link version to its parent LiveSet
                        if let parentName = extractParentName(from: fileName) {
                            let mainLiveSets = try db.fetchMainLiveSets()
                            if let parent = mainLiveSets.first(where: { $0.name == parentName }) {
                                liveSet.parentLiveSetPath = parent.path
                            }
                        }
                    }

                    try db.insertLiveSet(liveSet)
                    newLiveSets.append(liveSet)
                    print("New file: \(liveSet.name)")
                }
            }
        }

        // Scan Backup folder
        let backupUrl = folderUrl.appendingPathComponent("Backup")
        if let backupContents = try? fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for fileUrl in backupContents where fileUrl.pathExtension.lowercased() == "als" {
                let filePath = fileUrl.path
                currentFilePaths.insert(filePath)

                let currentModDate = getFileModificationDate(for: fileUrl)

                if var existing = existingByPath[filePath] {
                    // Check if file was modified (1 second tolerance for float precision)
                    if let storedDate = existing.fileModificationDate,
                       let currentDate = currentModDate,
                       currentDate.timeIntervalSince(storedDate) > 1.0 {
                        existing.fileModificationDate = currentDate
                        try db.updateLiveSet(existing)
                        changedLiveSets.append(existing)
                        print("File changed: \(existing.name)")
                    }
                } else {
                    var liveSet = LiveSet(path: filePath, category: .backup)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate
                    try db.insertLiveSet(liveSet)
                    newLiveSets.append(liveSet)
                    print("New backup file: \(liveSet.name)")
                }
            }
        }

        // Remove deleted files (exclude version LiveSets - they're in .sordello/versions/)
        for (path, liveSet) in existingByPath {
            if !currentFilePaths.contains(path) && liveSet.category != .version {
                print("Deleted file: \(liveSet.name)")
                try db.deleteLiveSet(path: path)
            }
        }

        // Parse only changed and new LiveSets
        let toReparse = changedLiveSets + newLiveSets
        if !toReparse.isEmpty {
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
        } else {
            print("No files changed")
        }
    }

    /// Write a file to a project folder (uses stored bookmark for access)
    func writeToProjectFolder(projectPath: String, fileName: String, data: Data) -> URL? {
        var resultUrl: URL?
        accessFile(at: projectPath) { folderUrl in
            let fileUrl = folderUrl.appendingPathComponent(fileName)
            do {
                try data.write(to: fileUrl)
                resultUrl = fileUrl
                print("Wrote file: \(fileUrl.path)")
            } catch {
                print("Failed to write file: \(error)")
            }
        }
        return resultUrl
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
        accessFile(at: projectPath) { folderUrl in
            do {
                guard let projectDb = self.projectDatabases[projectPath],
                      let project = try projectDb.fetchProject() else { return }
                try self.scanAndSaveLiveSets(in: folderUrl, for: project, db: projectDb)
            } catch {
                print("Failed to rescan project: \(error)")
            }
        }
    }

    /// Create a version of a LiveSet by copying it with a timestamp
    func createVersion(of liveSet: LiveSet, comment: String? = nil) {
        guard let projectPath = liveSet.projectPath else { return }

        accessFile(at: projectPath) { folderUrl in
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

        accessFile(at: projectPath) { _ in
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

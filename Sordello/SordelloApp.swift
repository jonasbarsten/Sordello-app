//
//  SordelloApp.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

@main
struct SordelloApp: App {
    let modelContainer: ModelContainer

    init() {
        // Delete existing database files BEFORE creating container (fresh start each launch)
        Self.deleteSwiftDataFiles()

        do {
            let schema = Schema([
                SDProject.self,
                SDLiveSet.self,
                SDTrack.self,
                SDConnectedDevice.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("Created fresh ModelContainer")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Delete SwiftData database files before container creation
    private static func deleteSwiftDataFiles() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        // SwiftData stores files with .store extension
        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        for fileName in storeFiles {
            let fileUrl = appSupport.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileUrl.path) {
                do {
                    try fileManager.removeItem(at: fileUrl)
                } catch {
                    print("Failed to delete \(fileName): \(error)")
                }
            }
        }
        print("Cleared SwiftData on launch")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    OSCServer.shared.start()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project...") {
                    ProjectManager.shared.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

/// Manages project opening and file access
/// Now writes to SwiftData instead of in-memory state
@MainActor
final class ProjectManager {
    static let shared = ProjectManager()

    /// Store security-scoped bookmarks for file access
    private var bookmarks: [String: Data] = [:]

    /// Reference to the model context (set from views)
    var modelContext: ModelContext?

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

    /// Load a project folder and scan for .als files - writes to SwiftData
    func loadProject(at folderUrl: URL) {
        guard let context = modelContext else {
            print("No ModelContext available")
            return
        }

        // Start accessing for initial load
        let accessing = folderUrl.startAccessingSecurityScopedResource()

        // Fix any _subproject files first
        fixSubprojectFilenames(in: folderUrl)

        // Get or create the project in SwiftData
        let project = getOrCreateProject(path: folderUrl.path, context: context)

        // Scan and save LiveSets
        scanAndSaveLiveSets(in: folderUrl, for: project, context: context)

        // Select the project in UI state
        UIState.shared.selectedProjectPath = project.path

        // Auto-select the first main LiveSet
        let mainPredicate = SDPredicates.mainLiveSets(forProjectPath: project.path)
        let descriptor = FetchDescriptor<SDLiveSet>(predicate: mainPredicate, sortBy: [SDSortDescriptors.liveSetsByName()])
        if let firstMain = try? context.fetch(descriptor).first {
            UIState.shared.selectedLiveSetPath = firstMain.path
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

    /// Get or create a project in SwiftData
    private func getOrCreateProject(path: String, context: ModelContext) -> SDProject {
        let predicate = #Predicate<SDProject> { $0.path == path }
        let descriptor = FetchDescriptor<SDProject>(predicate: predicate)

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let project = SDProject(path: path)
        context.insert(project)
        return project
    }

    /// Scan folder and save LiveSets to SwiftData
    private func scanAndSaveLiveSets(in folderUrl: URL, for project: SDProject, context: ModelContext) {
        let fileManager = FileManager.default

        // Delete existing LiveSets and tracks for this project
        let existingLiveSets = project.liveSets
        for liveSet in existingLiveSets {
            context.delete(liveSet)
        }

        var mainLiveSetPaths: [String: SDLiveSet] = [:]

        // Scan root folder for .als files
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                if fileName.hasPrefix(".subproject-") {
                    let liveSet = SDLiveSet(path: fileUrl.path, category: .subproject)
                    loadSubprojectMetadata(for: liveSet, folderUrl: folderUrl)
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    liveSet.project = project
                    context.insert(liveSet)

                } else if fileName.hasPrefix(".version-") {
                    // Version files are handled after main LiveSets
                    continue

                } else {
                    let liveSet = SDLiveSet(path: fileUrl.path, category: .main)
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    liveSet.project = project
                    context.insert(liveSet)
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
                    let liveSet = SDLiveSet(path: fileUrl.path, category: .version)
                    liveSet.parentLiveSetPath = parentLiveSet.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                    liveSet.project = project
                    context.insert(liveSet)
                }
            }
        }

        // Scan Backup folder
        let backupUrl = folderUrl.appendingPathComponent("Backup")
        if let backupContents = try? fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: nil) {
            for fileUrl in backupContents where fileUrl.pathExtension.lowercased() == "als" {
                let liveSet = SDLiveSet(path: fileUrl.path, category: .backup)
                liveSet.comment = loadComment(for: fileUrl)
                liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                liveSet.project = project
                context.insert(liveSet)
            }
        }

        project.lastUpdated = Date()

        do {
            try context.save()
            print("Saved project with \(project.liveSets.count) LiveSets to SwiftData")
        } catch {
            print("Failed to save to SwiftData: \(error)")
        }

        // Start background parsing (we're still in security-scoped access)
        let liveSetPaths = project.liveSets.map { $0.path }
        let projectPath = project.path
        parseAllLiveSetsInBackground(liveSetPaths: liveSetPaths, projectPath: projectPath)
    }

    /// Parse all LiveSets in background using parallel TaskGroup
    private func parseAllLiveSetsInBackground(liveSetPaths: [String], projectPath: String) {
        guard let context = modelContext else { return }

        // Get bookmark data on MainActor BEFORE entering background task
        guard let bookmarkData = bookmarks[projectPath] else {
            print("No bookmark found for project: \(projectPath)")
            return
        }

        print("Starting parallel parsing of \(liveSetPaths.count) LiveSets...")
        let startTime = Date()

        // Launch a Task (inherits MainActor but immediately goes to background via @concurrent)
        Task {
            // Resolve bookmark ONCE for all files
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

            // Parse files in parallel, write to SwiftData in batches
            var completedCount = 0
            var pendingSaveCount = 0
            let batchSize = 20  // Save every 20 files to reduce UI updates

            await withTaskGroup(of: AlsParseResult.self) { group in
                for path in liveSetPaths {
                    group.addTask {
                        await parseAlsFileInBackground(at: path)
                    }
                }

                // Process each result as it completes
                for await result in group {
                    completedCount += 1

                    // Skip failed parses
                    guard result.errorMessage == nil else {
                        print("[\(completedCount)/\(liveSetPaths.count)] Failed: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                        continue
                    }

                    // Write to SwiftData (but don't save yet)
                    await MainActor.run {
                        let pathToFind = result.path
                        let predicate = #Predicate<SDLiveSet> { $0.path == pathToFind }
                        let descriptor = FetchDescriptor<SDLiveSet>(predicate: predicate)

                        guard let liveSet = try? context.fetch(descriptor).first else { return }
                        guard !liveSet.isParsed else { return }

                        // Delete existing tracks
                        for track in liveSet.tracks {
                            context.delete(track)
                        }

                        // Create SDTrack objects from parsed data
                        liveSet.liveVersion = result.liveVersion ?? "Unknown"

                        for parsedTrack in result.tracks {
                            let track = SDTrack(
                                trackId: parsedTrack.id,
                                name: parsedTrack.name,
                                type: SDTrackType(rawValue: parsedTrack.type.rawValue) ?? .audio,
                                parentGroupId: parsedTrack.parentGroupId
                            )
                            track.sortIndex = parsedTrack.sortIndex
                            track.color = parsedTrack.color
                            track.isFrozen = parsedTrack.isFrozen
                            track.trackDelay = parsedTrack.trackDelay
                            track.isDelayInSamples = parsedTrack.isDelayInSamples

                            if let routing = parsedTrack.audioInput {
                                track.audioInput = SDTrack.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
                            }
                            if let routing = parsedTrack.audioOutput {
                                track.audioOutput = SDTrack.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
                            }
                            if let routing = parsedTrack.midiInput {
                                track.midiInput = SDTrack.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
                            }
                            if let routing = parsedTrack.midiOutput {
                                track.midiOutput = SDTrack.RoutingInfo(target: routing.target, displayName: routing.displayName, channel: routing.channel)
                            }

                            track.liveSet = liveSet
                            context.insert(track)
                        }

                        liveSet.isParsed = true
                        liveSet.lastUpdated = Date()
                        pendingSaveCount += 1

                        // Batch save: only save every N files to reduce UI lag
                        if pendingSaveCount >= batchSize {
                            try? context.save()
                            pendingSaveCount = 0
                        }
                    }
                }

                // Final save for any remaining unsaved items
                await MainActor.run {
                    if pendingSaveCount > 0 {
                        try? context.save()
                    }
                }
            }

            print("Parsed \(completedCount)/\(liveSetPaths.count) files in \(Date().timeIntervalSince(startTime).formatted(.number.precision(.fractionLength(1))))s")

            // Link tracks to subprojects (quick operation at the end)
            await MainActor.run {
                ProjectManager.shared.accessFile(at: projectPath) { _ in
                    let projectPredicate = #Predicate<SDProject> { $0.path == projectPath }
                    let projectDescriptor = FetchDescriptor<SDProject>(predicate: projectPredicate)

                    guard let project = try? context.fetch(projectDescriptor).first else { return }

                    for liveSet in project.liveSets where liveSet.category == .main {
                        ProjectManager.shared.linkTracksToSubprojects(liveSet: liveSet, context: context)
                    }

                    do {
                        try context.save()
                        let totalTime = Date().timeIntervalSince(startTime)
                        print("Finished background parsing all LiveSets in \(totalTime.formatted(.number.precision(.fractionLength(1))))s")
                    } catch {
                        print("Failed to save after linking subprojects: \(error)")
                    }
                }
            }
        }
    }

    /// Internal parsing method - used when already in security-scoped access
    private func parseLiveSetInternal(_ liveSet: SDLiveSet, context: ModelContext) {
        let alsUrl = URL(fileURLWithPath: liveSet.path)

        let parser = AlsParser()
        guard parser.loadFile(at: alsUrl) else {
            print("Failed to parse Live Set \(liveSet.name): \(parser.errorMessage ?? "unknown error")")
            return
        }

        // Delete existing tracks for this LiveSet
        for track in liveSet.tracks {
            context.delete(track)
        }

        // Parse and save tracks
        let parsedTracks = parser.getTracks()
        liveSet.liveVersion = parser.liveVersion ?? "Unknown"

        for parsedTrack in parsedTracks {
            let track = SDTrack(
                trackId: parsedTrack.id,
                name: parsedTrack.name,
                type: SDTrackType(rawValue: parsedTrack.type.rawValue) ?? .audio,
                parentGroupId: parsedTrack.parentGroupId
            )
            track.sortIndex = parsedTrack.sortIndex
            track.color = parsedTrack.color
            track.isFrozen = parsedTrack.isFrozen
            track.trackDelay = parsedTrack.trackDelay
            track.isDelayInSamples = parsedTrack.isDelayInSamples

            // Convert routing info
            if let routing = parsedTrack.audioInput {
                track.audioInput = SDTrack.RoutingInfo(
                    target: routing.target,
                    displayName: routing.displayName,
                    channel: routing.channel
                )
            }
            if let routing = parsedTrack.audioOutput {
                track.audioOutput = SDTrack.RoutingInfo(
                    target: routing.target,
                    displayName: routing.displayName,
                    channel: routing.channel
                )
            }
            if let routing = parsedTrack.midiInput {
                track.midiInput = SDTrack.RoutingInfo(
                    target: routing.target,
                    displayName: routing.displayName,
                    channel: routing.channel
                )
            }
            if let routing = parsedTrack.midiOutput {
                track.midiOutput = SDTrack.RoutingInfo(
                    target: routing.target,
                    displayName: routing.displayName,
                    channel: routing.channel
                )
            }

            track.liveSet = liveSet
            context.insert(track)
        }

        liveSet.isParsed = true
        liveSet.lastUpdated = Date()
        print("Parsed \(parsedTracks.count) tracks from \(liveSet.name) (Live \(liveSet.liveVersion))")
    }

    /// Load subproject metadata from companion JSON file
    private func loadSubprojectMetadata(for liveSet: SDLiveSet, folderUrl: URL) {
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
    private func fixSubprojectFilenames(in folderUrl: URL) {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) else {
            return
        }

        for fileUrl in contents {
            let fileName = fileUrl.lastPathComponent

            // Check for _subproject .als files
            if fileName.hasPrefix("_subproject-") && fileName.hasSuffix(".als") {
                let newFileName = "." + fileName.dropFirst() // Replace _ with .
                let newUrl = folderUrl.appendingPathComponent(newFileName)

                do {
                    // Remove existing file if it exists (overwrite)
                    if fileManager.fileExists(atPath: newUrl.path) {
                        try fileManager.removeItem(at: newUrl)
                        print("Removed existing: \(newFileName)")
                    }

                    try fileManager.moveItem(at: fileUrl, to: newUrl)
                    print("Renamed: \(fileName) -> \(newFileName)")

                    // Also rename the corresponding -meta.json file if it exists
                    let oldMetaName = fileName.replacingOccurrences(of: ".als", with: "-meta.json")
                    let newMetaName = newFileName.replacingOccurrences(of: ".als", with: "-meta.json")
                    let oldMetaUrl = folderUrl.appendingPathComponent(oldMetaName)
                    let newMetaUrl = folderUrl.appendingPathComponent(newMetaName)

                    if fileManager.fileExists(atPath: oldMetaUrl.path) {
                        if fileManager.fileExists(atPath: newMetaUrl.path) {
                            try fileManager.removeItem(at: newMetaUrl)
                        }
                        try fileManager.moveItem(at: oldMetaUrl, to: newMetaUrl)
                        print("Renamed: \(oldMetaName) -> \(newMetaName)")
                    }
                } catch {
                    print("Failed to rename \(fileName): \(error.localizedDescription)")
                }
            }
        }
    }

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

    /// Parse a specific LiveSet and save tracks to SwiftData
    func parseLiveSet(_ liveSet: SDLiveSet) {
        guard let context = modelContext,
              let projectPath = liveSet.project?.path else { return }

        accessFile(at: projectPath) { _ in
            parseLiveSetInternal(liveSet, context: context)
            linkTracksToSubprojects(liveSet: liveSet, context: context)

            do {
                try context.save()
            } catch {
                print("Failed to save tracks: \(error)")
            }
        }
    }

    /// Link group tracks to their extracted subprojects
    private func linkTracksToSubprojects(liveSet: SDLiveSet, context: ModelContext) {
        guard let projectPath = liveSet.project?.path else { return }

        // Find subprojects for this LiveSet
        let subprojectPredicate = SDPredicates.subprojectLiveSets(forProjectPath: projectPath)
        let descriptor = FetchDescriptor<SDLiveSet>(predicate: subprojectPredicate)

        guard let subprojects = try? context.fetch(descriptor) else { return }

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
        for track in liveSet.tracks where track.isGroup {
            if let subprojectPath = subprojectsByGroupId[track.trackId] {
                track.subprojectPath = subprojectPath
                print("Linked group '\(track.name)' (ID: \(track.trackId)) to subproject")
            }
        }
    }

    /// Get file modification date
    private func getFileModificationDate(for fileUrl: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.modificationDate] as? Date
    }

    /// Reload a project folder after changes - only processes changed files
    private func reloadProject(folderPath: String) {
        guard let context = modelContext else { return }

        accessFile(at: folderPath) { folderUrl in
            // Fix filenames first
            self.fixSubprojectFilenames(in: folderUrl)

            // Find the project
            let predicate = #Predicate<SDProject> { $0.path == folderPath }
            let descriptor = FetchDescriptor<SDProject>(predicate: predicate)

            guard let project = try? context.fetch(descriptor).first else { return }

            // Incremental update: only process changed files
            self.incrementalUpdate(in: folderUrl, for: project, context: context)
        }
    }

    /// Incrementally update LiveSets - only re-parse changed files
    private func incrementalUpdate(in folderUrl: URL, for project: SDProject, context: ModelContext) {
        let fileManager = FileManager.default

        // Build map of existing LiveSets by path
        var existingByPath: [String: SDLiveSet] = [:]
        for liveSet in project.liveSets {
            existingByPath[liveSet.path] = liveSet
        }

        // Collect current files on disk
        var currentFilePaths: Set<String> = []
        var changedLiveSets: [SDLiveSet] = []
        var newLiveSets: [SDLiveSet] = []

        // Scan root folder
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent
                let filePath = fileUrl.path
                currentFilePaths.insert(filePath)

                let currentModDate = getFileModificationDate(for: fileUrl)

                if let existing = existingByPath[filePath] {
                    // Check if file was modified
                    if let storedDate = existing.fileModificationDate,
                       let currentDate = currentModDate,
                       currentDate > storedDate {
                        existing.fileModificationDate = currentDate
                        changedLiveSets.append(existing)
                        print("File changed: \(existing.name)")
                    }
                } else {
                    // New file
                    let category: SDLiveSetCategory
                    if fileName.hasPrefix(".subproject-") {
                        category = .subproject
                    } else if fileName.hasPrefix(".version-") {
                        category = .version
                    } else {
                        category = .main
                    }

                    let liveSet = SDLiveSet(path: filePath, category: category)
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate
                    liveSet.project = project
                    context.insert(liveSet)

                    if category == .subproject {
                        loadSubprojectMetadata(for: liveSet, folderUrl: folderUrl)
                    } else if category == .version {
                        // Link version to its parent LiveSet
                        if let parentName = extractParentName(from: fileName) {
                            // Find the parent LiveSet by matching the name
                            for existingLiveSet in project.liveSets where existingLiveSet.category == .main {
                                if existingLiveSet.name == parentName {
                                    liveSet.parentLiveSetPath = existingLiveSet.path
                                    break
                                }
                            }
                        }
                    }

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

                if let existing = existingByPath[filePath] {
                    if let storedDate = existing.fileModificationDate,
                       let currentDate = currentModDate,
                       currentDate > storedDate {
                        existing.fileModificationDate = currentDate
                        changedLiveSets.append(existing)
                        print("File changed: \(existing.name)")
                    }
                } else {
                    let liveSet = SDLiveSet(path: filePath, category: .backup)
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate
                    liveSet.project = project
                    context.insert(liveSet)
                    newLiveSets.append(liveSet)
                    print("New backup file: \(liveSet.name)")
                }
            }
        }

        // Remove deleted files
        for (path, liveSet) in existingByPath {
            if !currentFilePaths.contains(path) {
                print("Deleted file: \(liveSet.name)")
                context.delete(liveSet)
            }
        }

        // Parse only changed and new LiveSets
        let toReparse = changedLiveSets + newLiveSets
        if !toReparse.isEmpty {
            print("Re-parsing \(toReparse.count) LiveSet(s)...")
            for liveSet in toReparse {
                // Wrap in autoreleasepool to free memory after each file is parsed
                autoreleasepool {
                    parseLiveSetInternal(liveSet, context: context)
                }
            }

            // Re-link subprojects for main LiveSets that changed
            for liveSet in toReparse where liveSet.category == .main {
                linkTracksToSubprojects(liveSet: liveSet, context: context)
            }
        } else {
            print("No files changed")
        }

        do {
            try context.save()
        } catch {
            print("Failed to save incremental update: \(error)")
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
        Task.detached { [weak self] in
            await MainActor.run {
                self?.accessFile(at: projectPath) { folderUrl in
                    let extractor = AlsExtractor()
                    let result = extractor.extractGroup(from: liveSetPath, groupId: groupId, to: outputPath)

                    if result.success, let outputPath = result.outputPath {
                        // Save metadata JSON file
                        let baseName = URL(fileURLWithPath: outputPath).deletingPathExtension().lastPathComponent
                        let metadataFileName = "\(baseName)-meta.json"
                        let metadataUrl = folderUrl.appendingPathComponent(metadataFileName)

                        let metadata: [String: Any] = [
                            "sourceLiveSetName": sourceLiveSetName,
                            "sourceGroupId": groupId,
                            "sourceGroupName": groupName,
                            "extractedAt": ISO8601DateFormatter().string(from: Date())
                        ]

                        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
                            try? jsonData.write(to: metadataUrl)
                            print("Saved metadata: \(metadataFileName)")
                        }

                        completion(outputPath)
                    } else {
                        print("Extraction failed: \(result.error ?? "unknown error")")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Rescan a project folder to update the live sets list
    func rescanProject(projectPath: String) {
        guard let context = modelContext else { return }

        accessFile(at: projectPath) { folderUrl in
            let predicate = #Predicate<SDProject> { $0.path == projectPath }
            let descriptor = FetchDescriptor<SDProject>(predicate: predicate)

            guard let project = try? context.fetch(descriptor).first else { return }

            self.scanAndSaveLiveSets(in: folderUrl, for: project, context: context)
        }
    }

    /// Create a version of a LiveSet by copying it with a timestamp
    func createVersion(of liveSet: SDLiveSet, comment: String? = nil) {
        guard let projectPath = liveSet.project?.path else { return }

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
    func saveComment(for liveSet: SDLiveSet, comment: String) {
        guard let projectPath = liveSet.project?.path else { return }

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
                    liveSet.comment = nil
                } else {
                    // Write the comment to file
                    try trimmedComment.write(to: commentUrl, atomically: true, encoding: .utf8)
                    print("Saved comment: \(commentFileName)")
                    liveSet.comment = trimmedComment
                }

                if let context = self.modelContext {
                    try context.save()
                }
            } catch {
                print("Failed to save comment: \(error.localizedDescription)")
            }
        }
    }
}

//
//  SordelloApp.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct SordelloApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    OSCServer.shared.start()
                }
        }
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
@Observable
class ProjectManager {
    static let shared = ProjectManager()

    /// Store security-scoped bookmarks for file access
    private var bookmarks: [String: Data] = [:]
    /// Store bookmarks for directories (for write access)
    private var directoryBookmarks: [String: Data] = [:]

    init() {}

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

    /// Load a project folder and scan for .als files
    func loadProject(at folderUrl: URL) {
        // Start accessing for initial load
        let accessing = folderUrl.startAccessingSecurityScopedResource()

        // Scan for .als files in the folder
        let liveSets = scanForLiveSets(in: folderUrl)

        if liveSets.isEmpty {
            print("No .als files found in: \(folderUrl.path)")
            if accessing { folderUrl.stopAccessingSecurityScopedResource() }
            return
        }

        print("Found \(liveSets.count) Live Set(s) in project folder")

        // Create/update the project in app state
        let project = AppState.shared.getOrCreateProject(folderPath: folderUrl.path)
        project.liveSets = liveSets
        project.lastUpdated = Date()

        // Select the newly opened project
        AppState.shared.selectedProject = project

        // Auto-select the first main Live Set if available
        if let firstMain = project.mainLiveSets.first {
            AppState.shared.selectedLiveSet = firstMain
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
                        // Remove existing meta file if it exists
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

    /// Scan a folder for .als files and categorize them
    private func scanForLiveSets(in folderUrl: URL) -> [LiveSet] {
        // Fix any _subproject files first (Live substitutes . with _ on Save As)
        fixSubprojectFilenames(in: folderUrl)

        let fileManager = FileManager.default
        var liveSets: [LiveSet] = []
        var versionFiles: [(url: URL, parentName: String)] = []

        // Scan root folder for .als files
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                if fileName.hasPrefix(".subproject-") {
                    let subproject = LiveSet(path: fileUrl.path, category: .subproject)
                    // Load metadata from companion -meta.json file
                    let metadataFileName = SubprojectMetadata.metadataFileName(for: fileUrl.path)
                    let metadataUrl = folderUrl.appendingPathComponent(metadataFileName)
                    if let metadataData = try? Data(contentsOf: metadataUrl) {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        if let metadata = try? decoder.decode(SubprojectMetadata.self, from: metadataData) {
                            subproject.metadata = metadata
                        }
                    }
                    // Load comment
                    subproject.comment = loadComment(for: fileUrl)
                    liveSets.append(subproject)
                } else if fileName.hasPrefix(".version-") {
                    // Parse version file: .version-{parentName}-{timestamp}.als
                    if let parentName = extractParentName(from: fileName) {
                        versionFiles.append((url: fileUrl, parentName: parentName))
                    }
                } else {
                    let mainLiveSet = LiveSet(path: fileUrl.path, category: .main)
                    // Load comment
                    mainLiveSet.comment = loadComment(for: fileUrl)
                    liveSets.append(mainLiveSet)
                }
            }
        }

        // Scan Backup folder
        let backupUrl = folderUrl.appendingPathComponent("Backup")
        if let backupContents = try? fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: nil) {
            for fileUrl in backupContents where fileUrl.pathExtension.lowercased() == "als" {
                let backup = LiveSet(path: fileUrl.path, category: .backup)
                // Load comment (stored in Backup folder next to the .als file)
                backup.comment = loadComment(for: fileUrl)
                liveSets.append(backup)
            }
        }

        // Link version files to their parent LiveSets and load comments
        for (url, parentName) in versionFiles {
            let version = LiveSet(path: url.path, category: .version)

            // Load comment
            version.comment = loadComment(for: url)

            // Find parent by matching name
            if let parent = liveSets.first(where: { $0.category == .main && $0.name == parentName }) {
                parent.versions.append(version)
            }
        }

        // Sort versions by timestamp (newest first, based on filename)
        for liveSet in liveSets where liveSet.category == .main {
            liveSet.versions.sort { $0.name > $1.name }
        }

        return liveSets
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
        // Remove ".version-" prefix and ".als" extension
        var name = fileName
        if name.hasPrefix(".version-") {
            name = String(name.dropFirst(".version-".count))
        }
        if name.hasSuffix(".als") {
            name = String(name.dropLast(".als".count))
        }

        // Find the last hyphen followed by a timestamp pattern
        // Timestamp format: YYYY-MM-DDTHH-MM-SSZ (ISO8601 with colons replaced by hyphens)
        // We look for the pattern and extract everything before it
        if let range = name.range(of: #"-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z?$"#, options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }

        return nil
    }

    /// Parse a specific Live Set
    func parseLiveSet(_ liveSet: LiveSet) {
        accessFile(at: AppState.shared.selectedProject?.path ?? "") { folderUrl in
            let alsUrl = URL(fileURLWithPath: liveSet.path)

            let parser = AlsParser()
            guard parser.loadFile(at: alsUrl) else {
                print("Failed to parse Live Set: \(parser.errorMessage ?? "unknown error")")
                return
            }

            let tracks = parser.getTracks()
            liveSet.liveVersion = parser.liveVersion ?? "Unknown"
            liveSet.tracks = tracks
            liveSet.buildHierarchy()

            // Link tracks to subprojects
            if let project = AppState.shared.selectedProject {
                liveSet.linkTracksToSubprojects(project: project)
            }

            liveSet.lastUpdated = Date()

            print("Parsed \(tracks.count) tracks from \(liveSet.name) (Live \(liveSet.liveVersion))")
        }
    }

    /// Reload a project folder after changes
    private func reloadProject(folderPath: String) {
        accessFile(at: folderPath) { folderUrl in
            let liveSets = self.scanForLiveSets(in: folderUrl)

            DispatchQueue.main.async {
                if let project = AppState.shared.projects.first(where: { $0.path == folderPath }) {
                    // Update live sets list
                    project.liveSets = liveSets
                    project.lastUpdated = Date()

                    // Re-parse currently selected Live Set if it still exists
                    if let selected = AppState.shared.selectedLiveSet,
                       liveSets.contains(where: { $0.path == selected.path }) {
                        self.parseLiveSet(selected)
                    }
                }
            }
        }
    }

    /// Write a file to a project folder (uses stored bookmark for access)
    func writeToProjectFolder(_ project: Project, fileName: String, data: Data) -> URL? {
        var resultUrl: URL?
        accessFile(at: project.path) { folderUrl in
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
    func extractSubproject(from liveSetPath: String, groupId: Int, groupName: String, sourceLiveSetName: String, to outputPath: String, project: Project, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.accessFile(at: project.path) { folderUrl in
                let extractor = AlsExtractor()
                let result = extractor.extractGroup(from: liveSetPath, groupId: groupId, to: outputPath)

                if result.success, let outputPath = result.outputPath {
                    // Save metadata JSON file
                    let metadata = SubprojectMetadata(
                        sourceLiveSetName: sourceLiveSetName,
                        sourceGroupId: groupId,
                        sourceGroupName: groupName,
                        extractedAt: Date()
                    )

                    let metadataFileName = SubprojectMetadata.metadataFileName(for: outputPath)
                    let metadataUrl = folderUrl.appendingPathComponent(metadataFileName)

                    do {
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(metadata)
                        try jsonData.write(to: metadataUrl)
                        print("Saved metadata: \(metadataFileName)")
                    } catch {
                        print("Failed to save metadata: \(error)")
                    }

                    completion(outputPath)
                } else {
                    print("Extraction failed: \(result.error ?? "unknown error")")
                    completion(nil)
                }
            }
        }
    }

    /// Rescan a project folder to update the live sets list
    func rescanProject(_ project: Project) {
        accessFile(at: project.path) { folderUrl in
            let liveSets = self.scanForLiveSets(in: folderUrl)

            DispatchQueue.main.async {
                project.liveSets = liveSets
                project.lastUpdated = Date()
            }
        }
    }

    /// Create a version of a LiveSet by copying it with a timestamp
    func createVersion(of liveSet: LiveSet, in project: Project, comment: String? = nil) {
        accessFile(at: project.path) { folderUrl in
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
                DispatchQueue.main.async {
                    self.rescanProject(project)
                }
            } catch {
                print("Failed to create version: \(error.localizedDescription)")
            }
        }
    }
}

//
//  FileScanner.swift
//  Sordello
//
//  Scans project folders for files and updates the database.
//  Generic file scanning extracted from ProjectManager.
//
//  Created by Jonas Barsten on 10/12/2025.
//

import Foundation

/// Result of a folder scan operation
struct ScanResult {
    let liveSets: [LiveSet]
    let liveSetPaths: [String]
    let changedLiveSets: [LiveSet]
    let newLiveSets: [LiveSet]
}

/// Scans project folders for files and manages file discovery
struct FileScanner {

    // MARK: - Validation

    /// Check if a folder contains at least one .als file
    static func isValidAbletonProject(at url: URL) -> Bool {
        let fileManager = FileManager.default

        if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            return contents.contains { $0.pathExtension.lowercased() == "als" }
        }

        return false
    }

    // MARK: - Full Scan

    /// Scan folder and save LiveSets to project database
    /// Returns the paths of all LiveSets that need parsing
    static func scanAndSaveLiveSets(in folderUrl: URL, for project: Project, db: ProjectDatabase) throws -> [String] {
        let fileManager = FileManager.default

        // Delete existing LiveSets for this project
        try db.deleteAllLiveSets()

        var mainLiveSetPaths: [String: LiveSet] = [:]

        // Scan root folder for .als files (skip hidden files)
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                // Skip hidden files (versions are in .sordello/)
                guard !fileName.hasPrefix(".") else { continue }

                var liveSet = LiveSet(path: fileUrl.path, category: .main)
                liveSet.projectPath = project.path
                liveSet.comment = loadComment(for: fileUrl)
                liveSet.fileModificationDate = getFileModificationDate(for: fileUrl)
                try db.insertLiveSet(liveSet)
                mainLiveSetPaths[liveSet.name] = liveSet
            }
        }

        // Scan .sordello/{fileName}/versions/ for version files
        let sordelloUrl = folderUrl.appendingPathComponent(".sordello")
        if let sordelloContents = try? fileManager.contentsOfDirectory(at: sordelloUrl, includingPropertiesForKeys: nil) {
            for itemUrl in sordelloContents {
                // Skip non-directories and special folders like "db"
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: itemUrl.path, isDirectory: &isDir),
                      isDir.boolValue,
                      itemUrl.lastPathComponent != "db" else { continue }

                // Check for versions subdirectory
                let versionsUrl = itemUrl.appendingPathComponent("versions")
                guard let versionFiles = try? fileManager.contentsOfDirectory(at: versionsUrl, includingPropertiesForKeys: nil) else { continue }

                // Find the parent LiveSet by matching the folder name
                let parentName = itemUrl.lastPathComponent
                guard let parentLiveSet = mainLiveSetPaths[parentName] else { continue }

                for versionUrl in versionFiles where versionUrl.pathExtension.lowercased() == "als" {
                    var liveSet = LiveSet(path: versionUrl.path, category: .version)
                    liveSet.projectPath = project.path
                    liveSet.parentLiveSetPath = parentLiveSet.path
                    liveSet.fileModificationDate = getFileModificationDate(for: versionUrl)
                    try db.insertLiveSet(liveSet)
                }

                // Check for liveSetTracks subdirectory
                let liveSetTracksUrl = itemUrl.appendingPathComponent("liveSetTracks")
                if let trackIdDirs = try? fileManager.contentsOfDirectory(at: liveSetTracksUrl, includingPropertiesForKeys: nil) {
                    for trackIdDir in trackIdDirs {
                        // Each subdirectory is named with the trackId
                        var isTrackDir: ObjCBool = false
                        guard fileManager.fileExists(atPath: trackIdDir.path, isDirectory: &isTrackDir),
                              isTrackDir.boolValue,
                              let trackId = Int(trackIdDir.lastPathComponent) else { continue }

                        // Scan for .als files in this track directory
                        if let trackVersionFiles = try? fileManager.contentsOfDirectory(at: trackIdDir, includingPropertiesForKeys: nil) {
                            for trackVersionUrl in trackVersionFiles where trackVersionUrl.pathExtension.lowercased() == "als" {
                                var liveSet = LiveSet(path: trackVersionUrl.path, category: .liveSetTrackVersion)
                                liveSet.projectPath = project.path
                                liveSet.parentLiveSetPath = parentLiveSet.path
                                liveSet.sourceLiveSetName = parentName
                                liveSet.sourceGroupId = trackId
                                liveSet.fileModificationDate = getFileModificationDate(for: trackVersionUrl)
                                try db.insertLiveSet(liveSet)
                            }
                        }
                    }
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
        print("FileScanner: Saved \(liveSets.count) LiveSets to database")

        return liveSets.map { $0.path }
    }

    // MARK: - Incremental Update

    /// Result of incremental update
    struct IncrementalUpdateResult {
        let changed: [LiveSet]  // Files that were modified (for auto-versioning)
        let new: [LiveSet]      // New files added

        var allToReparse: [LiveSet] { changed + new }
    }

    /// Incrementally update LiveSets - returns changed and new LiveSets separately
    static func incrementalUpdate(in folderUrl: URL, for project: Project, db: ProjectDatabase) throws -> IncrementalUpdateResult {
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

        // Scan root folder (skip hidden files)
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                // Skip hidden files (versions are in .sordello/)
                guard !fileName.hasPrefix(".") else { continue }

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
                        print("FileScanner: File changed: \(existing.name)")
                    }
                } else {
                    // New main LiveSet
                    var liveSet = LiveSet(path: filePath, category: .main)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate

                    try db.insertLiveSet(liveSet)
                    newLiveSets.append(liveSet)
                    print("FileScanner: New file: \(liveSet.name)")
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
                        print("FileScanner: File changed: \(existing.name)")
                    }
                } else {
                    var liveSet = LiveSet(path: filePath, category: .backup)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate
                    try db.insertLiveSet(liveSet)
                    newLiveSets.append(liveSet)
                    print("FileScanner: New backup file: \(liveSet.name)")
                }
            }
        }

        // Scan .sordello/{fileName}/versions/ for version files
        let sordelloUrl = folderUrl.appendingPathComponent(".sordello")
        let mainLiveSets = try db.fetchMainLiveSets()
        let mainLiveSetsByName = Dictionary(uniqueKeysWithValues: mainLiveSets.map { ($0.name, $0) })

        if let sordelloContents = try? fileManager.contentsOfDirectory(at: sordelloUrl, includingPropertiesForKeys: nil) {
            for itemUrl in sordelloContents {
                // Skip non-directories and special folders like "db"
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: itemUrl.path, isDirectory: &isDir),
                      isDir.boolValue,
                      itemUrl.lastPathComponent != "db" else { continue }

                // Check for versions subdirectory
                let versionsUrl = itemUrl.appendingPathComponent("versions")
                guard let versionFiles = try? fileManager.contentsOfDirectory(at: versionsUrl, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }

                // Find the parent LiveSet by matching the folder name
                let parentName = itemUrl.lastPathComponent
                let parentLiveSet = mainLiveSetsByName[parentName]

                for versionUrl in versionFiles where versionUrl.pathExtension.lowercased() == "als" {
                    let filePath = versionUrl.path
                    currentFilePaths.insert(filePath)

                    let currentModDate = getFileModificationDate(for: versionUrl)

                    if var existing = existingByPath[filePath] {
                        // Check if file was modified
                        if let storedDate = existing.fileModificationDate,
                           let currentDate = currentModDate,
                           currentDate.timeIntervalSince(storedDate) > 1.0 {
                            existing.fileModificationDate = currentDate
                            try db.updateLiveSet(existing)
                            changedLiveSets.append(existing)
                            print("FileScanner: Version file changed: \(existing.name)")
                        }
                    } else {
                        // New version file
                        var liveSet = LiveSet(path: filePath, category: .version)
                        liveSet.projectPath = project.path
                        liveSet.parentLiveSetPath = parentLiveSet?.path
                        liveSet.fileModificationDate = currentModDate
                        try db.insertLiveSet(liveSet)
                        newLiveSets.append(liveSet)
                        print("FileScanner: New version file: \(versionUrl.lastPathComponent)")
                    }
                }

                // Check for liveSetTracks subdirectory
                let liveSetTracksUrl = itemUrl.appendingPathComponent("liveSetTracks")
                if let trackIdDirs = try? fileManager.contentsOfDirectory(at: liveSetTracksUrl, includingPropertiesForKeys: nil) {
                    for trackIdDir in trackIdDirs {
                        // Each subdirectory is named with the trackId
                        var isTrackDir: ObjCBool = false
                        guard fileManager.fileExists(atPath: trackIdDir.path, isDirectory: &isTrackDir),
                              isTrackDir.boolValue,
                              let trackId = Int(trackIdDir.lastPathComponent) else { continue }

                        // Scan for .als files in this track directory
                        if let trackVersionFiles = try? fileManager.contentsOfDirectory(at: trackIdDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                            for trackVersionUrl in trackVersionFiles where trackVersionUrl.pathExtension.lowercased() == "als" {
                                let filePath = trackVersionUrl.path
                                currentFilePaths.insert(filePath)

                                let currentModDate = getFileModificationDate(for: trackVersionUrl)

                                if var existing = existingByPath[filePath] {
                                    // Check if file was modified
                                    if let storedDate = existing.fileModificationDate,
                                       let currentDate = currentModDate,
                                       currentDate.timeIntervalSince(storedDate) > 1.0 {
                                        existing.fileModificationDate = currentDate
                                        try db.updateLiveSet(existing)
                                        changedLiveSets.append(existing)
                                        print("FileScanner: Track version file changed: \(existing.name)")
                                    }
                                } else {
                                    // New track version file
                                    var liveSet = LiveSet(path: filePath, category: .liveSetTrackVersion)
                                    liveSet.projectPath = project.path
                                    liveSet.parentLiveSetPath = parentLiveSet?.path
                                    liveSet.sourceLiveSetName = parentName
                                    liveSet.sourceGroupId = trackId
                                    liveSet.fileModificationDate = currentModDate
                                    try db.insertLiveSet(liveSet)
                                    newLiveSets.append(liveSet)
                                    print("FileScanner: New track version file: \(trackVersionUrl.lastPathComponent)")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Remove deleted files
        for (path, liveSet) in existingByPath {
            if !currentFilePaths.contains(path) {
                print("FileScanner: Deleted file: \(liveSet.name)")
                try db.deleteLiveSet(path: path)
            }
        }

        if changedLiveSets.isEmpty && newLiveSets.isEmpty {
            print("FileScanner: No files changed")
        }

        return IncrementalUpdateResult(changed: changedLiveSets, new: newLiveSets)
    }

    // MARK: - Helper Methods

    /// Get file modification date
    static func getFileModificationDate(for fileUrl: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.modificationDate] as? Date
    }

    /// Load comment from companion -comment.txt file
    static func loadComment(for alsUrl: URL) -> String? {
        let baseName = alsUrl.deletingPathExtension().lastPathComponent
        let commentUrl = alsUrl.deletingLastPathComponent().appendingPathComponent("\(baseName)-comment.txt")
        if let commentData = try? Data(contentsOf: commentUrl),
           let comment = String(data: commentData, encoding: .utf8) {
            return comment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

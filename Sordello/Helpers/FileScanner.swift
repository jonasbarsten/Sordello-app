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

        // Scan root folder for .als files
        if let rootContents = try? fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil) {
            for fileUrl in rootContents where fileUrl.pathExtension.lowercased() == "als" {
                let fileName = fileUrl.lastPathComponent

                if fileName.hasPrefix(".subproject-") {
                    var liveSet = LiveSet(path: fileUrl.path, category: .liveSetTrackVersion)
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
        print("FileScanner: Saved \(liveSets.count) LiveSets to database")

        return liveSets.map { $0.path }
    }

    // MARK: - Incremental Update

    /// Incrementally update LiveSets - returns changed and new LiveSets that need re-parsing
    static func incrementalUpdate(in folderUrl: URL, for project: Project, db: ProjectDatabase) throws -> [LiveSet] {
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
                        print("FileScanner: File changed: \(existing.name)")
                    }
                } else {
                    // New file
                    let category: FileCategory
                    if fileName.hasPrefix(".subproject-") {
                        category = .liveSetTrackVersion
                    } else if fileName.hasPrefix(".version-") {
                        category = .version
                    } else {
                        category = .main
                    }

                    var liveSet = LiveSet(path: filePath, category: category)
                    liveSet.projectPath = project.path
                    liveSet.comment = loadComment(for: fileUrl)
                    liveSet.fileModificationDate = currentModDate

                    if category == .liveSetTrackVersion {
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

        // Remove deleted files (exclude version LiveSets - they're in .sordello/versions/)
        for (path, liveSet) in existingByPath {
            if !currentFilePaths.contains(path) && liveSet.category != .version {
                print("FileScanner: Deleted file: \(liveSet.name)")
                try db.deleteLiveSet(path: path)
            }
        }

        let toReparse = changedLiveSets + newLiveSets
        if toReparse.isEmpty {
            print("FileScanner: No files changed")
        }

        return toReparse
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

    /// Extract parent LiveSet name from version filename
    /// Format: .version-{parentName}-{timestamp}.als
    static func extractParentName(from fileName: String) -> String? {
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

    /// Load subproject metadata from companion JSON file
    static func loadSubprojectMetadata(for liveSet: inout LiveSet, folderUrl: URL) {
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
}

// MARK: - DTOs

/// DTO for reading subproject metadata JSON
private struct SubprojectMetadataDTO: Codable {
    let sourceLiveSetName: String
    let sourceGroupId: Int
    let sourceGroupName: String
    let extractedAt: Date
}

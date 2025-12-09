//
//  VersionControl.swift
//  Sordello
//
//  File-based version control for LiveSets
//  Creates timestamped copies when .als files are modified
//

import Foundation

/// Manages file-based version history for a project's LiveSets
final class VersionControl {

    private let projectPath: String
    private let versionsPath: String
    private var isInitialized = false

    /// Initialize version control for a project
    /// - Parameter projectPath: Path to the Ableton project folder
    init(projectPath: String) {
        self.projectPath = projectPath
        self.versionsPath = (projectPath as NSString).appendingPathComponent(".sordello/versions")
    }

    /// Initialize the versions directory if it doesn't exist
    func initializeIfNeeded() throws {
        let fileManager = FileManager.default
        let versionsUrl = URL(fileURLWithPath: versionsPath)

        // Create versions directory if needed
        if !fileManager.fileExists(atPath: versionsPath) {
            try fileManager.createDirectory(at: versionsUrl, withIntermediateDirectories: true)
            print("VersionControl: Created versions directory")
        } else {
            print("VersionControl: Using existing versions directory")
        }

        isInitialized = true
    }

    /// Sync existing version files on disk to the database
    /// Call this after opening a project to ensure orphaned version files are registered
    func syncVersionsToDatabase(db: ProjectDatabase, mainLiveSets: [LiveSet]) throws {
        let fileManager = FileManager.default

        // Get existing version records from db
        var existingVersionPaths = Set<String>()
        for mainLiveSet in mainLiveSets {
            let versions = try db.fetchVersionLiveSets(forParentPath: mainLiveSet.path)
            for version in versions {
                existingVersionPaths.insert(version.path)
            }
        }

        // Scan version directories for each main LiveSet
        for mainLiveSet in mainLiveSets {
            let liveSetName = URL(fileURLWithPath: mainLiveSet.path).deletingPathExtension().lastPathComponent
            let liveSetVersionsPath = (versionsPath as NSString).appendingPathComponent(liveSetName)

            guard fileManager.fileExists(atPath: liveSetVersionsPath) else { continue }

            let versionFiles = try fileManager.contentsOfDirectory(atPath: liveSetVersionsPath)
                .filter { $0.hasSuffix(".als") }

            for versionFile in versionFiles {
                let versionPath = (liveSetVersionsPath as NSString).appendingPathComponent(versionFile)

                // Skip if already in database
                if existingVersionPaths.contains(versionPath) { continue }

                // Parse timestamp from filename
                let versionName = (versionFile as NSString).deletingPathExtension
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
                let timestamp = formatter.date(from: versionName) ?? Date()

                // Create LiveSet record
                var versionLiveSet = LiveSet(path: versionPath, category: .version)
                versionLiveSet.projectPath = projectPath
                versionLiveSet.parentLiveSetPath = mainLiveSet.path
                versionLiveSet.fileModificationDate = timestamp
                try db.insertLiveSet(versionLiveSet)

                print("VersionControl: Synced orphaned version \(versionName) for \(liveSetName)")
            }
        }
    }

    /// Save a version of a LiveSet file and record it in the database
    /// - Parameters:
    ///   - alsPath: Path to the .als file
    ///   - db: Database to store the version record in
    ///   - message: Optional description (stored in companion .txt file)
    /// - Returns: The version timestamp if successful
    @discardableResult
    func commitLiveSet(at alsPath: String, db: ProjectDatabase, message: String? = nil) throws -> String {
        guard isInitialized else {
            throw VersionControlError.repositoryNotInitialized
        }

        let fileManager = FileManager.default
        let alsUrl = URL(fileURLWithPath: alsPath)
        let fileName = alsUrl.lastPathComponent

        // Only track main .als files (not .version- or .subproject-)
        guard !fileName.hasPrefix(".") else {
            return ""
        }

        // Create subdirectory for this LiveSet
        let liveSetName = alsUrl.deletingPathExtension().lastPathComponent
        let liveSetVersionsPath = (versionsPath as NSString).appendingPathComponent(liveSetName)
        let liveSetVersionsUrl = URL(fileURLWithPath: liveSetVersionsPath)

        if !fileManager.fileExists(atPath: liveSetVersionsPath) {
            try fileManager.createDirectory(at: liveSetVersionsUrl, withIntermediateDirectories: true)
        }

        // Generate timestamp for version name (filesystem-safe format)
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let versionName = formatter.string(from: timestamp)

        // Check if we already have a version from this exact second
        let versionFileName = "\(versionName).als"
        let destinationUrl = liveSetVersionsUrl.appendingPathComponent(versionFileName)

        if fileManager.fileExists(atPath: destinationUrl.path) {
            // Already have a version from this second, skip
            return ""
        }

        // Check if content has changed from the most recent version
        let existingVersions = try getVersionFiles(for: liveSetName)
        if let latestVersion = existingVersions.first {
            let latestPath = liveSetVersionsUrl.appendingPathComponent(latestVersion)
            if fileManager.contentsEqual(atPath: alsPath, andPath: latestPath.path) {
                // Content unchanged, no need for new version
                return ""
            }
        }

        // Copy the file
        try fileManager.copyItem(at: alsUrl, to: destinationUrl)

        // Optionally save message as companion file
        if let message = message {
            let messageUrl = liveSetVersionsUrl.appendingPathComponent("\(versionName).txt")
            try message.write(to: messageUrl, atomically: true, encoding: .utf8)
        }

        // Create a LiveSet record for this version in the database
        var versionLiveSet = LiveSet(path: destinationUrl.path, category: .version)
        versionLiveSet.projectPath = projectPath
        versionLiveSet.parentLiveSetPath = alsPath
        versionLiveSet.fileModificationDate = timestamp
        versionLiveSet.comment = message
        try db.insertLiveSet(versionLiveSet)

        print("VersionControl: Saved version \(versionName) of \(liveSetName)")
        return versionName
    }

    /// Get version history for a LiveSet
    /// - Parameter fileName: Name of the .als file
    /// - Returns: Array of version entries (newest first)
    func getHistory(for fileName: String) -> [VersionEntry] {
        let liveSetName = (fileName as NSString).deletingPathExtension
        let liveSetVersionsPath = (versionsPath as NSString).appendingPathComponent(liveSetName)

        do {
            let versionFiles = try getVersionFiles(for: liveSetName)

            return versionFiles.compactMap { versionFile -> VersionEntry? in
                let versionName = (versionFile as NSString).deletingPathExtension

                // Parse timestamp from filename
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
                guard let date = formatter.date(from: versionName) else { return nil }

                // Check for companion message file
                let messagePath = (liveSetVersionsPath as NSString).appendingPathComponent("\(versionName).txt")
                let message = try? String(contentsOfFile: messagePath, encoding: .utf8)

                return VersionEntry(
                    hash: versionName,
                    date: date,
                    message: message ?? "Auto-save",
                    fileName: fileName
                )
            }
        } catch {
            print("VersionControl: Failed to get history: \(error)")
            return []
        }
    }

    /// Get the number of versions saved
    func commitCount() -> Int {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: versionsPath) else {
            return 0
        }

        var count = 0
        for item in contents {
            let itemPath = (versionsPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                // Count .als files in each LiveSet folder
                if let versions = try? fileManager.contentsOfDirectory(atPath: itemPath) {
                    count += versions.filter { $0.hasSuffix(".als") }.count
                }
            }
        }
        return count
    }

    /// Get total size of the versions directory
    func repositorySize() -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: versionsPath) else { return 0 }

        var totalSize: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let filePath = (versionsPath as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    // MARK: - Private Helpers

    /// Get sorted list of version files for a LiveSet (newest first)
    private func getVersionFiles(for liveSetName: String) throws -> [String] {
        let fileManager = FileManager.default
        let liveSetVersionsPath = (versionsPath as NSString).appendingPathComponent(liveSetName)

        guard fileManager.fileExists(atPath: liveSetVersionsPath) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(atPath: liveSetVersionsPath)
        return contents
            .filter { $0.hasSuffix(".als") }
            .sorted { $0 > $1 } // Newest first (lexicographic sort works with ISO format)
    }
}

// MARK: - Supporting Types

struct VersionEntry: Identifiable {
    let hash: String  // Now stores timestamp string instead of git hash
    let date: Date
    let message: String
    let fileName: String

    var id: String { hash }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum VersionControlError: Error, LocalizedError {
    case repositoryNotInitialized
    case commitFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotInitialized: return "Version control not initialized"
        case .commitFailed(let msg): return "Failed to save version: \(msg)"
        case .restoreFailed(let msg): return "Failed to restore version: \(msg)"
        }
    }
}

//
//  VersionControl.swift
//  Sordello
//
//  File-based version control for any file type
//  Creates timestamped copies in .sordello/files/{fileName}/versions/
//

import Foundation

/// Manages file-based version history for a project's files
final class VersionControl {

    private let projectPath: String
    private let filesPath: String
    private let bookmarkData: Data?

    /// Initialize version control for a project
    init(projectPath: String) {
        self.projectPath = projectPath
        self.filesPath = (projectPath as NSString)
            .appendingPathComponent(K.sordello.filesPath)
        self.bookmarkData = BookmarkManager.shared.getBookmarkData(for: projectPath)
    }

    /// Initialize the .sordello/files directory if it doesn't exist
    func initializeIfNeeded() throws {
        let fileManager = FileManager.default
        let filesUrl = URL(fileURLWithPath: filesPath)

        if !fileManager.fileExists(atPath: filesPath) {
            try fileManager.createDirectory(at: filesUrl, withIntermediateDirectories: true)
        }
    }

    /// Generate the path for a new version (without creating the file)
    /// - Parameter filePath: Path to the source file
    /// - Returns: The path where the version would be created
    func versionPath(for filePath: String) -> String {
        let fileUrl = URL(fileURLWithPath: filePath)
        let fileExtension = fileUrl.pathExtension
        let fileNameWithoutExtension = fileUrl.deletingPathExtension().lastPathComponent

        let formatter = DateFormatter()
        formatter.dateFormat = K.dateFormat.timestamp
        let versionName = formatter.string(from: Date())

        return (filesPath as NSString)
            .appendingPathComponent(fileNameWithoutExtension)
            .appending("/\(K.sordello.versionsDir)/\(versionName).\(fileExtension)")
    }

    /// Generate the path for a new track version (extracted track as standalone .als)
    /// - Parameters:
    ///   - liveSetPath: Path to the source LiveSet
    ///   - trackId: The track ID being extracted
    /// - Returns: The path where the track version would be created
    func liveSetTrackVersionPath(for liveSetPath: String, trackId: Int) -> String {
        let fileUrl = URL(fileURLWithPath: liveSetPath)
        let fileExtension = fileUrl.pathExtension
        let liveSetName = fileUrl.deletingPathExtension().lastPathComponent

        let formatter = DateFormatter()
        formatter.dateFormat = K.dateFormat.timestamp
        let versionName = formatter.string(from: Date())

        return (filesPath as NSString)
            .appendingPathComponent(liveSetName)
            .appending("/\(K.sordello.liveSetTracksDir)/\(trackId)/\(versionName).\(fileExtension)")
    }

    /// Copy a file synchronously (assumes caller has bookmark access)
    nonisolated func createCopy(of filePath: String, to destinationPath: String) throws {
        let fileManager = FileManager.default
        let destinationUrl = URL(fileURLWithPath: destinationPath)
        let parentDir = destinationUrl.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try fileManager.copyItem(
            at: URL(fileURLWithPath: filePath),
            to: destinationUrl
        )

        // Update modification date to now (copyItem preserves original date)
        try fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: destinationPath
        )

        print("VersionControl: Created version \(destinationUrl.lastPathComponent)")
    }

    /// Copy a file asynchronously with its own bookmark access (for background/UI use)
    @concurrent
    func createCopyAsync(of filePath: String, to destinationPath: String) async throws {
        // Resolve bookmark for background access
        guard let bookmarkData = bookmarkData,
              let resolved = BookmarkManager.resolveBookmark(bookmarkData) else {
            throw NSError(domain: "VersionControl", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access project folder"])
        }
        defer {
            if resolved.needsStopAccess {
                resolved.url.stopAccessingSecurityScopedResource()
            }
        }

        try createCopy(of: filePath, to: destinationPath)
    }
}

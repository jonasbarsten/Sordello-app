//
//  FileHandler.swift
//  Sordello
//
//  Protocol and dispatcher for file type handlers.
//  Enables generic handling of different file types (.als, images, audio, etc.)
//
//  Created by Jonas Barsten on 10/12/2025.
//

import Foundation

/// Protocol for file type handlers
/// Each supported file type has a handler that conforms to this protocol
protocol FileHandler {
    associatedtype FileType: ProjectFile

    /// Supported file extensions for this handler
    static var supportedExtensions: [String] { get }

    /// Parse a file and return updated model + any child objects
    /// Returns nil if parsing fails
    static func parse(_ file: FileType) -> (file: FileType, children: [any Sendable])?

    /// Parse and save to database
    /// Returns true if successful
    static func parseAndSave(_ file: FileType, to db: ProjectDatabase) -> Bool

    /// Parse all files in background using security-scoped bookmark
    static func parseAllInBackground(paths: [String], bookmarkData: Data, db: ProjectDatabase, projectPath: String)
}

// MARK: - File Handlers Dispatcher

/// Central dispatcher for routing file operations to the appropriate handler
enum FileHandlers {

    /// Get the file extension for a path
    static func fileExtension(for path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    /// Check if a file type is supported
    static func isSupported(_ path: String) -> Bool {
        let ext = fileExtension(for: path)
        return AlsHandler.supportedExtensions.contains(ext)
        // Future: || ImageHandler.supportedExtensions.contains(ext)
    }

    /// Parse a ProjectFile and save to database
    /// Dispatches to the appropriate handler based on file type
    static func parseAndSave(_ file: any ProjectFile, to db: ProjectDatabase) -> Bool {
        switch file {
        case let liveSet as LiveSet:
            return AlsHandler.parseAndSave(liveSet, to: db)
        // Future:
        // case let image as Image:
        //     return ImageHandler.parseAndSave(image, to: db)
        default:
            print("FileHandlers: No handler for file type: \(type(of: file))")
            return false
        }
    }

    /// Parse all files of a given type in background
    static func parseAllInBackground(
        paths: [String],
        fileType: String,
        bookmarkData: Data,
        db: ProjectDatabase,
        projectPath: String
    ) {
        switch fileType {
        case "als":
            AlsHandler.parseAllInBackground(paths: paths, bookmarkData: bookmarkData, db: db, projectPath: projectPath)
        // Future:
        // case "png", "jpg":
        //     ImageHandler.parseAllInBackground(paths: paths, bookmarkData: bookmarkData, db: db, projectPath: projectPath)
        default:
            print("FileHandlers: No handler for file type: \(fileType)")
        }
    }

    /// Parse all .als files in background (convenience method)
    static func parseLiveSetsInBackground(paths: [String], bookmarkData: Data, db: ProjectDatabase, projectPath: String) {
        AlsHandler.parseAllInBackground(paths: paths, bookmarkData: bookmarkData, db: db, projectPath: projectPath)
    }
}

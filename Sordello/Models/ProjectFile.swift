//
//  ProjectFile.swift
//  Sordello
//
//  Protocol for files that can be managed within a project.
//  Allows generic handling of different file types (LiveSets, images, audio, etc.)
//
//  Created by Jonas Barsten on 10/12/2025.
//

import Foundation
import GRDB

/// Category of a file within a project
/// Generic categories that apply to any file type
enum FileCategory: String, Codable, CaseIterable, DatabaseValueConvertible {
    case main               // Primary files in root
    case liveSetTrackVersion // Extracted track/group versions (subprojects)
    case version            // Versioned copies of files
    case backup             // Files in Backup/ folder
}

/// Protocol for files that can be managed within a project
/// Implemented by LiveSet and future file types (Image, AudioFile, etc.)
/// Note: Types should also conform to Identifiable separately
protocol ProjectFile: Sendable {
    /// File path (serves as primary key)
    var path: String { get }

    /// Display name derived from path
    var name: String { get }

    /// Category within the project
    var category: FileCategory { get }

    /// Last update timestamp
    var lastUpdated: Date { get }

    /// Whether the file has been parsed/processed
    var isParsed: Bool { get }

    /// File extension for this type (e.g., "als", "png")
    static var fileExtension: String { get }

    /// All supported file extensions for this type (e.g., ["als"], ["png", "jpg"])
    static var supportedExtensions: [String] { get }
}

// MARK: - Default Implementations

extension ProjectFile {
    var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static var supportedExtensions: [String] {
        [fileExtension]
    }
}

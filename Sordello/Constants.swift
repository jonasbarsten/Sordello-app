//
//  Constants.swift
//  Sordello
//
//  Created by Jonas Barsten on 09/12/2025.
//

/// App-wide constants
/// nonisolated: Static constants are safe to access from any thread
nonisolated struct K {
    nonisolated struct lexIndex {
        static let chars: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
        static let base = 26
    }

    nonisolated struct parsing {
        /// Maximum concurrent ALS parsing tasks to limit memory usage
        static let maxConcurrentAlsParsers = 4
    }

    nonisolated struct dateFormat {
        /// Filesystem-safe timestamp format for version files
        static let timestamp = "yyyy-MM-dd'T'HH-mm-ss"
    }

    /// App-level database (stored in ~/Library/Application Support/Sordello/)
    nonisolated struct app {
        static let dbFile = "sordello.db"
        static let supportDir = "Sordello"
    }

    /// Sordello data directory structure (per-project)
    /// .sordello/
    /// ├── db/
    /// │   └── sordello.db
    /// └── files/
    ///     └── {liveSetName}/
    ///         ├── versions/
    ///         └── liveSetTracks/{trackId}/
    nonisolated struct sordello {
        static let rootDir = ".sordello"
        static let dbDir = "db"
        static let dbFile = "sordello.db"
        static let filesDir = "files"
        static let versionsDir = "versions"
        static let liveSetTracksDir = "liveSetTracks"

        /// Full path: .sordello/db
        static var dbPath: String { "\(rootDir)/\(dbDir)" }
        /// Full path: .sordello/files
        static var filesPath: String { "\(rootDir)/\(filesDir)" }
        /// Full path: .sordello/db/sordello.db
        static var dbFilePath: String { "\(dbPath)/\(dbFile)" }
    }
}

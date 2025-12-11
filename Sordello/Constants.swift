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
}

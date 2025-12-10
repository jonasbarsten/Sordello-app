//
//  AlsHandler.swift
//  Sordello
//
//  High-level handler for Ableton Live Set (.als) files.
//  Orchestrates parsing (via AlsParser) and database operations.
//
//  Created by Jonas Barsten on 10/12/2025.
//

import Foundation

/// Handler for Ableton Live Set (.als) files
/// Implements FileHandler protocol for generic file handling
nonisolated struct AlsHandler: FileHandler {
    typealias FileType = LiveSet

    static let supportedExtensions = ["als"]

    // MARK: - Core Parsing

    /// Parse a LiveSet and return updated model + tracks
    /// Returns nil if parsing fails
    static func parse(_ liveSet: LiveSet) -> (file: LiveSet, children: [any Sendable])? {
        let alsUrl = URL(fileURLWithPath: liveSet.path)

        let parser = AlsParser()
        let result = parser.parse(at: alsUrl)
        guard result.success else {
            print("AlsHandler: Failed to parse \(liveSet.name): \(result.errorMessage ?? "unknown error")")
            return nil
        }

        var updatedLiveSet = liveSet
        updatedLiveSet.liveVersion = result.liveVersion ?? "Unknown"
        updatedLiveSet.isParsed = true
        updatedLiveSet.lastUpdated = Date()

        let tracks = createTracks(from: result.tracks, liveSetPath: liveSet.path)
        return (updatedLiveSet, tracks)
    }

    /// Parse a LiveSet and save to database
    /// Returns true if successful
    static func parseAndSave(_ liveSet: LiveSet, to db: ProjectDatabase) -> Bool {
        guard let (updatedLiveSet, children) = parse(liveSet),
              let tracks = children as? [LiveSetTrack] else {
            return false
        }

        do {
            try db.saveLiveSetWithTracks(updatedLiveSet, tracks: tracks)
            print("AlsHandler: Parsed \(tracks.count) tracks from \(liveSet.name) (Live \(updatedLiveSet.liveVersion))")
            return true
        } catch {
            print("AlsHandler: Failed to save parsed LiveSet: \(error)")
            return false
        }
    }

    // MARK: - Background Parsing

    /// Parse a single LiveSet by path (for background use)
    @concurrent
    static func parseSingle(path: String, db: ProjectDatabase) async throws {
        // Use autoreleasepool to release memory after each parse
        let parseResult: AlsParseResult = autoreleasepool {
            let parser = AlsParser()
            return parser.parse(atPath: path)
        }

        guard parseResult.success else {
            print("AlsHandler: Failed: \(URL(fileURLWithPath: path).lastPathComponent)")
            return
        }

        // Get existing LiveSet from database
        guard var liveSet = try db.fetchLiveSet(path: parseResult.path) else {
            print("AlsHandler: LiveSet not found in database: \(path)")
            return
        }

        guard !liveSet.isParsed else {
            print("AlsHandler: Already parsed: \(path)")
            return
        }

        // Update LiveSet with parsed data
        liveSet.liveVersion = parseResult.liveVersion ?? "Unknown"
        liveSet.isParsed = true
        liveSet.lastUpdated = Date()

        let tracks = createTracks(from: parseResult.tracks, liveSetPath: liveSet.path)

        // Save to database (GRDB is thread-safe)
        try db.saveLiveSetWithTracks(liveSet, tracks: tracks)
        print("AlsHandler: Parsed: \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    /// Maximum concurrent parsing operations to limit memory usage
    private static let maxConcurrentParses = 4

    /// Parse all LiveSets in parallel using security-scoped bookmark
    /// Uses TaskGroup with limited concurrency to control memory usage
    static func parseAllInBackground(
        paths: [String],
        bookmarkData: Data,
        db: ProjectDatabase
    ) {
        // Resolve bookmark for security-scoped access
        var isStale = false
        guard let folderUrl = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("AlsHandler: Failed to resolve bookmark for parsing")
            return
        }

        guard folderUrl.startAccessingSecurityScopedResource() else {
            print("AlsHandler: Failed to access security-scoped resource")
            return
        }

        Task {
            await parseWithLimitedConcurrency(paths: paths, db: db)
            folderUrl.stopAccessingSecurityScopedResource()
        }
    }

    /// Parse paths with limited concurrency using chunked TaskGroup
    private static func parseWithLimitedConcurrency(paths: [String], db: ProjectDatabase) async {
        // Process in chunks to limit concurrent memory usage
        let chunks = paths.chunked(into: maxConcurrentParses)

        for chunk in chunks {
            await withTaskGroup(of: Void.self) { group in
                for path in chunk {
                    let pathCopy = path  // Explicit copy for sendability
                    group.addTask {
                        try? await parseSingle(path: pathCopy, db: db)
                    }
                }
            }
        }

        print("AlsHandler: Completed parsing \(paths.count) LiveSets")
    }

    // MARK: - Private Helpers

    /// Create LiveSetTrack models from parsed track data
    private static func createTracks(from parsedTracks: [LiveSetTrack], liveSetPath: String) -> [LiveSetTrack] {
        var tracks: [LiveSetTrack] = []

        for parsedTrack in parsedTracks {
            var track = LiveSetTrack(
                trackId: parsedTrack.trackId,
                name: parsedTrack.name,
                type: parsedTrack.type,
                parentGroupId: parsedTrack.parentGroupId
            )
            track.liveSetPath = liveSetPath
            track.sortIndex = parsedTrack.sortIndex
            track.color = parsedTrack.color
            track.isFrozen = parsedTrack.isFrozen
            track.trackDelay = parsedTrack.trackDelay
            track.isDelayInSamples = parsedTrack.isDelayInSamples
            track.audioInput = parsedTrack.audioInput
            track.audioOutput = parsedTrack.audioOutput
            track.midiInput = parsedTrack.midiInput
            track.midiOutput = parsedTrack.midiOutput

            tracks.append(track)
        }

        return tracks
    }
}

// MARK: - Array Extension

private extension Array {
    /// Split array into chunks of specified size
    nonisolated func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

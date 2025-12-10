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

    /// Parse a single .als file (pure parsing, no DB operations)
    /// Returns the parse result which is Sendable
    @concurrent
    private static func parseAlsFile(at path: String) async -> AlsParseResult {
        autoreleasepool {
            let parser = AlsParser()
            return parser.parse(atPath: path)
        }
    }

    /// Parse all LiveSets in parallel using security-scoped bookmark
    /// Uses TaskGroup - parsing returns Sendable results, DB writes happen sequentially
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
            await parseWithTaskGroup(paths: paths, db: db)
            folderUrl.stopAccessingSecurityScopedResource()
        }
    }

    /// Parse paths using TaskGroup - returns results, then saves to DB
    private static func parseWithTaskGroup(paths: [String], db: ProjectDatabase) async {
        var completedCount = 0

        // TaskGroup returns AlsParseResult (Sendable), DB writes happen in for-await loop
        await withTaskGroup(of: AlsParseResult.self) { group in
            // Add all parsing tasks - only captures path (String is Sendable)
            for path in paths {
                group.addTask {
                    await parseAlsFile(at: path)
                }
            }

            // Process results as they complete (sequential, safe to use db here)
            for await result in group {
                completedCount += 1

                guard result.success else {
                    print("[\(completedCount)/\(paths.count)] Failed: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                    continue
                }

                // Save to database (outside the addTask closure, so db access is safe)
                do {
                    guard var liveSet = try db.fetchLiveSet(path: result.path) else {
                        print("[\(completedCount)/\(paths.count)] Not in DB: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                        continue
                    }

                    guard !liveSet.isParsed else {
                        continue
                    }

                    liveSet.liveVersion = result.liveVersion ?? "Unknown"
                    liveSet.isParsed = true
                    liveSet.lastUpdated = Date()

                    let tracks = createTracks(from: result.tracks, liveSetPath: liveSet.path)
                    try db.saveLiveSetWithTracks(liveSet, tracks: tracks)

                    print("[\(completedCount)/\(paths.count)] Parsed: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                } catch {
                    print("[\(completedCount)/\(paths.count)] DB error: \(error)")
                }
            }
        }

        print("AlsHandler: Completed parsing \(completedCount)/\(paths.count) LiveSets")
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

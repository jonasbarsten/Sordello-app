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
    /// Uses TaskGroup with limited concurrency - parsing returns Sendable results
    static func parseAllInBackground(
        paths: [String],
        bookmarkData: Data,
        db: ProjectDatabase,
        projectPath: String
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
            await MainActor.run {
                ProjectManager.shared.startParsingProgress(for: projectPath, total: paths.count)
            }
            await parseWithLimitedConcurrency(paths: paths, db: db, projectPath: projectPath)
            await MainActor.run {
                ProjectManager.shared.clearParsingProgress(for: projectPath)
            }
            folderUrl.stopAccessingSecurityScopedResource()
        }
    }

    /// Parse paths with limited concurrency using TaskGroup
    /// Processes in chunks to limit memory and allow UI updates between chunks
    private static func parseWithLimitedConcurrency(paths: [String], db: ProjectDatabase, projectPath: String) async {
        var totalCompleted = 0
        let totalCount = paths.count

        // Process in chunks to limit concurrent memory usage
        for chunk in paths.chunked(into: K.parsing.maxConcurrentAlsParsers) {
            await withTaskGroup(of: AlsParseResult.self) { group in
                // Add tasks for this chunk only
                for path in chunk {
                    group.addTask {
                        await parseAlsFile(at: path)
                    }
                }

                // Process results as they complete
                for await result in group {
                    totalCompleted += 1

                    // Update progress on main thread
                    await MainActor.run {
                        ProjectManager.shared.updateParsingProgress(for: projectPath, completed: totalCompleted)
                    }

                    guard result.success else {
                        print("[\(totalCompleted)/\(totalCount)] Failed: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                        continue
                    }

                    // Save to database
                    do {
                        guard var liveSet = try db.fetchLiveSet(path: result.path) else {
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

                        print("[\(totalCompleted)/\(totalCount)] Parsed: \(URL(fileURLWithPath: result.path).lastPathComponent)")
                    } catch {
                        print("[\(totalCompleted)/\(totalCount)] DB error: \(error)")
                    }
                }
            }
            // UI updates happen here between chunks as GRDB observers trigger
        }

        print("AlsHandler: Completed parsing \(totalCompleted)/\(totalCount) LiveSets")
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

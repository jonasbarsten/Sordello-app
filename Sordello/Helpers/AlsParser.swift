//
//  AlsParser.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation
import Compression

/// Result of parsing an ALS file
/// nonisolated: Used with AlsParser from background threads
nonisolated struct AlsParseResult {
    let path: String
    let tracks: [LiveSetTrack]
    let liveVersion: String?
    let errorMessage: String?

    var success: Bool { errorMessage == nil }
}

/// Parser for Ableton Live Set (.als) files
/// nonisolated: Opts out of Swift 6.2's default MainActor isolation so this can be
/// used from @concurrent background functions. Safe because it has no mutable state.
nonisolated struct AlsParser {

    /// Parse an .als file and return the result
    func parse(at url: URL) -> AlsParseResult {
        let path = url.path

        guard FileManager.default.fileExists(atPath: path) else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "File does not exist")
        }

        guard url.pathExtension.lowercased() == "als" else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "Not an Ableton Live Set file (.als)")
        }

        guard let compressedData = try? Data(contentsOf: url) else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "Failed to read file")
        }

        guard let xmlData = compressedData.gunzip(),
              let xmlString = String(data: xmlData, encoding: .utf8) else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "Failed to decompress file")
        }

        let xmlDocument: XMLDocument
        do {
            xmlDocument = try XMLDocument(xmlString: xmlString, options: [])
        } catch {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "Failed to parse XML: \(error.localizedDescription)")
        }

        guard let rootElement = xmlDocument.rootElement(),
              rootElement.name == "Ableton" else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: "Not a valid Ableton Live file")
        }

        // Extract Live version
        let liveVersion = rootElement.attribute(forName: "Creator")?.stringValue?
            .replacingOccurrences(of: "Ableton Live ", with: "")

        // Parse tracks
        let tracks = parseTracks(from: xmlDocument)

        return AlsParseResult(path: path, tracks: tracks, liveVersion: liveVersion, errorMessage: nil)
    }

    /// Convenience method to parse from path string
    func parse(atPath path: String) -> AlsParseResult {
        parse(at: URL(fileURLWithPath: path))
    }

    // MARK: - Private Parsing Methods

    private func parseTracks(from xmlDocument: XMLDocument) -> [LiveSetTrack] {
        guard let root = xmlDocument.rootElement(),
              let liveSet = root.elements(forName: "LiveSet").first,
              let tracksElement = liveSet.elements(forName: "Tracks").first else {
            return []
        }

        var tracks: [LiveSetTrack] = []
        let trackTypes = ["MidiTrack", "AudioTrack", "GroupTrack", "ReturnTrack"]

        // Collect track elements
        var trackElements: [(element: XMLElement, tagName: String)] = []
        for child in tracksElement.children ?? [] {
            guard let element = child as? XMLElement,
                  let tagName = element.name,
                  trackTypes.contains(tagName) else { continue }
            trackElements.append((element, tagName))
        }

        // Generate sort indices
        let sortIndices = FractionalIndex.generateInitialIndices(count: trackElements.count)

        // Parse each track
        for (index, (element, tagName)) in trackElements.enumerated() {
            var track = parseTrack(element, type: tagName)
            track.sortIndex = sortIndices[index]
            tracks.append(track)
        }

        return tracks
    }

    private func parseTrack(_ element: XMLElement, type: String) -> LiveSetTrack {
        let id = Int(element.attribute(forName: "Id")?.stringValue ?? "-1") ?? -1
        let name = getTrackName(element)
        let groupId = getTrackGroupId(element)

        let trackType: TrackType
        switch type {
        case "MidiTrack": trackType = .midi
        case "AudioTrack": trackType = .audio
        case "GroupTrack": trackType = .group
        case "ReturnTrack": trackType = .returnTrack
        default: trackType = .audio
        }

        var track = LiveSetTrack(
            trackId: id,
            name: name,
            type: trackType,
            parentGroupId: groupId == -1 ? nil : groupId
        )

        track.color = getTrackColor(element)
        track.isFrozen = getTrackFrozen(element)
        (track.trackDelay, track.isDelayInSamples) = getTrackDelay(element)

        if let deviceChain = element.elements(forName: "DeviceChain").first {
            track.audioInput = getRouting(from: deviceChain, name: "AudioInputRouting")
            track.audioOutput = getRouting(from: deviceChain, name: "AudioOutputRouting")
            track.midiInput = getRouting(from: deviceChain, name: "MidiInputRouting")
            track.midiOutput = getRouting(from: deviceChain, name: "MidiOutputRouting")
        }

        return track
    }

    private func getTrackName(_ element: XMLElement) -> String {
        element.elements(forName: "Name").first?
            .elements(forName: "EffectiveName").first?
            .attribute(forName: "Value")?.stringValue ?? "Unknown"
    }

    private func getTrackGroupId(_ element: XMLElement) -> Int {
        Int(element.elements(forName: "TrackGroupId").first?
            .attribute(forName: "Value")?.stringValue ?? "-1") ?? -1
    }

    private func getTrackColor(_ element: XMLElement) -> Int {
        Int(element.elements(forName: "Color").first?
            .attribute(forName: "Value")?.stringValue ?? "0") ?? 0
    }

    private func getTrackFrozen(_ element: XMLElement) -> Bool {
        element.elements(forName: "Freeze").first?
            .attribute(forName: "Value")?.stringValue?.lowercased() == "true"
    }

    private func getTrackDelay(_ element: XMLElement) -> (Double, Bool) {
        guard let delayElement = element.elements(forName: "TrackDelay").first else {
            return (0, false)
        }
        let value = Double(delayElement.elements(forName: "Value").first?
            .attribute(forName: "Value")?.stringValue ?? "0") ?? 0
        let isSampleBased = delayElement.elements(forName: "IsValueSampleBased").first?
            .attribute(forName: "Value")?.stringValue?.lowercased() == "true"
        return (value, isSampleBased)
    }

    private func getRouting(from deviceChain: XMLElement, name: String) -> LiveSetTrack.RoutingInfo? {
        guard let routingElement = deviceChain.elements(forName: name).first else { return nil }

        let target = routingElement.elements(forName: "Target").first?
            .attribute(forName: "Value")?.stringValue ?? ""
        let displayName = routingElement.elements(forName: "UpperDisplayString").first?
            .attribute(forName: "Value")?.stringValue ?? ""
        let channel = routingElement.elements(forName: "LowerDisplayString").first?
            .attribute(forName: "Value")?.stringValue ?? ""

        if target.isEmpty || target.contains("/None") { return nil }

        return LiveSetTrack.RoutingInfo(target: target, displayName: displayName, channel: channel)
    }
}

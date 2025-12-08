//
//  AlsParser.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation
import Compression

/// Result of parsing an ALS file - Sendable for crossing concurrency boundaries
struct AlsParseResult: Sendable {
    let path: String
    let tracks: [Track]
    let liveVersion: String?
    let errorMessage: String?
}

/// Parse a single .als file in the background
/// @concurrent ensures this runs OFF MainActor for parallel execution
@concurrent
func parseAlsFileInBackground(at path: String) async -> AlsParseResult {
    autoreleasepool {
        let url = URL(fileURLWithPath: path)
        let parser = AlsParser()
        if parser.loadFile(at: url) {
            return AlsParseResult(path: path, tracks: parser.getTracks(), liveVersion: parser.liveVersion, errorMessage: nil)
        } else {
            return AlsParseResult(path: path, tracks: [], liveVersion: nil, errorMessage: parser.errorMessage)
        }
    }
}

/// Parser for Ableton Live Set (.als) files
/// nonisolated to allow usage from @concurrent functions
nonisolated final class AlsParser {
    private var xmlDocument: XMLDocument?
    private(set) var errorMessage: String?
    private(set) var liveVersion: String?

    func loadFile(at url: URL) -> Bool {
        xmlDocument = nil
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "File does not exist"
            return false
        }

        guard url.pathExtension.lowercased() == "als" else {
            errorMessage = "Not an Ableton Live Set file (.als)"
            return false
        }

        // Read and decompress the gzip file
        guard let compressedData = try? Data(contentsOf: url) else {
            errorMessage = "Failed to read file"
            return false
        }

        guard let xmlString = decompressGzip(compressedData) else {
            return false
        }

        // Parse as XML
        do {
            xmlDocument = try XMLDocument(xmlString: xmlString, options: [])
        } catch {
            errorMessage = "Failed to parse XML: \(error.localizedDescription)"
            return false
        }

        // Verify it's an Ableton file
        guard let rootElement = xmlDocument?.rootElement(),
              rootElement.name == "Ableton" else {
            errorMessage = "Not a valid Ableton Live file"
            return false
        }

        // Extract Live version from Creator attribute (e.g., "Ableton Live 12.3")
        if let creator = rootElement.attribute(forName: "Creator")?.stringValue {
            // Extract version number from "Ableton Live X.Y"
            liveVersion = creator.replacingOccurrences(of: "Ableton Live ", with: "")
        }

        return true
    }

    /// Get all tracks from the loaded file
    func getTracks() -> [Track] {
        guard let root = xmlDocument?.rootElement(),
              let liveSet = root.elements(forName: "LiveSet").first,
              let tracksElement = liveSet.elements(forName: "Tracks").first else {
            return []
        }

        var tracks: [Track] = []
        let trackTypes = ["MidiTrack", "AudioTrack", "GroupTrack", "ReturnTrack"]

        // Collect track elements first
        var trackElements: [(element: XMLElement, tagName: String)] = []
        for child in tracksElement.children ?? [] {
            guard let element = child as? XMLElement,
                  let tagName = element.name,
                  trackTypes.contains(tagName) else {
                continue
            }
            trackElements.append((element, tagName))
        }

        // Generate fractional indices for all tracks (preserves XML/visual order)
        let sortIndices = FractionalIndex.generateInitialIndices(count: trackElements.count)

//        print("DEBUG: Generating \(trackElements.count) tracks with sortIndices")
//        print("DEBUG: First 10 sortIndices: \(Array(sortIndices.prefix(10)))")

        // Parse tracks with their sort indices
        for (index, (element, tagName)) in trackElements.enumerated() {
            var track = parseTrack(element, type: tagName)
            track.sortIndex = sortIndices[index]
//            print("DEBUG: Track[\(index)] '\(track.name)' → sortIndex '\(track.sortIndex)'")
            tracks.append(track)
        }

        return tracks
    }

    /// Get only group tracks
    func getGroups() -> [Track] {
        return getTracks().filter { $0.type == .group }
    }

    // MARK: - Private Methods

    private func decompressGzip(_ data: Data) -> String? {
        // .als files are gzip compressed
        guard let decompressed = data.gunzip() else {
            errorMessage = "Failed to decompress file"
            return nil
        }
        return String(data: decompressed, encoding: .utf8)
    }

    private func parseTrack(_ element: XMLElement, type: String) -> Track {
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

        var track = Track(
            trackId: id,
            name: name,
            type: trackType,
            parentGroupId: groupId == -1 ? nil : groupId
        )

        // Extract additional properties
        track.color = getTrackColor(element)
        track.isFrozen = getTrackFrozen(element)
        (track.trackDelay, track.isDelayInSamples) = getTrackDelay(element)

        // Extract routing info from DeviceChain
        if let deviceChain = element.elements(forName: "DeviceChain").first {
            track.audioInput = getRouting(from: deviceChain, name: "AudioInputRouting")
            track.audioOutput = getRouting(from: deviceChain, name: "AudioOutputRouting")
            track.midiInput = getRouting(from: deviceChain, name: "MidiInputRouting")
            track.midiOutput = getRouting(from: deviceChain, name: "MidiOutputRouting")
        }

        return track
    }

    private func getTrackName(_ element: XMLElement) -> String {
        if let nameElement = element.elements(forName: "Name").first,
           let effectiveName = nameElement.elements(forName: "EffectiveName").first,
           let value = effectiveName.attribute(forName: "Value")?.stringValue {
            return value
        }
        return "Unknown"
    }

    private func getTrackGroupId(_ element: XMLElement) -> Int {
        if let groupIdElement = element.elements(forName: "TrackGroupId").first,
           let value = groupIdElement.attribute(forName: "Value")?.stringValue {
            return Int(value) ?? -1
        }
        return -1
    }

    private func getTrackColor(_ element: XMLElement) -> Int {
        if let colorElement = element.elements(forName: "Color").first,
           let value = colorElement.attribute(forName: "Value")?.stringValue {
            return Int(value) ?? 0
        }
        return 0
    }

    private func getTrackFrozen(_ element: XMLElement) -> Bool {
        if let freezeElement = element.elements(forName: "Freeze").first,
           let value = freezeElement.attribute(forName: "Value")?.stringValue {
            return value.lowercased() == "true"
        }
        return false
    }

    private func getTrackDelay(_ element: XMLElement) -> (Double, Bool) {
        if let delayElement = element.elements(forName: "TrackDelay").first {
            let value = delayElement.elements(forName: "Value").first?
                .attribute(forName: "Value")?.stringValue ?? "0"
            let isSampleBased = delayElement.elements(forName: "IsValueSampleBased").first?
                .attribute(forName: "Value")?.stringValue?.lowercased() == "true"
            return (Double(value) ?? 0, isSampleBased)
        }
        return (0, false)
    }

    private func getRouting(from deviceChain: XMLElement, name: String) -> Track.RoutingInfo? {
        guard let routingElement = deviceChain.elements(forName: name).first else {
            return nil
        }

        let target = routingElement.elements(forName: "Target").first?
            .attribute(forName: "Value")?.stringValue ?? ""
        let displayName = routingElement.elements(forName: "UpperDisplayString").first?
            .attribute(forName: "Value")?.stringValue ?? ""
        let channel = routingElement.elements(forName: "LowerDisplayString").first?
            .attribute(forName: "Value")?.stringValue ?? ""

        // Skip if target is "None" or empty
        if target.isEmpty || target.contains("/None") {
            return nil
        }

        return Track.RoutingInfo(target: target, displayName: displayName, channel: channel)
    }
}

// MARK: - Data Extension for Gzip

import Compression

extension Data {
    /// Decompress gzip data using Apple's Compression framework
    func gunzip() -> Data? {
        guard self.count > 10 else { return nil }

        // Check for gzip magic number
        guard self[0] == 0x1f, self[1] == 0x8b else {
            return nil
        }

        // Parse gzip header to find start of compressed data
        var offset = 10 // Minimum gzip header size

        let flags = self[3]
        let hasExtra = (flags & 0x04) != 0
        let hasName = (flags & 0x08) != 0
        let hasComment = (flags & 0x10) != 0

        // Skip extra field
        if hasExtra && offset + 2 <= self.count {
            let extraLen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + extraLen
        }

        // Skip original filename (null-terminated)
        if hasName {
            while offset < self.count && self[offset] != 0 {
                offset += 1
            }
            offset += 1 // Skip null terminator
        }

        // Skip comment (null-terminated)
        if hasComment {
            while offset < self.count && self[offset] != 0 {
                offset += 1
            }
            offset += 1 // Skip null terminator
        }

        guard offset < self.count - 8 else { return nil }

        // Read original size from gzip trailer (last 4 bytes, little-endian)
        // Note: This is mod 2^32, so files >4GB would wrap, but .als files won't be that large
        let sizeOffset = self.count - 4
        let originalSize = Int(self[sizeOffset]) |
                          (Int(self[sizeOffset + 1]) << 8) |
                          (Int(self[sizeOffset + 2]) << 16) |
                          (Int(self[sizeOffset + 3]) << 24)

        // Extract the deflate-compressed data (excluding 8-byte trailer)
        let compressedData = self.subdata(in: offset..<(self.count - 8))

        // Allocate exact buffer size needed (with small margin for safety)
        let bufferSize = originalSize + 1024

        let result = compressedData.withUnsafeBytes { srcPtr -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destinationBuffer.deallocate() }

            let decodedSize = compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                srcBase.assumingMemoryBound(to: UInt8.self),
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )

            if decodedSize > 0 {
                return Data(bytes: destinationBuffer, count: decodedSize)
            }
            return nil
        }

        // If single buffer failed, fall back to streaming
        if let result = result {
            return result
        }

        // Streaming decompression as fallback
        return decompressStream(compressedData)
    }

    /// Streaming decompression for larger files
    private func decompressStream(_ compressedData: Data) -> Data? {
        var decompressed = Data()
        let pageSize = 65536

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        var stream = streamPtr.pointee
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }

        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pageSize)
        defer { dstBuffer.deallocate() }

        return compressedData.withUnsafeBytes { srcPtr -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }

            stream.src_ptr = srcBase.assumingMemoryBound(to: UInt8.self)
            stream.src_size = compressedData.count
            stream.dst_ptr = dstBuffer
            stream.dst_size = pageSize

            while true {
                status = compression_stream_process(&stream, 0)

                switch status {
                case COMPRESSION_STATUS_OK:
                    if stream.dst_size == 0 {
                        decompressed.append(dstBuffer, count: pageSize)
                        stream.dst_ptr = dstBuffer
                        stream.dst_size = pageSize
                    }
                case COMPRESSION_STATUS_END:
                    if stream.dst_ptr > dstBuffer {
                        let count = pageSize - stream.dst_size
                        decompressed.append(dstBuffer, count: count)
                    }
                    return decompressed
                default:
                    return nil
                }

                if stream.src_size == 0 {
                    break
                }
            }

            return decompressed.isEmpty ? nil : decompressed
        }
    }
}

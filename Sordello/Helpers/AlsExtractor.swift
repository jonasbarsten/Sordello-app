//
//  AlsExtractor.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation
import Compression

/// Extracts tracks from .als files to new standalone .als files
/// Pure struct - no mutable state, safe to use on any thread
struct AlsExtractor {

    struct ExtractionResult {
        let success: Bool
        let outputPath: String?
        let tracksExtracted: Int
        let error: String?
    }

    /// Extract any track (audio, MIDI, or group) from an .als file to a new file
    /// For groups: includes all nested tracks
    /// For audio/MIDI: just that single track
    func extractTrack(from inputPath: String, trackId: Int, to outputPath: String) -> ExtractionResult {
        // Read and decompress the input file
        let inputUrl = URL(fileURLWithPath: inputPath)
        guard let compressedData = try? Data(contentsOf: inputUrl) else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to read input file")
        }

        guard let xmlData = compressedData.gunzip() else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to decompress file")
        }

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to decode XML as UTF-8")
        }

        // Parse the XML
        let xmlDoc: XMLDocument
        do {
            xmlDoc = try XMLDocument(xmlString: xmlString, options: [.nodePreserveAll])
        } catch {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to parse XML: \(error.localizedDescription)")
        }

        // Find the structure
        guard let root = xmlDoc.rootElement(),
              root.name == "Ableton",
              let liveSet = root.elements(forName: "LiveSet").first,
              let tracksElement = liveSet.elements(forName: "Tracks").first else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Invalid .als structure")
        }

        let trackTypes = ["MidiTrack", "AudioTrack", "GroupTrack", "ReturnTrack"]

        // Get all track elements
        var allTrackElements: [XMLElement] = []
        for child in tracksElement.children ?? [] {
            if let element = child as? XMLElement,
               let tagName = element.name,
               trackTypes.contains(tagName) {
                allTrackElements.append(element)
            }
        }

        // Find the target track
        var targetTrackElement: XMLElement?
        var targetTrackType: String?
        for element in allTrackElements {
            if let idAttr = element.attribute(forName: "Id")?.stringValue,
               Int(idAttr) == trackId {
                targetTrackElement = element
                targetTrackType = element.name
                break
            }
        }

        guard let targetTrack = targetTrackElement,
              let trackType = targetTrackType else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Track with ID \(trackId) not found")
        }

        let trackName = getTrackName(targetTrack)
        print("Extracting track: \"\(trackName)\" (ID: \(trackId), Type: \(trackType))")

        var tracksToInclude: [XMLElement] = []
        var returnTracks: [XMLElement] = []

        // Collect return tracks
        for element in allTrackElements {
            if element.name == "ReturnTrack" {
                returnTracks.append(element)
            }
        }

        if trackType == "GroupTrack" {
            // For groups: include the group and all nested tracks
            var groupIdsToInclude = Set<Int>([trackId])

            // Keep scanning until we find no new nested groups
            var foundNew = true
            while foundNew {
                foundNew = false
                for element in allTrackElements {
                    if element.name == "GroupTrack" {
                        let nestedId = getTrackId(element)
                        if groupIdsToInclude.contains(nestedId) { continue }

                        let parentId = getTrackGroupId(element)
                        if groupIdsToInclude.contains(parentId) {
                            groupIdsToInclude.insert(nestedId)
                            foundNew = true
                            print("  Found nested group: \"\(getTrackName(element))\" (ID: \(nestedId))")
                        }
                    }
                }
            }

            // Set the main group track to root level
            setTrackGroupId(targetTrack, newGroupId: -1)
            tracksToInclude.append(targetTrack)
            print("  Including: \(trackName) (GroupTrack, ID: \(trackId))")

            // Add all child tracks
            for element in allTrackElements {
                guard let tagName = element.name, tagName != "ReturnTrack" else { continue }
                if element === targetTrack { continue }

                let trackGroupId = getTrackGroupId(element)
                if groupIdsToInclude.contains(trackGroupId) {
                    let childId = getTrackId(element)
                    let childName = getTrackName(element)
                    print("  Including: \(childName) (\(tagName), ID: \(childId))")
                    tracksToInclude.append(element)
                }
            }
        } else {
            // For audio/MIDI tracks: just include that single track at root level
            setTrackGroupId(targetTrack, newGroupId: -1)
            tracksToInclude.append(targetTrack)
            print("  Including: \(trackName) (\(trackType), ID: \(trackId))")
        }

        print("  Including \(returnTracks.count) return track(s)")

        // Remove all tracks from the original Tracks element
        while tracksElement.children?.first != nil {
            tracksElement.removeChild(at: 0)
        }

        // Add tracks in order: target track(s), return tracks
        for track in tracksToInclude {
            tracksElement.addChild(track.copy() as! XMLNode)
        }
        for track in returnTracks {
            tracksElement.addChild(track.copy() as! XMLNode)
        }

        // Get the modified XML string
        let newXmlString = xmlDoc.xmlString(options: [.nodePrettyPrint])

        // Compress to gzip
        guard let xmlBytes = newXmlString.data(using: .utf8),
              let compressedOutput = xmlBytes.gzip() else {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to compress output")
        }

        // Write to output file
        let outputUrl = URL(fileURLWithPath: outputPath)
        do {
            try compressedOutput.write(to: outputUrl)
        } catch {
            return ExtractionResult(success: false, outputPath: nil, tracksExtracted: 0, error: "Failed to write output file: \(error.localizedDescription)")
        }

        return ExtractionResult(
            success: true,
            outputPath: outputPath,
            tracksExtracted: tracksToInclude.count,
            error: nil
        )
    }

    // MARK: - Private Helper Methods

    private func getTrackId(_ element: XMLElement) -> Int {
        if let idAttr = element.attribute(forName: "Id")?.stringValue {
            return Int(idAttr) ?? -1
        }
        return -1
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

    private func setTrackGroupId(_ element: XMLElement, newGroupId: Int) {
        if let groupIdElement = element.elements(forName: "TrackGroupId").first {
            if let valueAttr = groupIdElement.attribute(forName: "Value") {
                valueAttr.stringValue = String(newGroupId)
            }
        }

        // If moving to root level (-1), route audio output to Master
        if newGroupId == -1 {
            setAudioOutputToMaster(element)
        }
    }

    /// Set AudioOutputRouting to Master for tracks at root level
    private func setAudioOutputToMaster(_ element: XMLElement) {
        // Navigate to DeviceChain -> AudioOutputRouting
        guard let deviceChain = element.elements(forName: "DeviceChain").first,
              let audioOutputRouting = deviceChain.elements(forName: "AudioOutputRouting").first,
              let target = audioOutputRouting.elements(forName: "Target").first else {
            return
        }

        let oldTarget = target.attribute(forName: "Value")?.stringValue ?? "unknown"
        target.attribute(forName: "Value")?.stringValue = "AudioOut/Master"

        // Also update the display strings
        if let upperDisplay = audioOutputRouting.elements(forName: "UpperDisplayString").first {
            upperDisplay.attribute(forName: "Value")?.stringValue = "Master"
        }
        if let lowerDisplay = audioOutputRouting.elements(forName: "LowerDisplayString").first {
            lowerDisplay.attribute(forName: "Value")?.stringValue = ""
        }
        print("  Fixed audio routing: \(oldTarget) → Master")
    }
}

// MARK: - Data Extension for Gzip Compression

extension Data {
    /// Compress data using gzip format
    func gzip() -> Data? {
        guard !self.isEmpty else { return nil }

        // Deflate compress the data
        let bufferSize = self.count + 1024
        var compressed = Data()

        let result = self.withUnsafeBytes { srcPtr -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destinationBuffer.deallocate() }

            let compressedSize = compression_encode_buffer(
                destinationBuffer,
                bufferSize,
                srcBase.assumingMemoryBound(to: UInt8.self),
                self.count,
                nil,
                COMPRESSION_ZLIB
            )

            if compressedSize > 0 {
                return Data(bytes: destinationBuffer, count: compressedSize)
            }
            return nil
        }

        guard let deflatedData = result else { return nil }

        // Build gzip format manually:
        // Header (10 bytes) + deflated data + CRC32 (4 bytes) + original size (4 bytes)

        // Gzip header
        let header = Data([
            0x1f, 0x8b,       // Magic number
            0x08,             // Compression method (deflate)
            0x00,             // Flags
            0x00, 0x00, 0x00, 0x00,  // Modification time
            0x00,             // Extra flags
            0xff              // OS (unknown)
        ])

        compressed.append(header)
        compressed.append(deflatedData)

        // CRC32 of original data
        let crc = crc32(self)
        compressed.append(UInt8(crc & 0xff))
        compressed.append(UInt8((crc >> 8) & 0xff))
        compressed.append(UInt8((crc >> 16) & 0xff))
        compressed.append(UInt8((crc >> 24) & 0xff))

        // Original size (mod 2^32)
        let size = UInt32(self.count)
        compressed.append(UInt8(size & 0xff))
        compressed.append(UInt8((size >> 8) & 0xff))
        compressed.append(UInt8((size >> 16) & 0xff))
        compressed.append(UInt8((size >> 24) & 0xff))

        return compressed
    }

    /// Calculate CRC32 checksum
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff

        // CRC32 lookup table
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xedb88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }

        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }

        return crc ^ 0xffffffff
    }
}

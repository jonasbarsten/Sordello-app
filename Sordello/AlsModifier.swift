//
//  AlsModifier.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation

/// Modifies existing .als files and saves as new versions.
///
/// This class is distinct from `AlsExtractor` which extracts portions of an .als file
/// to create subprojects. `AlsModifier` takes an existing .als file, applies modifications
/// (like track name changes), and saves to a new file - keeping the original unchanged.
///
/// Use cases:
/// - Renaming tracks and saving as a new version
/// - Future: Modifying track colors, routing, etc.
class AlsModifier {

    struct ModificationResult {
        let success: Bool
        let outputPath: String?
        let tracksModified: Int
        let error: String?
    }

    /// Save a copy of the .als file with modified track names.
    ///
    /// This creates a new .als file with the specified track name changes applied.
    /// The original file is never modified.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the original .als file
    ///   - outputPath: Path where the modified .als file should be saved
    ///   - nameChanges: Dictionary mapping track IDs to their new names
    /// - Returns: Result indicating success/failure and details
    func saveWithModifiedTrackNames(
        inputPath: String,
        outputPath: String,
        nameChanges: [Int: String]
    ) -> ModificationResult {
        // Read and decompress the input file
        let inputUrl = URL(fileURLWithPath: inputPath)
        guard let compressedData = try? Data(contentsOf: inputUrl) else {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to read input file")
        }

        guard let xmlData = compressedData.gunzip() else {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to decompress file")
        }

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to decode XML as UTF-8")
        }

        // Parse the XML (preserving all nodes including whitespace/comments)
        let xmlDoc: XMLDocument
        do {
            xmlDoc = try XMLDocument(xmlString: xmlString, options: [.nodePreserveAll])
        } catch {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to parse XML: \(error.localizedDescription)")
        }

        // Navigate to the Tracks element
        guard let root = xmlDoc.rootElement(),
              root.name == "Ableton",
              let liveSet = root.elements(forName: "LiveSet").first,
              let tracksElement = liveSet.elements(forName: "Tracks").first else {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Invalid .als structure")
        }

        let trackTypes = ["MidiTrack", "AudioTrack", "GroupTrack", "ReturnTrack"]

        // Apply name changes to matching tracks
        var changesApplied = 0
        for child in tracksElement.children ?? [] {
            guard let element = child as? XMLElement,
                  let tagName = element.name,
                  trackTypes.contains(tagName) else { continue }

            let trackId = getTrackId(element)
            if let newName = nameChanges[trackId] {
                let oldName = getTrackName(element)
                setTrackName(element, newName: newName)
                changesApplied += 1
                print("AlsModifier: Track \(trackId) renamed from '\(oldName)' to '\(newName)'")
            }
        }

        if changesApplied == 0 {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "No matching tracks found to rename")
        }

        // Serialize the modified XML
        let newXmlString = xmlDoc.xmlString(options: [.nodePrettyPrint])

        // Compress to gzip format (required for .als files)
        guard let xmlBytes = newXmlString.data(using: .utf8),
              let compressedOutput = xmlBytes.gzip() else {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to compress output")
        }

        // Write to the output file
        let outputUrl = URL(fileURLWithPath: outputPath)
        do {
            try compressedOutput.write(to: outputUrl)
        } catch {
            return ModificationResult(success: false, outputPath: nil, tracksModified: 0, error: "Failed to write output file: \(error.localizedDescription)")
        }

        print("AlsModifier: Saved \(changesApplied) track name change(s) to \(outputPath)")
        return ModificationResult(success: true, outputPath: outputPath, tracksModified: changesApplied, error: nil)
    }

    // MARK: - Private Helpers

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

    /// Sets the track name in the XML.
    ///
    /// Ableton stores track names in:
    /// ```xml
    /// <Name>
    ///   <EffectiveName Value="DisplayedName"/>
    ///   <UserName Value=""/>  <!-- Empty = auto-generated name -->
    /// </Name>
    /// ```
    ///
    /// When UserName has a value, Ableton uses it as the EffectiveName.
    /// We update both to ensure the name change is immediately visible.
    private func setTrackName(_ element: XMLElement, newName: String) {
        guard let nameElement = element.elements(forName: "Name").first else { return }

        // Set UserName (the user-defined name that persists)
        if let userNameElement = nameElement.elements(forName: "UserName").first,
           let valueAttr = userNameElement.attribute(forName: "Value") {
            valueAttr.stringValue = newName
        }

        // Also update EffectiveName for immediate effect
        if let effectiveNameElement = nameElement.elements(forName: "EffectiveName").first,
           let valueAttr = effectiveNameElement.attribute(forName: "Value") {
            valueAttr.stringValue = newName
        }
    }
}

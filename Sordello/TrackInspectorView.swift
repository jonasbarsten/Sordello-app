//
//  TrackInspectorView.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import SwiftUI

/// Inspector panel showing detailed track information
struct TrackInspectorView: View {
    let track: Track
    let project: Project?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                Divider()

                // Properties
                propertiesSection

                // Routing
                if hasRoutingInfo {
                    Divider()
                    routingSection
                }

                // Group info (child count)
                if track.isGroup {
                    Divider()
                    groupSection
                }

                // Subproject info
                if let subprojectPath = track.subprojectPath {
                    Divider()
                    subprojectSection(path: subprojectPath)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForTrackType(track.type))
                    .font(.title2)
                    .foregroundColor(colorForTrackType(track.type))

                Text(track.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(track.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                Text("ID: \(track.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties")
                .font(.headline)
                .foregroundColor(.secondary)

            // Color
            PropertyRow(label: "Color", value: track.colorName, icon: "paintpalette.fill")
                .foregroundColor(abletonColor(for: track.color))

            // Frozen status
            if track.isFrozen {
                PropertyRow(label: "Status", value: "Frozen", icon: "snowflake")
            }

            // Track delay
            if track.trackDelay != 0 {
                let unit = track.isDelayInSamples ? "samples" : "ms"
                PropertyRow(
                    label: "Track Delay",
                    value: "\(String(format: "%.1f", track.trackDelay)) \(unit)",
                    icon: "clock"
                )
            }

            // Parent group
            if let parentId = track.parentGroupId {
                PropertyRow(label: "Parent Group ID", value: "\(parentId)", icon: "folder")
            } else {
                PropertyRow(label: "Level", value: "Root", icon: "folder")
            }
        }
    }

    // MARK: - Routing Section

    private var hasRoutingInfo: Bool {
        track.audioInput != nil || track.audioOutput != nil ||
        track.midiInput != nil || track.midiOutput != nil
    }

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routing")
                .font(.headline)
                .foregroundColor(.secondary)

            if let audioIn = track.audioInput {
                RoutingRow(label: "Audio In", routing: audioIn, icon: "arrow.right.circle")
            }

            if let audioOut = track.audioOutput {
                RoutingRow(label: "Audio Out", routing: audioOut, icon: "arrow.left.circle")
            }

            if let midiIn = track.midiInput {
                RoutingRow(label: "MIDI In", routing: midiIn, icon: "pianokeys")
            }

            if let midiOut = track.midiOutput {
                RoutingRow(label: "MIDI Out", routing: midiOut, icon: "pianokeys")
            }
        }
    }

    // MARK: - Group Section

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group")
                .font(.headline)
                .foregroundColor(.secondary)

            let childCount = track.children.count
            PropertyRow(
                label: "Children",
                value: "\(childCount) track\(childCount == 1 ? "" : "s")",
                icon: "list.bullet.indent"
            )

            // Count by type
            let audioCount = track.children.filter { $0.type == .audio }.count
            let midiCount = track.children.filter { $0.type == .midi }.count
            let groupCount = track.children.filter { $0.type == .group }.count

            if audioCount > 0 {
                PropertyRow(label: "Audio Tracks", value: "\(audioCount)", icon: "waveform")
            }
            if midiCount > 0 {
                PropertyRow(label: "MIDI Tracks", value: "\(midiCount)", icon: "pianokeys")
            }
            if groupCount > 0 {
                PropertyRow(label: "Nested Groups", value: "\(groupCount)", icon: "folder.fill")
            }
        }
    }

    // MARK: - Subproject Section

    private func subprojectSection(path: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subproject")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "doc.badge.gearshape.fill")
                    .foregroundColor(.purple)

                VStack(alignment: .leading) {
                    Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .lineLimit(1)
                    Text("Extracted to subproject")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                navigateToSubproject(path: path)
            } label: {
                Label("Go to Subproject", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func navigateToSubproject(path: String) {
        guard let project = project else { return }
        if let subproject = project.subprojectLiveSets.first(where: { $0.path == path }) {
            AppState.shared.selectedLiveSet = subproject
            AppState.shared.selectedTrack = nil
        }
    }

    private func iconForTrackType(_ type: Track.TrackType) -> String {
        switch type {
        case .audio: return "waveform"
        case .midi: return "pianokeys"
        case .group: return "folder.fill"
        case .returnTrack: return "arrow.turn.up.right"
        }
    }

    private func colorForTrackType(_ type: Track.TrackType) -> Color {
        switch type {
        case .audio: return .orange
        case .midi: return .purple
        case .group: return .blue
        case .returnTrack: return .green
        }
    }

    private func abletonColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 1.0, green: 0.6, blue: 0.6),   // Rose
            Color(red: 1.0, green: 0.3, blue: 0.3),   // Red
            Color(red: 1.0, green: 0.6, blue: 0.2),   // Orange
            Color(red: 1.0, green: 0.8, blue: 0.4),   // Light Orange
            Color(red: 1.0, green: 1.0, blue: 0.6),   // Light Yellow
            Color(red: 1.0, green: 1.0, blue: 0.2),   // Yellow
            Color(red: 0.6, green: 1.0, blue: 0.2),   // Lime
            Color(red: 0.2, green: 0.8, blue: 0.2),   // Green
            Color(red: 0.4, green: 1.0, blue: 0.8),   // Mint
            Color(red: 0.2, green: 1.0, blue: 1.0),   // Cyan
            Color(red: 0.4, green: 0.8, blue: 1.0),   // Sky
            Color(red: 0.6, green: 0.8, blue: 1.0),   // Light Blue
            Color(red: 0.4, green: 0.4, blue: 1.0),   // Blue
            Color(red: 0.6, green: 0.4, blue: 1.0),   // Purple
            Color(red: 0.8, green: 0.4, blue: 1.0),   // Violet
            Color(red: 1.0, green: 0.4, blue: 0.8),   // Magenta
            Color(red: 1.0, green: 0.6, blue: 0.8),   // Pink
            Color(red: 0.8, green: 0.8, blue: 0.8),   // Light Gray
            Color(red: 0.5, green: 0.5, blue: 0.5),   // Medium Gray
            Color(red: 0.3, green: 0.3, blue: 0.3),   // Dark Gray
        ]
        guard index >= 0 && index < colors.count else { return .gray }
        return colors[index]
    }
}

// MARK: - Helper Views

struct PropertyRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

struct RoutingRow: View {
    let label: String
    let routing: TrackRouting
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.secondary)

                Text(label)
                    .foregroundColor(.secondary)
            }
            .font(.callout)

            HStack {
                Spacer().frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routing.displayName)
                        .fontWeight(.medium)

                    if !routing.channel.isEmpty {
                        Text(routing.channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - LiveSet Inspector View

/// Inspector panel showing detailed LiveSet information
struct LiveSetInspectorView: View {
    let liveSet: LiveSet
    var project: Project?
    @State private var editableComment: String = ""
    @State private var isEditingComment: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                Divider()

                // Properties
                propertiesSection

                Divider()

                // Track Summary
                trackSummarySection

                // Subproject info (if applicable)
                if liveSet.category == .subproject, let metadata = liveSet.metadata {
                    Divider()
                    subprojectSection(metadata: metadata)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForCategory(liveSet.category))
                    .font(.title2)
                    .foregroundColor(colorForCategory(liveSet.category))

                Text(liveSet.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(liveSet.category.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                Text("Live \(liveSet.liveVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File")
                .font(.headline)
                .foregroundColor(.secondary)

            PropertyRow(label: "Size", value: fileSize, icon: "doc")
            PropertyRow(label: "Modified", value: lastModified, icon: "clock")
            PropertyRow(label: "Path", value: liveSet.path, icon: "folder")

            // Editable comment section for all LiveSet types
            commentSection
        }
    }

    // MARK: - Comment Section

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.quote")
                    .frame(width: 20)
                    .foregroundColor(.secondary)
                Text("Comment")
                    .foregroundColor(.secondary)
                Spacer()
                if isEditingComment {
                    Button("Save") {
                        saveComment()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(editableComment.isEmpty ? "Add" : "Edit") {
                        isEditingComment = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.callout)

            if isEditingComment {
                TextEditor(text: $editableComment)
                    .font(.callout)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else if !editableComment.isEmpty {
                Text(editableComment)
                    .font(.callout)
                    .padding(.leading, 24)
                    .foregroundColor(.primary)
            } else {
                Text("No comment")
                    .font(.callout)
                    .padding(.leading, 24)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .onAppear {
            editableComment = liveSet.comment ?? ""
        }
        .onChange(of: liveSet.id) { _, _ in
            editableComment = liveSet.comment ?? ""
            isEditingComment = false
        }
    }

    // MARK: - Track Summary Section

    private var trackSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.headline)
                .foregroundColor(.secondary)

            let totalTracks = liveSet.tracks.count
            PropertyRow(label: "Total Tracks", value: "\(totalTracks)", icon: "list.bullet")

            let audioCount = liveSet.tracks.filter { $0.type == .audio }.count
            let midiCount = liveSet.tracks.filter { $0.type == .midi }.count
            let groupCount = liveSet.tracks.filter { $0.type == .group }.count
            let returnCount = liveSet.tracks.filter { $0.type == .returnTrack }.count

            if audioCount > 0 {
                PropertyRow(label: "Audio Tracks", value: "\(audioCount)", icon: "waveform")
            }
            if midiCount > 0 {
                PropertyRow(label: "MIDI Tracks", value: "\(midiCount)", icon: "pianokeys")
            }
            if groupCount > 0 {
                PropertyRow(label: "Groups", value: "\(groupCount)", icon: "folder.fill")
            }
            if returnCount > 0 {
                PropertyRow(label: "Return Tracks", value: "\(returnCount)", icon: "arrow.turn.up.right")
            }

            // Versions count (for main LiveSets)
            if liveSet.category == .main && !liveSet.versions.isEmpty {
                PropertyRow(label: "Versions", value: "\(liveSet.versions.count)", icon: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: - Subproject Section

    private func subprojectSection(metadata: SubprojectMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.headline)
                .foregroundColor(.secondary)

            PropertyRow(label: "Live Set", value: metadata.sourceLiveSetName, icon: "doc.fill")
            PropertyRow(label: "Group", value: metadata.sourceGroupName, icon: "folder.fill")
            PropertyRow(label: "Group ID", value: "\(metadata.sourceGroupId)", icon: "number")
            PropertyRow(label: "Extracted", value: formatDate(metadata.extractedAt), icon: "calendar")

            Button {
                navigateToSource(metadata: metadata)
            } label: {
                Label("Go to Source", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func navigateToSource(metadata: SubprojectMetadata) {
        guard let project = project else { return }

        // Find the source LiveSet by name
        guard let sourceLiveSet = project.mainLiveSets.first(where: { $0.name == metadata.sourceLiveSetName }) else {
            return
        }

        // Select the source LiveSet
        AppState.shared.selectedLiveSet = sourceLiveSet

        // Find and select the source group track
        func findTrack(withId id: Int, in tracks: [Track]) -> Track? {
            for track in tracks {
                if track.id == id {
                    return track
                }
                if let found = findTrack(withId: id, in: track.children) {
                    return found
                }
            }
            return nil
        }

        if let sourceTrack = findTrack(withId: metadata.sourceGroupId, in: sourceLiveSet.tracks) {
            AppState.shared.selectedTrack = sourceTrack
        } else {
            AppState.shared.selectedTrack = nil
        }
    }

    private func saveComment() {
        guard let project = project else {
            isEditingComment = false
            return
        }

        // Generate comment filename: {baseName}-comment.txt
        let url = URL(fileURLWithPath: liveSet.path)
        let baseName = url.deletingPathExtension().lastPathComponent
        let commentFileName = "\(baseName)-comment.txt"
        let folderUrl = url.deletingLastPathComponent()
        let commentUrl = folderUrl.appendingPathComponent(commentFileName)

        // Access the project folder to write
        ProjectManager.shared.accessFile(at: project.path) { _ in
            do {
                let trimmedComment = editableComment.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedComment.isEmpty {
                    // Delete the comment file if comment is empty
                    if FileManager.default.fileExists(atPath: commentUrl.path) {
                        try FileManager.default.removeItem(at: commentUrl)
                        print("Deleted comment file: \(commentFileName)")
                    }
                    liveSet.comment = nil
                } else {
                    // Write the comment to file
                    try trimmedComment.write(to: commentUrl, atomically: true, encoding: .utf8)
                    print("Saved comment: \(commentFileName)")
                    liveSet.comment = trimmedComment
                }
                editableComment = trimmedComment
            } catch {
                print("Failed to save comment: \(error.localizedDescription)")
            }
        }

        isEditingComment = false
    }

    // MARK: - Helpers

    private var fileSize: String {
        let url = URL(fileURLWithPath: liveSet.path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var lastModified: String {
        let url = URL(fileURLWithPath: liveSet.path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return "Unknown"
        }
        return formatDate(date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func iconForCategory(_ category: LiveSetCategory) -> String {
        switch category {
        case .main: return "doc.fill"
        case .subproject: return "doc.badge.gearshape.fill"
        case .version: return "clock.arrow.circlepath"
        case .backup: return "clock.fill"
        }
    }

    private func colorForCategory(_ category: LiveSetCategory) -> Color {
        switch category {
        case .main: return .blue
        case .subproject: return .purple
        case .version: return .orange
        case .backup: return .gray
        }
    }
}

#Preview("Track Inspector") {
    TrackInspectorView(
        track: Track(
            id: 15,
            name: "Test Track",
            type: .audio,
            parentGroupId: nil
        ),
        project: nil
    )
}

#Preview("LiveSet Inspector") {
    LiveSetInspectorView(
        liveSet: LiveSet(path: "/test/path.als", category: .main),
        project: nil
    )
}

//
//  TrackInspectorView.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import SwiftUI
import GRDB

// MARK: - Track Inspector (GRDB)

/// Inspector panel showing detailed track information
struct TrackInspectorView: View {
    let track: Track
    let liveSetPath: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                propertiesSection

                if hasRoutingInfo {
                    Divider()
                    routingSection
                }

                if track.isGroup {
                    Divider()
                    groupSection
                }

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

                Text("ID: \(track.trackId)")
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

            PropertyRow(label: "Color", value: track.colorName, icon: "paintpalette.fill")
                .foregroundColor(abletonColor(for: track.color))

            if track.isFrozen {
                PropertyRow(label: "Status", value: "Frozen", icon: "snowflake")
            }

            if track.trackDelay != 0 {
                let unit = track.isDelayInSamples ? "samples" : "ms"
                PropertyRow(
                    label: "Track Delay",
                    value: "\(String(format: "%.1f", track.trackDelay)) \(unit)",
                    icon: "clock"
                )
            }

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

    private var childCount: Int {
        let parentId = track.trackId
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return 0 }
        do {
            let children = try projectDb.fetchChildTracks(forLiveSetPath: liveSetPath, parentGroupId: parentId)
            return children.count
        } catch {
            return 0
        }
    }

    private func countByType(_ type: TrackType) -> Int {
        let parentId = track.trackId
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return 0 }
        do {
            let children = try projectDb.fetchChildTracks(forLiveSetPath: liveSetPath, parentGroupId: parentId)
            return children.filter { $0.type == type }.count
        } catch {
            return 0
        }
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group")
                .font(.headline)
                .foregroundColor(.secondary)

            let count = childCount
            PropertyRow(
                label: "Children",
                value: "\(count) track\(count == 1 ? "" : "s")",
                icon: "list.bullet.indent"
            )

            let audioCount = countByType(.audio)
            let midiCount = countByType(.midi)
            let groupCount = countByType(.group)

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
        UIState.shared.selectedLiveSetPath = path
        UIState.shared.selectedTrackId = nil
    }

    private func iconForTrackType(_ type: TrackType) -> String {
        switch type {
        case .audio: return "waveform"
        case .midi: return "pianokeys"
        case .group: return "folder.fill"
        case .returnTrack: return "arrow.turn.up.right"
        }
    }

    private func colorForTrackType(_ type: TrackType) -> Color {
        switch type {
        case .audio: return .orange
        case .midi: return .purple
        case .group: return .blue
        case .returnTrack: return .green
        }
    }

    private func abletonColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 1.0, green: 0.6, blue: 0.6),
            Color(red: 1.0, green: 0.3, blue: 0.3),
            Color(red: 1.0, green: 0.6, blue: 0.2),
            Color(red: 1.0, green: 0.8, blue: 0.4),
            Color(red: 1.0, green: 1.0, blue: 0.6),
            Color(red: 1.0, green: 1.0, blue: 0.2),
            Color(red: 0.6, green: 1.0, blue: 0.2),
            Color(red: 0.2, green: 0.8, blue: 0.2),
            Color(red: 0.4, green: 1.0, blue: 0.8),
            Color(red: 0.2, green: 1.0, blue: 1.0),
            Color(red: 0.4, green: 0.8, blue: 1.0),
            Color(red: 0.6, green: 0.8, blue: 1.0),
            Color(red: 0.4, green: 0.4, blue: 1.0),
            Color(red: 0.6, green: 0.4, blue: 1.0),
            Color(red: 0.8, green: 0.4, blue: 1.0),
            Color(red: 1.0, green: 0.4, blue: 0.8),
            Color(red: 1.0, green: 0.6, blue: 0.8),
            Color(red: 0.8, green: 0.8, blue: 0.8),
            Color(red: 0.5, green: 0.5, blue: 0.5),
            Color(red: 0.3, green: 0.3, blue: 0.3),
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
    let routing: Track.RoutingInfo
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

// MARK: - LiveSet Inspector (GRDB)

/// Inspector panel showing detailed LiveSet information
struct LiveSetInspectorView: View {
    let liveSet: LiveSet
    @State private var editableComment: String = ""
    @State private var isEditingComment: Bool = false
    @State private var autoVersionEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                propertiesSection
                Divider()
                trackSummarySection

                if liveSet.category == .main {
                    Divider()
                    versioningSection
                }

                if liveSet.category == .subproject, liveSet.hasMetadata {
                    Divider()
                    subprojectSection
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            autoVersionEnabled = liveSet.autoVersionEnabled
        }
        .onChange(of: liveSet.path) { _, _ in
            autoVersionEnabled = liveSet.autoVersionEnabled
        }
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
        .onChange(of: liveSet.path) { _, _ in
            editableComment = liveSet.comment ?? ""
            isEditingComment = false
        }
    }

    // MARK: - Track Summary Section

    private var totalTrackCount: Int {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return 0 }
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            return tracks.count
        } catch {
            return 0
        }
    }

    private func trackCountByType(_ type: TrackType) -> Int {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return 0 }
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            return tracks.filter { $0.type == type }.count
        } catch {
            return 0
        }
    }

    private var versionCount: Int {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return 0 }
        do {
            let versions = try projectDb.fetchVersionLiveSets(forParentPath: liveSet.path)
            return versions.count
        } catch {
            return 0
        }
    }

    private var trackSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.headline)
                .foregroundColor(.secondary)

            PropertyRow(label: "Total Tracks", value: "\(totalTrackCount)", icon: "list.bullet")

            let audioCount = trackCountByType(.audio)
            let midiCount = trackCountByType(.midi)
            let groupCount = trackCountByType(.group)
            let returnCount = trackCountByType(.returnTrack)

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

            if liveSet.category == .main && versionCount > 0 {
                PropertyRow(label: "Versions", value: "\(versionCount)", icon: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: - Versioning Section

    private var versioningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Versioning")
                .font(.headline)
                .foregroundColor(.secondary)

            Toggle(isOn: $autoVersionEnabled) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 20)
                        .foregroundColor(.secondary)
                    Text("Auto-version on save")
                }
                .font(.callout)
            }
            .toggleStyle(.switch)
            .onChange(of: autoVersionEnabled) { _, newValue in
                saveAutoVersionSetting(enabled: newValue)
            }

            Text("When enabled, a new version is automatically created each time this Live Set is saved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveAutoVersionSetting(enabled: Bool) {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

        var updatedLiveSet = liveSet
        updatedLiveSet.autoVersionEnabled = enabled
        do {
            try projectDb.updateLiveSet(updatedLiveSet)
        } catch {
            print("Failed to save auto-version setting: \(error)")
        }
    }

    // MARK: - Subproject Section

    private var subprojectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.headline)
                .foregroundColor(.secondary)

            PropertyRow(label: "Live Set", value: liveSet.sourceLiveSetName ?? "", icon: "doc.fill")
            PropertyRow(label: "Group", value: liveSet.sourceGroupName ?? "", icon: "folder.fill")
            PropertyRow(label: "Group ID", value: "\(liveSet.sourceGroupId ?? 0)", icon: "number")
            if let extractedAt = liveSet.extractedAt {
                PropertyRow(label: "Extracted", value: formatDate(extractedAt), icon: "calendar")
            }

            Button {
                navigateToSource()
            } label: {
                Label("Go to Source", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func navigateToSource() {
        guard let projectPath = liveSet.projectPath,
              let sourceName = liveSet.sourceLiveSetName,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

        // Find source LiveSet by name
        do {
            let mainSets = try projectDb.fetchMainLiveSets()
            guard let source = mainSets.first(where: { $0.name == sourceName }) else { return }

            UIState.shared.selectedLiveSetPath = source.path

            // Select the source group track
            if let groupId = liveSet.sourceGroupId {
                UIState.shared.selectedTrackId = groupId
            } else {
                UIState.shared.selectedTrackId = nil
            }
        } catch {
            print("Error navigating to source: \(error)")
        }
    }

    private func saveComment() {
        ProjectManager.shared.saveComment(for: liveSet, comment: editableComment)
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
            trackId: 15,
            name: "Test Track",
            type: .audio,
            parentGroupId: nil
        ),
        liveSetPath: "/test/path.als"
    )
}

#Preview("LiveSet Inspector") {
    LiveSetInspectorView(
        liveSet: LiveSet(path: "/test/path.als", category: .main)
    )
}

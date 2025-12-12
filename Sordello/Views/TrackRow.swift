//
//  TrackRow.swift
//  Sordello
//

import SwiftUI
import AppKit
import GRDB
import GRDBQuery

struct TrackRow: View {
    var track: LiveSetTrack
    let liveSetPath: String
    let projectPath: String?
    let depth: Int
    @State private var isExpanded = false
    @State private var isEditingName = false
    @State private var editingText = ""
    @State private var showingVersions = false
    @Query<ChildTracksRequest> var children: [LiveSetTrack]
    @Query<TrackVersionsRequest> var trackVersions: [LiveSet]
    @FocusState private var isNameFieldFocused: Bool

    private var liveSetName: String {
        URL(fileURLWithPath: liveSetPath).deletingPathExtension().lastPathComponent
    }

    init(track: LiveSetTrack, liveSetPath: String, projectPath: String?, depth: Int) {
        self.track = track
        self.liveSetPath = liveSetPath
        self.projectPath = projectPath
        self.depth = depth
        _children = Query(constant: ChildTracksRequest(liveSetPath: liveSetPath, parentGroupId: track.trackId))

        let liveSetName = URL(fileURLWithPath: liveSetPath).deletingPathExtension().lastPathComponent
        _trackVersions = Query(constant: TrackVersionsRequest(
            projectPath: projectPath ?? "",
            sourceLiveSetName: liveSetName,
            sourceTrackId: track.trackId
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Indentation
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }

                // Expand/collapse chevron for groups
                if track.isGroup {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                        .onTapGesture {
                            isExpanded.toggle()
                        }
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16)
                }

                // Track icon
                Image(systemName: iconForTrackType(track.type))
                    .foregroundColor(colorForTrackType(track.type))
                    .frame(width: 20)

                // Track name (editable on double-click)
                if isEditingName {
                    TextField("Track name", text: $editingText)
                        .textFieldStyle(.plain)
                        .fontWeight(track.isGroup ? .medium : .regular)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            commitNameChange()
                        }
                        .onExitCommand {
                            isEditingName = false
                        }
                } else {
                    Text(track.name)
                        .fontWeight(track.isGroup ? .medium : .regular)
                        .onTapGesture(count: 2) {
                            editingText = track.name
                            isEditingName = true
                            isNameFieldFocused = true
                        }
                }

                // Modified indicator
                if track.isModified {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                        .help("Name changed from '\(track.originalName)'")
                }

                // Version indicator
                if !trackVersions.isEmpty {
                    Button {
                        showingVersions.toggle()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("\(trackVersions.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.purple)
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("\(trackVersions.count) version(s)")
                    .popover(isPresented: $showingVersions) {
                        TrackVersionsPopover(versions: trackVersions, trackName: track.name, projectPath: projectPath ?? "")
                    }
                }

                Spacer()

                // Subproject indicator
                if let subprojectPath = track.subprojectPath {
                    Button {
                        navigateToVersion(path: subprojectPath)
                    } label: {
                        HStack(spacing: 4) {
                            if track.bounceReady {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.green)
                                Text("Bounce Ready")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "doc.badge.arrow.up")
                                    .foregroundColor(.blue)
                                Text("Subproject")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(track.bounceReady ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Go to subproject")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(track.isGroup ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                if track.isGroup {
                    isExpanded.toggle()
                }
            }
            .contextMenu {
                Button("Rename") {
                    editingText = track.name
                    isEditingName = true
                    isNameFieldFocused = true
                }

                if track.isModified {
                    Button("Undo Name Change") {
                        undoNameChange()
                    }
                }

                Divider()

                Button("Create Version as subproject") {
                    if let projectPath = projectPath {
                        ProjectManager.shared.createLiveSetTrackVersion(
                            liveSetPath: liveSetPath,
                            trackId: track.trackId,
                            trackName: track.name,
                            projectPath: projectPath
                        )
                    }
                }

                if !trackVersions.isEmpty {
                    Button("Show Versions (\(trackVersions.count))") {
                        showingVersions = true
                    }
                }
            }

            // Children (if expanded)
            if track.isGroup && isExpanded {
                ForEach(children, id: \.trackId) { child in
                    TrackRow(track: child, liveSetPath: liveSetPath, projectPath: projectPath, depth: depth + 1)
                }
            }
        }
    }

    private func navigateToVersion(path: String) {
        // TODO: Implement navigation to subproject
        print("Navigate to: \(path)")
    }

    private func commitNameChange() {
        isEditingName = false
        guard editingText != track.name else { return }
        guard let projectPath = projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

        var updatedTrack = track
        updatedTrack.name = editingText
        updatedTrack.isModified = (editingText != track.originalName)

        do {
            try projectDb.updateTrack(updatedTrack)
        } catch {
            print("Failed to update track: \(error)")
            editingText = track.name
        }
    }

    private func undoNameChange() {
        guard let projectPath = projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

        var updatedTrack = track
        updatedTrack.name = track.originalName
        updatedTrack.isModified = false

        do {
            try projectDb.updateTrack(updatedTrack)
        } catch {
            print("Failed to undo name change: \(error)")
        }
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
}

// MARK: - Track Versions Popover

struct TrackVersionsPopover: View {
    let versions: [LiveSet]
    let trackName: String
    let projectPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Versions of \(trackName)")
                .font(.headline)
                .padding(.bottom, 4)

            if versions.isEmpty {
                Text("No versions found")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(versions, id: \.path) { version in
                            NavigationLink(destination: ProjectFileDetailView(liveSet: version)) {
                                TrackVersionRow(version: version)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}

struct TrackVersionRow: View {
    let version: LiveSet

    private var formattedDate: String {
        guard let date = version.extractedAt else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.name)
                    .fontWeight(.medium)
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

#Preview("Audio Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 1, name: "Drums", type: .audio, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        projectPath: "/test",
        depth: 0
    )
}

#Preview("MIDI Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 2, name: "Synth Lead", type: .midi, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        projectPath: "/test",
        depth: 0
    )
}

#Preview("Group Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 3, name: "Drums Group", type: .group, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        projectPath: "/test",
        depth: 0
    )
}

#Preview("Nested Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 4, name: "Kick", type: .audio, parentGroupId: 3),
        liveSetPath: "/test/My Song.als",
        projectPath: "/test",
        depth: 1
    )
}

#Preview("Track version row") {
    TrackVersionRow(
        version: LiveSet(path: "/test/Balbal.als", category: .version)
    )
}

#Preview("Track version popover") {
    TrackVersionsPopover(
        versions: [LiveSet(path: "/test/Balbal.als", category: .version), LiveSet(path: "/test/bolbol.als", category: .version), LiveSet(path: "/test/belbel.als", category: .version)],
        trackName: "Jonas er kul",
        projectPath: "/test"
    )
}

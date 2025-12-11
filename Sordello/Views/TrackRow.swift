//
//  TrackRow.swift
//  Sordello
//

import SwiftUI
import AppKit
import GRDB

struct TrackRow: View {
    var track: LiveSetTrack
    let liveSetPath: String
    let depth: Int
    @State private var isExpanded = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var showError = false
    @State private var showOpenPrompt = false
    @State private var extractedPath: String?
    @State private var isEditingName = false
    @State private var editingText = ""
    @State private var children: [LiveSetTrack] = []
    @State private var observationTask: Task<Void, Never>?
    @FocusState private var isNameFieldFocused: Bool

    private var isSelected: Bool {
        UIState.shared.selectedTrack?.trackId == track.trackId
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
                            if isExpanded && children.isEmpty {
                                loadChildren()
                            }
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

                Spacer()

                // Extraction indicator
                if isExtracting {
                    ProgressView()
                        .controlSize(.small)
                }

                // Subproject indicator
                if let subprojectPath = track.subprojectPath {
                    Button {
                        navigateToSubproject(path: subprojectPath)
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (track.isGroup ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
            )
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected && track.isGroup {
                    // Second click on selected group toggles expand/collapse
                    isExpanded.toggle()
                    if isExpanded && children.isEmpty {
                        loadChildren()
                    }
                } else {
                    UIState.shared.selectedTrack = track
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
                Button("Create Version") {
                    ProjectManager.shared.createLiveSetTrackVersion(
                        liveSetPath: liveSetPath,
                        trackId: track.trackId,
                        trackName: track.name
                    )
                }

                if track.isGroup {
                    Button("Extract as Subproject") {
                        extractAsSubproject()
                    }
                    .disabled(isExtracting)
                }
            }
            .alert("Extraction Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(extractionError ?? "Unknown error")
            }
            .alert("Subproject Created", isPresented: $showOpenPrompt) {
                Button("Open in Ableton") {
                    if let path = extractedPath {
                        openInAbleton(path: path)
                    }
                }
                Button("Later", role: .cancel) { }
            } message: {
                Text("Would you like to open the subproject in Ableton Live?")
            }

            // Children (if expanded)
            if track.isGroup && isExpanded {
                ForEach(children, id: \.trackId) { child in
                    TrackRow(track: child, liveSetPath: liveSetPath, depth: depth + 1)
                }
            }
        }
        .onDisappear {
            observationTask?.cancel()
        }
    }

    private func navigateToSubproject(path: String) {
        UIState.shared.selectedLiveSetPath = path
        UIState.shared.selectedTrack = nil
    }

    private func extractAsSubproject() {
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path

        // Get project name
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent.replacingOccurrences(of: " Project", with: "")

        // Get LiveSet name
        let liveSetName = URL(fileURLWithPath: liveSetPath).deletingPathExtension().lastPathComponent

        let safeName = track.name.replacingOccurrences(of: "/", with: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = ".subproject-\(projectName)-\(safeName)-\(timestamp).als"
        let outputPath = URL(fileURLWithPath: projectPath).appendingPathComponent(fileName).path

        isExtracting = true

        ProjectManager.shared.extractSubproject(
            from: liveSetPath,
            groupId: track.trackId,
            groupName: track.name,
            sourceLiveSetName: liveSetName,
            to: outputPath,
            projectPath: projectPath
        ) { result in
            DispatchQueue.main.async {
                isExtracting = false

                if let path = result {
                    print("Extracted subproject to: \(path)")
                    extractedPath = path
                    showOpenPrompt = true
                    ProjectManager.shared.rescanProject(projectPath: projectPath)
                } else {
                    extractionError = "Failed to extract subproject"
                    showError = true
                }
            }
        }
    }

    private func openInAbleton(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func commitNameChange() {
        isEditingName = false
        guard editingText != track.name else { return }

        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

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
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }

        var updatedTrack = track
        updatedTrack.name = track.originalName
        updatedTrack.isModified = false

        do {
            try projectDb.updateTrack(updatedTrack)
        } catch {
            print("Failed to undo name change: \(error)")
        }
    }

    private func loadChildren() {
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = projectDb.observeChildTracks(forLiveSetPath: liveSetPath, parentGroupId: track.trackId)
            do {
                for try await fetched in observation.values(in: db) {
                    children = fetched
                }
            } catch {
                // Observation cancelled
            }
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

#Preview("Audio Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 1, name: "Drums", type: .audio, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        depth: 0
    )
}

#Preview("MIDI Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 2, name: "Synth Lead", type: .midi, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        depth: 0
    )
}

#Preview("Group Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 3, name: "Drums Group", type: .group, parentGroupId: nil),
        liveSetPath: "/test/My Song.als",
        depth: 0
    )
}

#Preview("Nested Track") {
    TrackRow(
        track: LiveSetTrack(trackId: 4, name: "Kick", type: .audio, parentGroupId: 3),
        liveSetPath: "/test/My Song.als",
        depth: 1
    )
}

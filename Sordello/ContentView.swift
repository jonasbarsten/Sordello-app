//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var appState = AppState.shared
    var oscServer = OSCServer.shared

    var body: some View {
        NavigationSplitView {
            // Sidebar with project list
            List(selection: $appState.selectedProject) {
                if appState.projects.isEmpty {
                    Text("No projects opened")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(appState.projects) { project in
                        ProjectRow(project: project)
                            .tag(project)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem(placement: .status) {
                    HStack {
                        Circle()
                            .fill(oscServer.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(oscServer.isRunning ? "Listening" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } content: {
            // Middle column: Live Sets in selected project
            if let project = appState.selectedProject {
                LiveSetListView(project: project)
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        } detail: {
            // Right column: Track structure of selected Live Set
            if let liveSet = appState.selectedLiveSet {
                LiveSetDetailView(liveSet: liveSet, project: appState.selectedProject)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No Live Set selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Open an Ableton Live project to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Project...") {
                        ProjectManager.shared.openProject()
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}

struct ProjectRow: View {
    var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text(project.name)
                    .fontWeight(.medium)
            }
            Text("\(project.mainLiveSets.count) set(s), \(project.subprojectLiveSets.count) subproject(s)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct LiveSetListView: View {
    var project: Project
    @Bindable var appState = AppState.shared
    @State private var expandedLiveSets: Set<String> = []

    private var sortedMainLiveSets: [LiveSet] {
        let liveSets = project.mainLiveSets
        if appState.liveSetSortOrder == .descending {
            return liveSets.reversed()
        }
        return liveSets
    }

    private func toggleExpanded(_ liveSet: LiveSet) {
        if expandedLiveSets.contains(liveSet.id) {
            expandedLiveSets.remove(liveSet.id)
        } else {
            expandedLiveSets.insert(liveSet.id)
        }
    }

    var body: some View {
        List(selection: $appState.selectedLiveSet) {
            // Main Live Sets
            if !project.mainLiveSets.isEmpty {
                Section {
                    ForEach(sortedMainLiveSets) { liveSet in
                        LiveSetRow(liveSet: liveSet, project: project, isExpanded: expandedLiveSets.contains(liveSet.id)) {
                            toggleExpanded(liveSet)
                        }
                        .tag(liveSet)

                        // Show versions as separate list items when expanded
                        if expandedLiveSets.contains(liveSet.id) {
                            ForEach(liveSet.versions) { version in
                                VersionRow(version: version)
                                    .tag(version)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Live Sets")
                        Spacer()
                        Button {
                            appState.liveSetSortOrder = appState.liveSetSortOrder == .ascending ? .descending : .ascending
                        } label: {
                            Image(systemName: appState.liveSetSortOrder == .ascending ? "arrow.up" : "arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help(appState.liveSetSortOrder == .ascending ? "Sort Z-A" : "Sort A-Z")
                    }
                }
            }

            // Subprojects
            if !project.subprojectLiveSets.isEmpty {
                Section("Subprojects") {
                    ForEach(project.subprojectLiveSets) { liveSet in
                        LiveSetRow(liveSet: liveSet, project: project, isExpanded: false, onToggleExpand: {})
                            .tag(liveSet)
                    }
                }
            }

            // Backups (collapsed by default)
            if !project.backupLiveSets.isEmpty {
                Section("Backups (\(project.backupLiveSets.count))") {
                    ForEach(project.backupLiveSets) { liveSet in
                        LiveSetRow(liveSet: liveSet, project: project, isExpanded: false, onToggleExpand: {})
                            .tag(liveSet)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        .onChange(of: appState.selectedLiveSet) { _, newValue in
            if let liveSet = newValue, liveSet.tracks.isEmpty {
                ProjectManager.shared.parseLiveSet(liveSet)
            }
        }
    }
}

struct LiveSetRow: View {
    var liveSet: LiveSet
    var project: Project?
    var isExpanded: Bool
    var onToggleExpand: () -> Void
    @State private var showVersionDialog = false
    @State private var versionComment = ""

    var body: some View {
        HStack {
            // Expand/collapse chevron for main LiveSets with versions
            if liveSet.category == .main && !liveSet.versions.isEmpty {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                    .onTapGesture {
                        onToggleExpand()
                    }
            } else if liveSet.category == .main {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 12)
            }

            Image(systemName: iconForCategory(liveSet.category))
                .foregroundColor(colorForCategory(liveSet.category))

            VStack(alignment: .leading, spacing: 2) {
                Text(liveSet.name)
                    .lineLimit(1)

                // Show source info for subprojects with metadata
                if liveSet.category == .subproject, let metadata = liveSet.metadata {
                    Text("From: \(metadata.sourceLiveSetName) → \(metadata.sourceGroupName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if liveSet.category == .main && !liveSet.versions.isEmpty {
                Text("(\(liveSet.versions.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Ableton Live") {
                openInAbleton()
            }

            if liveSet.category == .main {
                Divider()
                Button("Create Version...") {
                    versionComment = ""
                    showVersionDialog = true
                }
            }
        }
        .alert("Create Version", isPresented: $showVersionDialog) {
            TextField("Comment (optional)", text: $versionComment)
            Button("Create") {
                createVersion(comment: versionComment.isEmpty ? nil : versionComment)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add an optional comment to describe this version.")
        }
    }

    private func createVersion(comment: String?) {
        guard let project = project else { return }
        ProjectManager.shared.createVersion(of: liveSet, in: project, comment: comment)
    }

    private func openInAbleton() {
        let url = URL(fileURLWithPath: liveSet.path)
        NSWorkspace.shared.open(url)
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

struct VersionRow: View {
    var version: LiveSet

    var body: some View {
        HStack(alignment: .top) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24)
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatVersionName(version.name))
                    .font(.caption)
                    .lineLimit(1)
                if let comment = version.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contextMenu {
            Button("Open in Ableton Live") {
                let url = URL(fileURLWithPath: version.path)
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func formatVersionName(_ name: String) -> String {
        // Extract timestamp from .version-{parentName}-{timestamp}
        // Format: 2025-12-08T14-30-00Z -> "2025-12-08 14:30"
        if let range = name.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}"#, options: .regularExpression) {
            var timestamp = String(name[range])
            timestamp = timestamp.replacingOccurrences(of: "T", with: " ")
            let parts = timestamp.split(separator: " ")
            if parts.count == 2 {
                let date = parts[0]
                let time = parts[1].replacingOccurrences(of: "-", with: ":")
                let timeParts = time.split(separator: ":")
                if timeParts.count >= 2 {
                    return "\(date) \(timeParts[0]):\(timeParts[1])"
                }
            }
        }
        return name
    }
}

struct LiveSetDetailView: View {
    var liveSet: LiveSet
    var project: Project?
    @Bindable var appState = AppState.shared

    private var isInspectorPresented: Binding<Bool> {
        Binding(
            get: { appState.isInspectorVisible },
            set: { newValue in
                // Sync inspector visibility with drag state
                appState.isInspectorVisible = newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(liveSet.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(liveSet.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Show source info for subprojects
                    if liveSet.category == .subproject, let metadata = liveSet.metadata {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text("From \(metadata.sourceLiveSetName) → \(metadata.sourceGroupName) (ID: \(metadata.sourceGroupId))")
                                .font(.caption)
                        }
                        .foregroundColor(.purple)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Ableton Live \(liveSet.liveVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(liveSet.groups.count) groups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            if liveSet.tracks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text("Loading track structure...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(liveSet.rootTracks) { track in
                            TrackRow(track: track, depth: 0, liveSet: liveSet, project: project)
                        }
                    }
                    .padding()
                }
            }
        }
        .inspector(isPresented: isInspectorPresented) {
            Group {
                if let selectedTrack = appState.selectedTrack {
                    TrackInspectorView(track: selectedTrack, project: project)
                } else {
                    LiveSetInspectorView(liveSet: liveSet, project: project)
                }
            }
            .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ProjectManager.shared.openProject()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Open Project...")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: appState.isInspectorVisible ? "info.circle.fill" : "info.circle")
                }
                .help(appState.isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .onChange(of: liveSet.id) { _, _ in
            // Clear track selection when changing LiveSet
            appState.selectedTrack = nil
        }
    }
}

struct TrackRow: View {
    let track: Track
    let depth: Int
    let liveSet: LiveSet
    let project: Project?
    @State private var isExpanded = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var showError = false
    @State private var showOpenPrompt = false
    @State private var extractedPath: String?
    @Bindable var appState = AppState.shared

    private var isSelected: Bool {
        appState.selectedTrack?.id == track.id
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

                // Track name
                Text(track.name)
                    .fontWeight(track.isGroup ? .medium : .regular)

                Spacer()

                // Extraction indicator
                if isExtracting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.horizontal, 4)
                }

                // Subproject indicator (clickable to navigate)
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
                // Select the track to show inspector
                appState.selectedTrack = track
            }
            .contextMenu {
                if track.isGroup {
                    Button("Extract as Subproject") {
                        extractAsSubproject()
                    }
                    .disabled(isExtracting || project == nil)
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
                ForEach(track.children) { child in
                    TrackRow(track: child, depth: depth + 1, liveSet: liveSet, project: project)
                }
            }
        }
    }

    private func navigateToSubproject(path: String) {
        guard let project = project else { return }

        // Find the subproject LiveSet by path
        if let subproject = project.subprojectLiveSets.first(where: { $0.path == path }) {
            AppState.shared.selectedLiveSet = subproject
            AppState.shared.selectedTrack = nil
        }
    }

    private func extractAsSubproject() {
        guard let project = project else { return }

        // Generate filename
        let safeName = track.name.replacingOccurrences(of: "/", with: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = ".subproject-\(project.name)-\(safeName)-\(timestamp).als"
        let outputPath = URL(fileURLWithPath: project.path).appendingPathComponent(fileName).path

        isExtracting = true

        // Use ProjectManager to extract with proper folder access
        ProjectManager.shared.extractSubproject(
            from: liveSet.path,
            groupId: track.id,
            groupName: track.name,
            sourceLiveSetName: liveSet.name,
            to: outputPath,
            project: project
        ) { result in
            DispatchQueue.main.async {
                isExtracting = false

                if let path = result {
                    print("Extracted subproject to: \(path)")
                    extractedPath = path
                    showOpenPrompt = true

                    // Rescan project folder to show new subproject
                    ProjectManager.shared.rescanProject(project)
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
}

#Preview {
    ContentView()
}

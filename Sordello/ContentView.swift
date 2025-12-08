//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [SDProject]
    var oscServer = OSCServer.shared

    var body: some View {
        NavigationSplitView {
            ProjectListView()
        } content: {
            if let selectedPath = UIState.shared.selectedProjectPath,
               let project = projects.first(where: { $0.path == selectedPath }) {
                LiveSetListView(projectPath: project.path)
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        } detail: {
            if let selectedPath = UIState.shared.selectedLiveSetPath {
                LiveSetDetailWrapper(liveSetPath: selectedPath)
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
        .onAppear {
            // Inject model context to ProjectManager
            ProjectManager.shared.modelContext = modelContext
        }
    }
}

// MARK: - Project List (Sidebar)

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDProject.lastUpdated, order: .reverse) private var projects: [SDProject]
    var oscServer = OSCServer.shared

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedProjectPath },
            set: { UIState.shared.selectedProjectPath = $0 }
        )) {
            if projects.isEmpty {
                Text("No projects opened")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(projects, id: \.path) { project in
                    ProjectRow(project: project)
                        .tag(project.path)
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
    }
}

struct ProjectRow: View {
    @Environment(\.modelContext) private var modelContext
    var project: SDProject

    private var mainCount: Int {
        let predicate = SDPredicates.mainLiveSets(forProjectPath: project.path)
        let descriptor = FetchDescriptor<SDLiveSet>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private var subprojectCount: Int {
        let predicate = SDPredicates.subprojectLiveSets(forProjectPath: project.path)
        let descriptor = FetchDescriptor<SDLiveSet>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text(project.name)
                    .fontWeight(.medium)
            }
            Text("\(mainCount) set(s), \(subprojectCount) subproject(s)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - LiveSet List (Middle Column)

struct LiveSetListView: View {
    let projectPath: String

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedLiveSetPath },
            set: { UIState.shared.selectedLiveSetPath = $0 }
        )) {
            // Main Live Sets with dynamic sort
            MainLiveSetsSection(projectPath: projectPath, sortAscending: UIState.shared.liveSetSortOrder == .ascending)

            // Subprojects
            SubprojectLiveSetsSection(projectPath: projectPath)

            // Backups
            BackupLiveSetsSection(projectPath: projectPath)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
    }
}

/// Subview for main LiveSets with dynamic sort order via init
struct MainLiveSetsSection: View {
    @Query private var liveSets: [SDLiveSet]
    let projectPath: String

    init(projectPath: String, sortAscending: Bool) {
        self.projectPath = projectPath
        let mainCategory = SDLiveSetCategory.main.rawValue
        let predicate = #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == mainCategory
        }
        _liveSets = Query(
            filter: predicate,
            sort: [SortDescriptor(\SDLiveSet.path, order: sortAscending ? .forward : .reverse)]
        )
    }

    var body: some View {
        if !liveSets.isEmpty {
            Section {
                ForEach(liveSets, id: \.path) { liveSet in
                    LiveSetRowWithVersions(liveSet: liveSet)
                        .tag(liveSet.path)
                }
            } header: {
                HStack {
                    Text("Live Sets")
                    Spacer()
                    Button {
                        UIState.shared.liveSetSortOrder = UIState.shared.liveSetSortOrder == .ascending ? .descending : .ascending
                    } label: {
                        Image(systemName: UIState.shared.liveSetSortOrder == .ascending ? "arrow.up" : "arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(UIState.shared.liveSetSortOrder == .ascending ? "Sort Z-A" : "Sort A-Z")
                }
            }
        }
    }
}

/// Subview for subproject LiveSets
struct SubprojectLiveSetsSection: View {
    @Query private var liveSets: [SDLiveSet]

    init(projectPath: String) {
        let subprojectCategory = SDLiveSetCategory.subproject.rawValue
        let predicate = #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == subprojectCategory
        }
        _liveSets = Query(filter: predicate, sort: [SortDescriptor(\SDLiveSet.path)])
    }

    var body: some View {
        if !liveSets.isEmpty {
            Section("Subprojects") {
                ForEach(liveSets, id: \.path) { liveSet in
                    LiveSetRow(liveSet: liveSet)
                        .tag(liveSet.path)
                }
            }
        }
    }
}

/// Subview for backup LiveSets sorted by timestamp
struct BackupLiveSetsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var liveSets: [SDLiveSet]

    init(projectPath: String) {
        let backupCategory = SDLiveSetCategory.backup.rawValue
        let predicate = #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == backupCategory
        }
        _liveSets = Query(
            filter: predicate,
            sort: [SortDescriptor(\SDLiveSet.backupTimestamp, order: .reverse)]
        )
    }

    var body: some View {
        if !liveSets.isEmpty {
            Section("Backups (\(liveSets.count))") {
                ForEach(liveSets, id: \.path) { liveSet in
                    LiveSetRow(liveSet: liveSet)
                        .tag(liveSet.path)
                }
            }
        }
    }
}

/// LiveSet row with expandable versions
struct LiveSetRowWithVersions: View {
    let liveSet: SDLiveSet
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveSetRow(liveSet: liveSet, isExpandable: true, isExpanded: isExpanded) {
                isExpanded.toggle()
            }

            if isExpanded {
                VersionsSubview(parentPath: liveSet.path)
            }
        }
    }
}

/// Subview for version LiveSets of a parent
struct VersionsSubview: View {
    @Query private var versions: [SDLiveSet]

    init(parentPath: String) {
        let versionCategory = SDLiveSetCategory.version.rawValue
        let predicate = #Predicate<SDLiveSet> { liveSet in
            liveSet.categoryRaw == versionCategory && liveSet.parentLiveSetPath == parentPath
        }
        _versions = Query(filter: predicate, sort: [SortDescriptor(\SDLiveSet.path, order: .reverse)])
    }

    var body: some View {
        ForEach(versions, id: \.path) { version in
            VersionRow(version: version)
                .tag(version.path)
        }
    }
}

// MARK: - Row Views

struct LiveSetRow: View {
    let liveSet: SDLiveSet
    var isExpandable: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var showVersionDialog = false
    @State private var versionComment = ""

    private var versionCount: Int {
        let versionCategory = SDLiveSetCategory.version.rawValue
        let parentPath = liveSet.path
        let predicate = #Predicate<SDLiveSet> { ls in
            ls.categoryRaw == versionCategory && ls.parentLiveSetPath == parentPath
        }
        let descriptor = FetchDescriptor<SDLiveSet>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    var body: some View {
        HStack {
            // Expand/collapse chevron for main LiveSets with versions
            if isExpandable && versionCount > 0 {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                    .onTapGesture {
                        onToggleExpand?()
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
                if liveSet.category == .subproject, liveSet.hasMetadata {
                    Text("From: \(liveSet.sourceLiveSetName ?? "") → \(liveSet.sourceGroupName ?? "")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if isExpandable && versionCount > 0 {
                Text("(\(versionCount))")
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
        ProjectManager.shared.createVersion(of: liveSet, comment: comment)
    }

    private func openInAbleton() {
        let url = URL(fileURLWithPath: liveSet.path)
        NSWorkspace.shared.open(url)
    }

    private func iconForCategory(_ category: SDLiveSetCategory) -> String {
        switch category {
        case .main: return "doc.fill"
        case .subproject: return "doc.badge.gearshape.fill"
        case .version: return "clock.arrow.circlepath"
        case .backup: return "clock.fill"
        }
    }

    private func colorForCategory(_ category: SDLiveSetCategory) -> Color {
        switch category {
        case .main: return .blue
        case .subproject: return .purple
        case .version: return .orange
        case .backup: return .gray
        }
    }
}

struct VersionRow: View {
    let version: SDLiveSet

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

// MARK: - LiveSet Detail View

/// Wrapper to fetch LiveSet by path
struct LiveSetDetailWrapper: View {
    @Query private var liveSets: [SDLiveSet]

    init(liveSetPath: String) {
        let predicate = #Predicate<SDLiveSet> { $0.path == liveSetPath }
        _liveSets = Query(filter: predicate)
    }

    var body: some View {
        if let liveSet = liveSets.first {
            LiveSetDetailView(liveSet: liveSet)
        } else {
            Text("LiveSet not found")
                .foregroundColor(.secondary)
        }
    }
}

struct LiveSetDetailView: View {
    let liveSet: SDLiveSet

    private var isInspectorPresented: Binding<Bool> {
        Binding(
            get: { UIState.shared.isInspectorVisible },
            set: { UIState.shared.isInspectorVisible = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            LiveSetHeader(liveSet: liveSet)

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
                TrackListView(liveSetPath: liveSet.path)
            }
        }
        .inspector(isPresented: isInspectorPresented) {
            InspectorContent(liveSet: liveSet)
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
                    UIState.shared.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: UIState.shared.isInspectorVisible ? "info.circle.fill" : "info.circle")
                }
                .help(UIState.shared.isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .onChange(of: liveSet.path) { _, _ in
            UIState.shared.selectedTrackId = nil
        }
    }
}

struct LiveSetHeader: View {
    @Environment(\.modelContext) private var modelContext
    let liveSet: SDLiveSet

    private var groupCount: Int {
        let groupType = SDTrackType.group.rawValue
        let liveSetPath = liveSet.path
        let predicate = #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.typeRaw == groupType
        }
        let descriptor = FetchDescriptor<SDTrack>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    var body: some View {
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
                if liveSet.category == .subproject, liveSet.hasMetadata {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("From \(liveSet.sourceLiveSetName ?? "") → \(liveSet.sourceGroupName ?? "") (ID: \(liveSet.sourceGroupId ?? 0))")
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
                Text("\(groupCount) groups")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct InspectorContent: View {
    let liveSet: SDLiveSet
    @Query private var tracks: [SDTrack]

    init(liveSet: SDLiveSet) {
        self.liveSet = liveSet
        let selectedId = UIState.shared.selectedTrackId
        let liveSetPath = liveSet.path
        if let trackId = selectedId {
            let predicate = #Predicate<SDTrack> { track in
                track.liveSet?.path == liveSetPath && track.trackId == trackId
            }
            _tracks = Query(filter: predicate)
        } else {
            // No track selected - empty query
            let predicate = #Predicate<SDTrack> { _ in false }
            _tracks = Query(filter: predicate)
        }
    }

    var body: some View {
        if let selectedTrack = tracks.first {
            SDTrackInspectorView(track: selectedTrack)
        } else {
            SDLiveSetInspectorView(liveSet: liveSet)
        }
    }
}

// MARK: - Track List View

struct TrackListView: View {
    @Query private var rootTracks: [SDTrack]

    init(liveSetPath: String) {
        let predicate = #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.parentGroupId == nil
        }
        _rootTracks = Query(filter: predicate, sort: [SortDescriptor(\SDTrack.trackId)])
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rootTracks, id: \.trackId) { track in
                    SDTrackRow(track: track, depth: 0)
                }
            }
            .padding()
        }
    }
}

struct SDTrackRow: View {
    let track: SDTrack
    let depth: Int
    @State private var isExpanded = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var showError = false
    @State private var showOpenPrompt = false
    @State private var extractedPath: String?

    private var isSelected: Bool {
        UIState.shared.selectedTrackId == track.trackId
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
                UIState.shared.selectedTrackId = track.trackId
            }
            .contextMenu {
                if track.isGroup {
                    Button("Extract as Subproject") {
                        extractAsSubproject()
                    }
                    .disabled(isExtracting || track.liveSet?.project == nil)
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
                ChildTracksView(liveSetPath: track.liveSet?.path ?? "", parentGroupId: track.trackId, depth: depth + 1)
            }
        }
    }

    private func navigateToSubproject(path: String) {
        UIState.shared.selectedLiveSetPath = path
        UIState.shared.selectedTrackId = nil
    }

    private func extractAsSubproject() {
        guard let liveSet = track.liveSet,
              let project = liveSet.project else { return }

        let safeName = track.name.replacingOccurrences(of: "/", with: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = ".subproject-\(project.name)-\(safeName)-\(timestamp).als"
        let outputPath = URL(fileURLWithPath: project.path).appendingPathComponent(fileName).path

        isExtracting = true

        ProjectManager.shared.extractSubproject(
            from: liveSet.path,
            groupId: track.trackId,
            groupName: track.name,
            sourceLiveSetName: liveSet.name,
            to: outputPath,
            projectPath: project.path
        ) { result in
            DispatchQueue.main.async {
                isExtracting = false

                if let path = result {
                    print("Extracted subproject to: \(path)")
                    extractedPath = path
                    showOpenPrompt = true
                    ProjectManager.shared.rescanProject(projectPath: project.path)
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

    private func iconForTrackType(_ type: SDTrackType) -> String {
        switch type {
        case .audio: return "waveform"
        case .midi: return "pianokeys"
        case .group: return "folder.fill"
        case .returnTrack: return "arrow.turn.up.right"
        }
    }

    private func colorForTrackType(_ type: SDTrackType) -> Color {
        switch type {
        case .audio: return .orange
        case .midi: return .purple
        case .group: return .blue
        case .returnTrack: return .green
        }
    }
}

/// Subview to fetch child tracks with predicate
struct ChildTracksView: View {
    @Query private var children: [SDTrack]
    let depth: Int

    init(liveSetPath: String, parentGroupId: Int, depth: Int) {
        self.depth = depth
        let predicate = #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.parentGroupId == parentGroupId
        }
        _children = Query(filter: predicate, sort: [SortDescriptor(\SDTrack.trackId)])
    }

    var body: some View {
        ForEach(children, id: \.trackId) { child in
            SDTrackRow(track: child, depth: depth)
        }
    }
}

#Preview {
    ContentView()
}

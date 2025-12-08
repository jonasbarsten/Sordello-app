//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GRDB

struct ContentView: View {
    @State private var projectManager = ProjectManager.shared

    var body: some View {
        NavigationSplitView {
            ProjectListView()
        } content: {
            if let selectedPath = UIState.shared.selectedProjectPath,
               projectManager.openProjectPaths.contains(selectedPath) {
                LiveSetListView(projectPath: selectedPath)
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
    }
}

// MARK: - Project List (Sidebar)

struct ProjectListView: View {
    @State private var projectManager = ProjectManager.shared

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedProjectPath },
            set: { UIState.shared.selectedProjectPath = $0 }
        )) {
            if projectManager.openProjectPaths.isEmpty {
                Text("No projects opened")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(projectManager.getOpenProjects(), id: \.path) { project in
                    ProjectRow(project: project)
                        .tag(project.path)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }
}

struct ProjectRow: View {
    var project: Project
    @State private var mainCount: Int = 0
    @State private var subprojectCount: Int = 0

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
        .onAppear {
            fetchCounts()
        }
    }

    private func fetchCounts() {
        guard let projectDb = ProjectManager.shared.database(forProjectPath: project.path) else { return }
        do {
            let mainSets = try projectDb.fetchMainLiveSets()
            let subprojects = try projectDb.fetchSubprojectLiveSets()
            mainCount = mainSets.count
            subprojectCount = subprojects.count
        } catch {
            mainCount = 0
            subprojectCount = 0
        }
    }
}

// MARK: - LiveSet List (Content)

struct LiveSetListView: View {
    let projectPath: String
    @State private var mainLiveSets: [LiveSet] = []
    @State private var versions: [String: [LiveSet]] = [:]
    @State private var mainObservationTask: Task<Void, Never>?

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedLiveSetPath },
            set: { UIState.shared.selectedLiveSetPath = $0 }
        )) {
            Section("Live Sets") {
                ForEach(mainLiveSets, id: \.path) { liveSet in
                    LiveSetRow(liveSet: liveSet, versions: versions[liveSet.path] ?? [])
                        .tag(liveSet.path)
                }
            }

            SubprojectsSection(projectPath: projectPath)
            BackupsSection(projectPath: projectPath)
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Sort A-Z") {
                        UIState.shared.liveSetSortOrder = .ascending
                    }
                    Button("Sort Z-A") {
                        UIState.shared.liveSetSortOrder = .descending
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            mainObservationTask?.cancel()
        }
        .onChange(of: projectPath) { _, _ in
            startObserving()
        }
    }

    private func startObserving() {
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        mainObservationTask?.cancel()
        mainObservationTask = Task {
            let observation = projectDb.observeMainLiveSets()
            do {
                for try await fetched in observation.values(in: db) {
                    mainLiveSets = fetched.sorted { lhs, rhs in
                        if UIState.shared.liveSetSortOrder == .ascending {
                            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                        } else {
                            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                        }
                    }
                    // Load versions for each main LiveSet
                    await loadVersions(for: fetched, db: projectDb)
                }
            } catch {
                // Observation cancelled
            }
        }
    }

    private func loadVersions(for liveSets: [LiveSet], db: ProjectDatabase) async {
        var newVersions: [String: [LiveSet]] = [:]
        for liveSet in liveSets {
            do {
                let versionList = try db.fetchVersionLiveSets(forParentPath: liveSet.path)
                newVersions[liveSet.path] = versionList
            } catch {
                newVersions[liveSet.path] = []
            }
        }
        versions = newVersions
    }
}

struct LiveSetRow: View {
    let liveSet: LiveSet
    let versions: [LiveSet]
    @State private var trackCount: Int = 0
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        DisclosureGroup {
            ForEach(versions, id: \.path) { version in
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                    Text(version.name)
                    Spacer()
                }
                .padding(.leading, 16)
                .tag(version.path)
            }
        } label: {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(liveSet.name)
                    Text("\(trackCount) tracks • Live \(liveSet.liveVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            observationTask?.cancel()
        }
    }

    private func startObserving() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = projectDb.observeTracks(forLiveSetPath: liveSet.path)
            do {
                for try await tracks in observation.values(in: db) {
                    trackCount = tracks.count
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

struct SubprojectsSection: View {
    let projectPath: String
    @State private var subprojects: [LiveSet] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        if !subprojects.isEmpty {
            Section("Subprojects") {
                ForEach(subprojects, id: \.path) { subproject in
                    HStack {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading) {
                            Text(subproject.name)
                            if let groupName = subproject.sourceGroupName {
                                Text("From: \(groupName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tag(subproject.path)
                }
            }
        }
    }

    init(projectPath: String) {
        self.projectPath = projectPath
        _observationTask = State(initialValue: nil)
        _subprojects = State(initialValue: [])
    }

    var bodyWithTask: some View {
        body
            .onAppear {
                startObserving()
            }
            .onDisappear {
                observationTask?.cancel()
            }
    }

    private func startObserving() {
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try LiveSet
                    .filter(Column("projectPath") == projectPath)
                    .filter(Column("category") == LiveSetCategory.subproject.rawValue)
                    .order(Column("path"))
                    .fetchAll(db)
            }
            do {
                for try await fetched in observation.values(in: db) {
                    subprojects = fetched
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

struct BackupsSection: View {
    let projectPath: String
    @State private var backups: [LiveSet] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        if !backups.isEmpty {
            Section("Backups") {
                ForEach(backups, id: \.path) { backup in
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.gray)
                        VStack(alignment: .leading) {
                            Text(backup.name)
                            if let timestamp = backup.backupTimestamp {
                                Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tag(backup.path)
                }
            }
        }
    }

    init(projectPath: String) {
        self.projectPath = projectPath
        _observationTask = State(initialValue: nil)
        _backups = State(initialValue: [])
    }

    var bodyWithTask: some View {
        body
            .onAppear {
                startObserving()
            }
            .onDisappear {
                observationTask?.cancel()
            }
    }

    private func startObserving() {
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try LiveSet
                    .filter(Column("projectPath") == projectPath)
                    .filter(Column("category") == LiveSetCategory.backup.rawValue)
                    .order(Column("backupTimestamp").desc)
                    .fetchAll(db)
            }
            do {
                for try await fetched in observation.values(in: db) {
                    backups = fetched
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

// MARK: - LiveSet Detail (Detail)

struct LiveSetDetailWrapper: View {
    let liveSetPath: String
    @State private var liveSet: LiveSet?
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let liveSet = liveSet {
                LiveSetDetailView(liveSet: liveSet)
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            observationTask?.cancel()
        }
        .onChange(of: liveSetPath) { _, _ in
            startObserving()
        }
    }

    private func startObserving() {
        // Get project path from the liveSet path (parent directory)
        let projectPath = URL(fileURLWithPath: liveSetPath).deletingLastPathComponent().path

        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try LiveSet.fetchOne(db, key: liveSetPath)
            }
            do {
                for try await fetched in observation.values(in: db) {
                    liveSet = fetched
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

struct LiveSetDetailView: View {
    let liveSet: LiveSet
    @State private var rootTracks: [Track] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            // Track list
            List(selection: Binding(
                get: { UIState.shared.selectedTrackId },
                set: { UIState.shared.selectedTrackId = $0 }
            )) {
                ForEach(rootTracks, id: \.trackId) { track in
                    TrackRow(track: track, liveSetPath: liveSet.path)
                        .tag(track.trackId)
                }
            }
            .frame(minWidth: 300)

            // Inspector
            if UIState.shared.isInspectorVisible {
                InspectorContent(liveSet: liveSet)
                    .frame(minWidth: 250, maxWidth: 300)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIState.shared.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: UIState.shared.isInspectorVisible ? "sidebar.trailing" : "sidebar.trailing")
                }
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            observationTask?.cancel()
        }
        .onChange(of: liveSet.path) { _, _ in
            UIState.shared.selectedTrackId = nil
            startObserving()
        }
    }

    private func startObserving() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = projectDb.observeRootTracks(forLiveSetPath: liveSet.path)
            do {
                for try await tracks in observation.values(in: db) {
                    rootTracks = tracks
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

// MARK: - Track Row

struct TrackRow: View {
    var track: Track
    let liveSetPath: String
    @State private var isEditing: Bool = false
    @State private var editingText: String = ""
    @State private var isExpanded: Bool = false
    @State private var children: [Track] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Expand/collapse for groups
                if track.isGroup {
                    Button {
                        isExpanded.toggle()
                        if isExpanded && children.isEmpty {
                            loadChildren()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

                // Track icon
                Image(systemName: iconForTrackType(track.type))
                    .foregroundColor(colorForTrackType(track.type))

                // Editable name
                if isEditing {
                    TextField("Track name", text: $editingText, onCommit: {
                        commitNameChange()
                    })
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand {
                        isEditing = false
                        editingText = track.name
                    }
                } else {
                    Text(track.name)
                        .onTapGesture(count: 2) {
                            editingText = track.name
                            isEditing = true
                        }
                }

                Spacer()

                // Indicators
                if track.isModified {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                if track.subprojectPath != nil {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.purple)
                        .font(.caption)
                }

                if track.bounceReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)

            // Children (if expanded)
            if isExpanded && !children.isEmpty {
                ForEach(children, id: \.trackId) { child in
                    TrackRow(track: child, liveSetPath: liveSetPath)
                        .padding(.leading, 24)
                }
            }
        }
        .onAppear {
            if track.isGroup && isExpanded {
                loadChildren()
            }
        }
        .onDisappear {
            observationTask?.cancel()
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

    private func commitNameChange() {
        isEditing = false
        guard editingText != track.name else { return }

        // Get project path from liveSetPath
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

    private func loadChildren() {
        // Get project path from liveSetPath
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
}

// MARK: - Inspector Content

struct InspectorContent: View {
    let liveSet: LiveSet
    @State private var selectedTrack: Track?
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let selectedTrack = selectedTrack {
                TrackInspectorView(track: selectedTrack, liveSetPath: liveSet.path)
            } else {
                LiveSetInspectorView(liveSet: liveSet)
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            observationTask?.cancel()
        }
        .onChange(of: UIState.shared.selectedTrackId) { _, _ in
            startObserving()
        }
    }

    private func startObserving() {
        guard let trackId = UIState.shared.selectedTrackId,
              let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else {
            selectedTrack = nil
            return
        }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try Track
                    .filter(Column("liveSetPath") == liveSet.path)
                    .filter(Column("trackId") == trackId)
                    .fetchOne(db)
            }
            do {
                for try await track in observation.values(in: db) {
                    selectedTrack = track
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

// MARK: - Nested Track Row (for groups)

struct NestedTrackRow: View {
    let track: Track
    let liveSetPath: String
    let depth: Int
    @State private var isExpanded = false
    @State private var children: [Track] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Indentation
                Spacer().frame(width: CGFloat(depth * 16))

                // Expand/collapse for groups
                if track.isGroup {
                    Button {
                        isExpanded.toggle()
                        if isExpanded {
                            loadChildren()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }

                // Track icon
                Image(systemName: iconForTrackType(track.type))
                    .foregroundColor(colorForTrackType(track.type))

                Text(track.name)

                Spacer()
            }
            .padding(.vertical, 2)

            // Children
            if isExpanded {
                ForEach(children, id: \.trackId) { child in
                    NestedTrackRow(track: child, liveSetPath: liveSetPath, depth: depth + 1)
                }
            }
        }
        .onDisappear {
            observationTask?.cancel()
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
}

#Preview {
    ContentView()
}

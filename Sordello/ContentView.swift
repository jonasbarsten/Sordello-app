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
    @State private var allVersions: [LiveSet] = []
    @State private var expandedPaths: Set<String> = []
    @State private var mainObservationTask: Task<Void, Never>?
    @State private var versionsObservationTask: Task<Void, Never>?

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedLiveSetPath },
            set: { UIState.shared.selectedLiveSetPath = $0 }
        )) {
            // Main Live Sets section
            if !mainLiveSets.isEmpty {
                Section {
                    ForEach(mainLiveSets, id: \.path) { liveSet in
                        let versions = versionsFor(liveSet)
                        let hasVersions = !versions.isEmpty
                        let isExpanded = expandedPaths.contains(liveSet.path)

                        // Main liveset row
                        LiveSetMainRow(
                            liveSet: liveSet,
                            versionCount: versions.count,
                            isExpanded: isExpanded,
                            onToggleExpand: hasVersions ? { toggleExpanded(liveSet.path) } : nil,
                            latestVersionPath: versions.first?.path
                        )
                        .tag(liveSet.path)

                        // Expanded versions (if any)
                        if isExpanded && hasVersions {
                            ForEach(versions, id: \.path) { version in
                                VersionRow(version: version)
                                    .tag(version.path)
                            }

                            // Original at the bottom
                            OriginalLiveSetRow(liveSet: liveSet)
                                .tag("original-\(liveSet.path)")
                        }
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

            SubprojectsSection(projectPath: projectPath)
            BackupsSection(projectPath: projectPath)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        .onAppear {
            startObserving()
        }
        .onDisappear {
            mainObservationTask?.cancel()
            versionsObservationTask?.cancel()
        }
        .onChange(of: projectPath) { _, _ in
            startObserving()
        }
    }

    private func versionsFor(_ liveSet: LiveSet) -> [LiveSet] {
        allVersions.filter { $0.parentLiveSetPath == liveSet.path }
    }

    private func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    private func startObserving() {
        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        // Observe main LiveSets
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
                }
            } catch {
                // Observation cancelled
            }
        }

        // Observe all versions for this project
        versionsObservationTask?.cancel()
        versionsObservationTask = Task {
            let observation = ValueObservation.tracking { db in
                try LiveSet
                    .filter(Column("projectPath") == projectPath)
                    .filter(Column("category") == LiveSetCategory.version.rawValue)
                    .order(Column("path").desc)
                    .fetchAll(db)
            }
            do {
                for try await fetched in observation.values(in: db) {
                    allVersions = fetched
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

/// Main liveset row with custom expand/collapse
struct LiveSetMainRow: View {
    let liveSet: LiveSet
    let versionCount: Int
    let isExpanded: Bool
    var onToggleExpand: (() -> Void)?
    var latestVersionPath: String?

    @State private var showVersionDialog = false
    @State private var versionComment = ""
    @State private var isParsed = false

    private var isSelected: Bool {
        UIState.shared.selectedLiveSetPath == liveSet.path
    }

    var body: some View {
        HStack {
            // Expand/collapse chevron (only if has versions)
            if versionCount > 0 {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                    .onTapGesture {
                        onToggleExpand?()
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 12)
            }

            Image(systemName: "doc.fill")
                .foregroundColor(.blue)

            Text(liveSet.name)
                .lineLimit(1)

            if versionCount > 0 {
                Text("(\(versionCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Show spinner while parsing
            if !isParsed {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected && versionCount > 0 {
                // Second click on selected liveset with versions toggles expand/collapse
                onToggleExpand?()
            } else {
                UIState.shared.selectedLiveSetPath = liveSet.path
            }
        }
        .contextMenu {
            if versionCount > 0, let latestPath = latestVersionPath {
                Button("Open Latest Version in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: latestPath))
                }
                Button("Open Original in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
                }
            } else {
                Button("Open in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
                }
            }

            Divider()

            Button("Create Version...") {
                versionComment = ""
                showVersionDialog = true
            }
        }
        .alert("Create Version", isPresented: $showVersionDialog) {
            TextField("Comment (optional)", text: $versionComment)
            Button("Create") {
                ProjectManager.shared.createVersion(of: liveSet, comment: versionComment.isEmpty ? nil : versionComment)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add an optional comment to describe this version.")
        }
        .onAppear {
            isParsed = liveSet.isParsed
        }
    }
}

/// Row showing a version
struct VersionRow: View {
    let version: LiveSet

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

            Spacer()

            // Show spinner while parsing
            if !version.isParsed {
                ProgressView()
                    .controlSize(.mini)
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

/// Row showing the "Original" liveset at the bottom of versions list
struct OriginalLiveSetRow: View {
    let liveSet: LiveSet

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24)
            Image(systemName: "doc")
                .foregroundColor(.blue.opacity(0.6))
            Text("Original")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Show spinner while parsing
            if !liveSet.isParsed {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Ableton Live") {
                NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
            }
        }
    }
}

/// Generic row for subprojects
struct LiveSetRow: View {
    let liveSet: LiveSet

    var body: some View {
        HStack {
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

            Spacer()

            // Show spinner while parsing
            if !liveSet.isParsed {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Ableton Live") {
                NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
            }
        }
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

struct SubprojectsSection: View {
    let projectPath: String
    @State private var subprojects: [LiveSet] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if !subprojects.isEmpty {
                Section("Subprojects") {
                    ForEach(subprojects, id: \.path) { subproject in
                        LiveSetRow(liveSet: subproject)
                            .tag(subproject.path)
                    }
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
        Group {
            if !backups.isEmpty {
                Section("Backups (\(backups.count))") {
                    ForEach(backups, id: \.path) { backup in
                        LiveSetRow(liveSet: backup)
                            .tag(backup.path)
                    }
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
        // Handle "original-" prefix from OriginalLiveSetRow tag
        let actualPath = liveSetPath.hasPrefix("original-")
            ? String(liveSetPath.dropFirst("original-".count))
            : liveSetPath

        // Get project path from the liveSet path (parent directory)
        let projectPath = URL(fileURLWithPath: actualPath).deletingLastPathComponent().path

        guard let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else { return }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try LiveSet.fetchOne(db, key: actualPath)
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
            TrackListView(liveSet: liveSet)
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
    let liveSet: LiveSet
    @State private var groupCount: Int = 0
    @State private var modifiedCount: Int = 0

    // Save functionality state
    @State private var showSaveConfirmation = false
    @State private var savedPath: String?
    @State private var showOpenPrompt = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var isSaving = false

    private var hasUnsavedChanges: Bool {
        modifiedCount > 0
    }

    /// Parse subproject filename to extract metadata
    private var parsedSubprojectInfo: (projectName: String, groupName: String, timestamp: String)? {
        guard liveSet.category == .subproject else { return nil }

        let name = liveSet.name
        guard name.hasPrefix(".subproject-") else { return nil }

        let withoutPrefix = String(name.dropFirst(".subproject-".count))

        // Find timestamp at the end (format: YYYY-MM-DDTHH-MM-SS)
        let timestampPattern = #"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern),
              let match = regex.firstMatch(in: withoutPrefix, range: NSRange(withoutPrefix.startIndex..., in: withoutPrefix)),
              let timestampRange = Range(match.range, in: withoutPrefix) else {
            return nil
        }

        let timestamp = String(withoutPrefix[timestampRange])
        let beforeTimestamp = withoutPrefix[..<timestampRange.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Split remaining by last hyphen to get projectName-groupName
        if let lastHyphen = beforeTimestamp.lastIndex(of: "-") {
            let projectName = String(beforeTimestamp[..<lastHyphen])
            let groupName = String(beforeTimestamp[beforeTimestamp.index(after: lastHyphen)...])
            return (projectName, groupName, timestamp)
        }

        return (beforeTimestamp, "", timestamp)
    }

    /// Format timestamp from 2025-12-08T14-30-00 to readable format
    private func formatTimestamp(_ timestamp: String) -> String {
        let parts = timestamp.split(separator: "T")
        guard parts.count == 2 else { return timestamp }
        let date = parts[0]
        let time = parts[1].replacingOccurrences(of: "-", with: ":")
        return "\(date) \(time)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if liveSet.category == .subproject {
                    // Subproject header
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .foregroundColor(.purple)
                        Text("SUBPROJECT")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }

                    if let info = parsedSubprojectInfo {
                        Text(info.groupName.isEmpty ? info.projectName : info.groupName)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                Text(info.projectName)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            if !info.groupName.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                    Text(info.groupName)
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(formatTimestamp(info.timestamp))
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    } else if liveSet.hasMetadata {
                        // Fallback to stored metadata
                        Text(liveSet.sourceGroupName ?? liveSet.name)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.caption)
                                Text(liveSet.sourceLiveSetName ?? "Unknown")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            if let extractedAt = liveSet.extractedAt {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text(extractedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(liveSet.name)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                } else {
                    // Normal LiveSet header
                    Text(liveSet.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(liveSet.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving...")
                            .foregroundColor(.secondary)
                    }
                } else if hasUnsavedChanges {
                    Button {
                        showSaveConfirmation = true
                    } label: {
                        Label("Save to new Live Set", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save changes to a new version of this Live Set")
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
        .onAppear {
            fetchCounts()
        }
        .onChange(of: liveSet.path) { _, _ in
            fetchCounts()
        }
        .confirmationDialog("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Save to new Live Set") {
                saveChangesToNewLiveSet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will create a new version of the .als file with \(modifiedCount) renamed track\(modifiedCount == 1 ? "" : "s"). The original file will remain unchanged.")
        }
        .alert("Changes Saved", isPresented: $showOpenPrompt) {
            Button("Open in Ableton") {
                if let path = savedPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Would you like to open the new Live Set in Ableton Live?")
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    private func fetchCounts() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            groupCount = tracks.filter { $0.type == .group }.count
            modifiedCount = tracks.filter { $0.isModified }.count
        } catch {
            groupCount = 0
            modifiedCount = 0
        }
    }

    private func saveChangesToNewLiveSet() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else {
            saveError = "No project found for this Live Set"
            showSaveError = true
            return
        }

        isSaving = true

        // Collect track name changes: [trackId: newName]
        var nameChanges: [Int: String] = [:]
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            for track in tracks where track.isModified {
                nameChanges[track.trackId] = track.name
            }
        } catch {
            isSaving = false
            saveError = "Failed to fetch modified tracks"
            showSaveError = true
            return
        }

        // Generate output path as a version file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)  // Remove timezone
        let baseName = liveSet.name
        let outputFileName = ".version-\(baseName)-\(timestamp).als"
        let outputPath = (projectPath as NSString).appendingPathComponent(outputFileName)

        // Use AlsModifier to save changes
        let modifier = AlsModifier()
        let result = modifier.saveWithModifiedTrackNames(
            inputPath: liveSet.path,
            outputPath: outputPath,
            nameChanges: nameChanges
        )

        isSaving = false

        if result.success {
            savedPath = outputPath

            // Reparse the original LiveSet from disk to reset track state
            ProjectManager.shared.parseLiveSet(liveSet)

            // Navigate to the new version in the sidebar
            UIState.shared.selectedLiveSetPath = outputPath

            showOpenPrompt = true
        } else {
            saveError = result.error ?? "Unknown error"
            showSaveError = true
        }
    }
}

// MARK: - Track List View

struct TrackListView: View {
    let liveSet: LiveSet
    @State private var rootTracks: [Track] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if rootTracks.isEmpty {
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
                        ForEach(rootTracks, id: \.trackId) { track in
                            TrackRow(track: track, liveSetPath: liveSet.path, depth: 0)
                        }
                    }
                    .padding()
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

struct TrackRow: View {
    var track: Track
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
    @State private var children: [Track] = []
    @State private var observationTask: Task<Void, Never>?
    @FocusState private var isNameFieldFocused: Bool

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
                    UIState.shared.selectedTrackId = track.trackId
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

                if track.isGroup {
                    Divider()
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
        UIState.shared.selectedTrackId = nil
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

#Preview {
    ContentView()
}

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
    @Query private var allVersions: [SDLiveSet]
    let projectPath: String
    @State private var expandedPaths: Set<String> = []

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

        // Also fetch all versions for this project
        let versionCategory = SDLiveSetCategory.version.rawValue
        let versionPredicate = #Predicate<SDLiveSet> { liveSet in
            liveSet.project?.path == projectPath && liveSet.categoryRaw == versionCategory
        }
        _allVersions = Query(filter: versionPredicate, sort: [SortDescriptor(\SDLiveSet.path, order: .reverse)])
    }

    private func versionsFor(_ liveSet: SDLiveSet) -> [SDLiveSet] {
        allVersions.filter { $0.parentLiveSetPath == liveSet.path }
    }

    private func latestVersionPath(for liveSet: SDLiveSet) -> String {
        // Versions are sorted by path descending, so first is latest
        versionsFor(liveSet).first?.path ?? liveSet.path
    }

    var body: some View {
        if !liveSets.isEmpty {
            Section {
                ForEach(liveSets, id: \.path) { liveSet in
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
    }

    private func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
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

/// Main liveset row (simplified, without version expansion logic embedded)
struct LiveSetMainRow: View {
    let liveSet: SDLiveSet
    let versionCount: Int
    let isExpanded: Bool
    var onToggleExpand: (() -> Void)?
    var latestVersionPath: String?

    @State private var showVersionDialog = false
    @State private var versionComment = ""

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
            if !liveSet.isParsed {
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
    }
}

/// Row showing the "Original" liveset at the bottom of versions list
struct OriginalLiveSetRow: View {
    let liveSet: SDLiveSet

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

// MARK: - Row Views

/// Generic row for subprojects and backups (not main livesets)
struct LiveSetRow: View {
    let liveSet: SDLiveSet

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

// MARK: - LiveSet Detail View

/// Wrapper to fetch LiveSet by path
struct LiveSetDetailWrapper: View {
    @Query private var liveSets: [SDLiveSet]

    init(liveSetPath: String) {
        // Handle "original-" prefix from OriginalLiveSetRow tag
        let actualPath = liveSetPath.hasPrefix("original-")
            ? String(liveSetPath.dropFirst("original-".count))
            : liveSetPath

        let predicate = #Predicate<SDLiveSet> { $0.path == actualPath }
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

    // Query to observe modified tracks (triggers re-render when isModified changes)
    @Query private var modifiedTracks: [SDTrack]

    // Save functionality state
    @State private var showSaveConfirmation = false
    @State private var savedPath: String?
    @State private var showOpenPrompt = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var isSaving = false

    init(liveSet: SDLiveSet) {
        self.liveSet = liveSet
        // Query for tracks that are modified in this LiveSet
        let liveSetPath = liveSet.path
        let predicate = #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.isModified == true
        }
        _modifiedTracks = Query(filter: predicate)
    }

    private var hasUnsavedChanges: Bool {
        !modifiedTracks.isEmpty
    }

    private var groupCount: Int {
        let groupType = SDTrackType.group.rawValue
        let liveSetPath = liveSet.path
        let predicate = #Predicate<SDTrack> { track in
            track.liveSet?.path == liveSetPath && track.typeRaw == groupType
        }
        let descriptor = FetchDescriptor<SDTrack>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Parse subproject filename to extract metadata
    /// Format: .subproject-ProjectName-GroupName-2025-12-08T14-30-00.als
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

            // Save button (visible when there are unsaved changes)


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
        .confirmationDialog("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Save to new Live Set") {
                saveChangesToNewLiveSet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let count = modifiedTracks.count
            Text("This will create a new version of the .als file with \(count) renamed track\(count == 1 ? "" : "s"). The original file will remain unchanged.")
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

    private func saveChangesToNewLiveSet() {
        guard let project = liveSet.project else {
            saveError = "No project found for this Live Set"
            showSaveError = true
            return
        }

        isSaving = true

        // Collect track name changes: [trackId: newName]
        var nameChanges: [Int: String] = [:]
        for track in modifiedTracks {
            nameChanges[track.trackId] = track.name
        }

        // Generate output path as a version file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)  // Remove timezone
        let baseName = liveSet.name
        let outputFileName = ".version-\(baseName)-\(timestamp).als"
        let outputPath = (project.path as NSString).appendingPathComponent(outputFileName)

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
            // This ensures we stay in sync with the truth on disk
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
        _rootTracks = Query(filter: predicate, sort: [SortDescriptor(\SDTrack.sortIndex)])
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
    var track: SDTrack
    let depth: Int
    @State private var isExpanded = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var showError = false
    @State private var showOpenPrompt = false
    @State private var extractedPath: String?
    @State private var isEditingName = false
    @State private var editingText = ""  // Local state for TextField to avoid per-keystroke model updates
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
                            // Commit edit to model only on submit
                            track.name = editingText
                            track.isModified = (track.name != track.originalName)
                            isEditingName = false
                        }
                        .onExitCommand {
                            // Discard edit on escape
                            isEditingName = false
                        }
                } else {
                    Text(track.name)
                        .fontWeight(track.isGroup ? .medium : .regular)
                        .onTapGesture(count: 2) {
                            editingText = track.name  // Initialize with current name
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

                // DEBUG: Show sortIndex
//                Text(track.sortIndex)
//                    .font(.caption2)
//                    .foregroundColor(.orange)
//                    .padding(.horizontal, 4)
//                    .background(Color.orange.opacity(0.1))
//                    .cornerRadius(2)

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
                        track.name = track.originalName
                        track.isModified = false
                    }
                }

                if track.isGroup {
                    Divider()
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
        _children = Query(filter: predicate, sort: [SortDescriptor(\SDTrack.sortIndex)])
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

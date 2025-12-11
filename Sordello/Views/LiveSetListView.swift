//
//  LiveSetListView.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct LiveSetListView: View {
    let projectPath: String
    @Query<MainLiveSetsRequest> var mainLiveSets: [LiveSet]
    @Query<VersionLiveSetsRequest> var allVersions: [LiveSet]
    @Query<SubprojectLiveSetsRequest> var subprojects: [LiveSet]
    
    @Query<BackupLiveSetsRequest> var backups: [LiveSet]
    @State private var expandedPaths: Set<String> = []
    @State private var selection: String?

    init(projectPath: String) {
        self.projectPath = projectPath
        _mainLiveSets = Query(constant: MainLiveSetsRequest(projectPath: projectPath))
        _allVersions = Query(constant: VersionLiveSetsRequest(projectPath: projectPath))
        _subprojects = Query(constant: SubprojectLiveSetsRequest(projectPath: projectPath))
        _backups = Query(constant: BackupLiveSetsRequest(projectPath: projectPath))
        _selection = State(initialValue: UIState.shared.selectedLiveSetPath)
    }

    /// All LiveSets combined for lookup
    private var allLiveSets: [LiveSet] {
        mainLiveSets + allVersions + subprojects + backups
    }

    /// Find a LiveSet by path (handles "original-" prefix)
    private func findLiveSet(path: String?) -> LiveSet? {
        guard let path = path else { return nil }
        let actualPath = path.hasPrefix("original-")
            ? String(path.dropFirst("original-".count))
            : path
        return allLiveSets.first { $0.path == actualPath }
    }

    private var sortedMainLiveSets: [LiveSet] {
        mainLiveSets.sorted { lhs, rhs in
            if UIState.shared.liveSetSortOrder == .ascending {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            } else {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
    }

    /// Versions whose parent LiveSet no longer exists
    private var orphanVersions: [LiveSet] {
        let mainPaths = Set(mainLiveSets.map { $0.path })
        return allVersions.filter { version in
            guard let parentPath = version.parentLiveSetPath else { return true }
            return !mainPaths.contains(parentPath)
        }
    }

    var body: some View {
        List(selection: $selection) {
            // Main Live Sets section
            if !sortedMainLiveSets.isEmpty {
                Section {
                    ForEach(sortedMainLiveSets, id: \.path) { liveSet in
                        let versions = versionsFor(liveSet)
                        let hasVersions = !versions.isEmpty
                        let isExpanded = expandedPaths.contains(liveSet.path)

                        // Main liveset row
                        LiveSetMainRow(
                            liveSet: liveSet,
                            versionCount: versions.count,
                            isExpanded: isExpanded,
                            onToggleExpand: hasVersions ? { toggleExpanded(liveSet.path) } : nil,
                            onSelect: {
                                selection = liveSet.path  // Immediate visual update
                            },
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

            // Orphan versions (parent LiveSet deleted)
            if !orphanVersions.isEmpty {
                Section("Orphan Versions") {
                    ForEach(orphanVersions, id: \.path) { version in
                        VersionRow(version: version)
                            .tag(version.path)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        .onChange(of: selection) { _, newSelection in
            Task { @MainActor in
                UIState.shared.selectedLiveSet = findLiveSet(path: newSelection)
            }
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
}

#Preview {
    LiveSetListView(projectPath: "/Users/test/My Song Project")
}

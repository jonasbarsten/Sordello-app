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
    @State private var expandedPaths: Set<String> = []

    init(projectPath: String) {
        self.projectPath = projectPath
        _mainLiveSets = Query(constant: MainLiveSetsRequest(projectPath: projectPath))
        _allVersions = Query(constant: VersionLiveSetsRequest(projectPath: projectPath))
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

    var body: some View {
        List(selection: Binding(
            get: { UIState.shared.selectedLiveSetPath },
            set: { UIState.shared.selectedLiveSetPath = $0 }
        )) {
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

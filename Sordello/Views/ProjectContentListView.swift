//
//  LiveSetListView.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct ProjectContentListView: View {
    let projectPath: String
    @Binding var selection: LiveSet?

    @Query<MainLiveSetsRequest> var mainLiveSets: [LiveSet]
    @Query<VersionLiveSetsRequest> var allVersions: [LiveSet]
    @Query<SubprojectLiveSetsRequest> var subprojects: [LiveSet]
    @Query<BackupLiveSetsRequest> var backups: [LiveSet]

    @State private var expandedPaths: Set<String> = []
    @State private var sortAscending = true

    init(projectPath: String, selection: Binding<LiveSet?>) {
        self.projectPath = projectPath
        self._selection = selection
        _mainLiveSets = Query(constant: MainLiveSetsRequest(projectPath: projectPath))
        _allVersions = Query(constant: VersionLiveSetsRequest(projectPath: projectPath))
        _subprojects = Query(constant: SubprojectLiveSetsRequest(projectPath: projectPath))
        _backups = Query(constant: BackupLiveSetsRequest(projectPath: projectPath))
    }

    private var sortedMainLiveSets: [LiveSet] {
        mainLiveSets.sorted { lhs, rhs in
            if sortAscending {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            } else {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
    }

    private var orphanVersions: [LiveSet] {
        let mainPaths = Set(mainLiveSets.map { $0.path })
        return allVersions.filter { version in
            guard let parentPath = version.parentItemPath else { return true }
            return !mainPaths.contains(parentPath)
        }
    }

    var body: some View {
        List(selection: $selection) {
            if !sortedMainLiveSets.isEmpty {
                Section {
                    ForEach(sortedMainLiveSets, id: \.path) { liveSet in
                        let versions = versionsFor(liveSet)
                        let hasVersions = !versions.isEmpty
                        let isExpanded = expandedPaths.contains(liveSet.path)

                        LiveSetMainRow(
                            liveSet: liveSet,
                            versionCount: versions.count,
                            isExpanded: isExpanded,
                            onToggleExpand: hasVersions ? { toggleExpanded(liveSet.path) } : nil,
                            latestVersionPath: versions.first?.path
                        )
                        .tag(liveSet)

                        if isExpanded && hasVersions {
                            ForEach(versions, id: \.path) { version in
                                VersionRow(version: version)
                                    .tag(version)
                            }
                            OriginalLiveSetRow(liveSet: liveSet)
                                .tag(liveSet)
                        }
                    }
                } header: {
                    HStack {
                        Text("Live Sets")
                        Spacer()
                        Button {
                            sortAscending.toggle()
                        } label: {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SubprojectsSection(projectPath: projectPath)
            BackupsSection(projectPath: projectPath)

            if !orphanVersions.isEmpty {
                Section("Orphan Versions") {
                    ForEach(orphanVersions, id: \.path) { version in
                        VersionRow(version: version)
                            .tag(version)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
    }

    private func versionsFor(_ liveSet: LiveSet) -> [LiveSet] {
        allVersions.filter { $0.parentItemPath == liveSet.path }
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
    ProjectContentListView(projectPath: "/Users/test/My Song Project", selection: .constant(nil))
}

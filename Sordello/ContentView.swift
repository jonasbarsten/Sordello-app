//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import GRDBQuery

struct ContentView: View {
    @State private var selectedProjectPath: String?
    @State private var selectedLiveSet: LiveSet?

    var body: some View {
        NavigationSplitView {
            ProjectListView(selection: $selectedProjectPath)
        } content: {
            if let projectPath = selectedProjectPath,
               ProjectManager.shared.openProjectPaths.contains(projectPath),
               let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                LiveSetListView(projectPath: projectPath, selection: $selectedLiveSet)
                    .databaseContext(.readOnly { db })
            } else if selectedProjectPath != nil {
                ProgressView("Loading...")
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        } detail: {
            if let projectPath = selectedProjectPath,
               let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                NavigationStack {
                    if let liveSet = selectedLiveSet {
                        ProjectFileDetailView(liveSet: liveSet)
                    } else {
                        Text("Select a Live Set")
                            .foregroundColor(.secondary)
                    }
                }
                .databaseContext(.readOnly { db })
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
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
        }
        .frame(minWidth: 900, minHeight: 500)
        .onChange(of: ProjectManager.shared.openProjectPaths) { oldPaths, newPaths in
            if let newProject = newPaths.first(where: { !oldPaths.contains($0) }) {
                selectedProjectPath = newProject
            }
        }
        .onChange(of: selectedProjectPath) { _, _ in
            selectedLiveSet = nil
        }
    }
}

#Preview {
    ContentView()
}

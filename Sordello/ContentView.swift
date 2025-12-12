//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import GRDBQuery

struct ContentView: View {
    @State private var selectedProject: Project?
    @State private var selectedProjectContent: LiveSet?
    @State private var selectedFileSystemItem: LazyFileSystemItem?
    @State private var isInspectorVisible = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(selection: $selectedProject)
        } content: {
            if let projectPath = selectedProject?.path,
               ProjectManager.shared.openProjectPaths.contains(projectPath),
               let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                WholeTreeLazyTestView(projectPath: projectPath, selection: $selectedFileSystemItem)
//                ProjectContentListView(projectPath: projectPath, selection: $selectedProjectContent)
//                    .databaseContext(.readOnly { db })
            } else if selectedProject?.path != nil {
                ProgressView("Loading...")
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        } detail: {
            if let projectPath = selectedProject?.path,
               let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                NavigationStack {
//                    if let projectContent = selectedProjectContent {
//                        ProjectFileDetailView(liveSet: projectContent)
//                    } else {
//                        Text("Select a Live Set")
//                            .foregroundColor(.secondary)
//                    }
                    if let fileSystemItem = selectedFileSystemItem {
                        FileSystemItemDetailView(fileSystemItem: fileSystemItem)
                    } else {
                        Text("Select an item in the list")
                            .foregroundColor(.secondary)
                    }
                }
                .databaseContext(.readOnly { db })
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        }
        .inspector(isPresented: $isInspectorVisible) {
            if let projectContent = selectedProjectContent {
                LiveSetInspectorView(liveSet: projectContent)
            } else {
                Text("Select a Live Set")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        // Select a new project when it is loaded
        .onChange(of: ProjectManager.shared.openProjectPaths) { oldPaths, newPaths in
            if let newProjectPath = newPaths.first(where: { !oldPaths.contains($0) }) {
                selectedProject = ProjectManager.shared.getProject(byPath: newProjectPath)
            }
        }
        .onChange(of: selectedProject) { _, _ in
            selectedProjectContent = nil
            selectedFileSystemItem = nil
        }
        .navigationTitle(selectedProject?.name ?? "Sordello")
    }
}

#Preview {
    ContentView()
}

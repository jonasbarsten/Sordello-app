//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import GRDBQuery

struct ContentView: View {
    
    // Updated via .onChangeOf
    @State private var inspectorIsVisible = UIState.shared.isInspectorVisible

    var body: some View {
        NavigationSplitView {
            ProjectListView()
        } content: {
            if let selectedPath = UIState.shared.selectedProjectPath,
               ProjectManager.shared.openProjectPaths.contains(selectedPath),
               let db = ProjectManager.shared.database(forProjectPath: selectedPath)?.dbQueue {
                LiveSetListView(projectPath: selectedPath)
                    .databaseContext(.readOnly { db })
            } else if UIState.shared.selectedProjectPath != nil {
                // Project selected but database not ready yet
                ProgressView("Loading...")
            } else {
                Text("Select a project")
                    .foregroundColor(.secondary)
            }
        } detail: {
            if let selectedPath = UIState.shared.selectedLiveSetPath,
               let projectPath = UIState.shared.selectedProjectPath,
               let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                LiveSetDetailWrapper(liveSetPath: selectedPath)
                    .databaseContext(.readOnly { db })
            } else if UIState.shared.selectedLiveSetPath != nil {
                ProgressView("Loading...")
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No project selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Open a project to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Project...") {
                        ProjectManager.shared.openProject()
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
            }
        }
        .inspector(isPresented: $inspectorIsVisible) {
            InspectorContent()
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
                    Image(systemName: inspectorIsVisible ? "info.circle.fill" : "info.circle")
                }
                .help(inspectorIsVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .onChange(of: UIState.shared.isInspectorVisible, { _, newValue in
            inspectorIsVisible = newValue
        })
        .frame(minWidth: 900, minHeight: 500)
    }
}

#Preview {
    ContentView()
}

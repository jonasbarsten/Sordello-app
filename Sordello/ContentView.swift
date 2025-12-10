//
//  ContentView.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI
import GRDBQuery

struct ContentView: View {

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
            if let selectedPath = UIState.shared.selectedLiveSetPath {
                // Get the project path from the liveSet path (handle "original-" prefix)
                let actualPath = selectedPath.hasPrefix("original-")
                    ? String(selectedPath.dropFirst("original-".count))
                    : selectedPath
                let projectPath = URL(fileURLWithPath: actualPath).deletingLastPathComponent().path

                if let db = ProjectManager.shared.database(forProjectPath: projectPath)?.dbQueue {
                    LiveSetDetailWrapper(liveSetPath: selectedPath)
                        .databaseContext(.readOnly { db })
                } else {
                    ProgressView("Loading...")
                }
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
        .inspector(isPresented: Binding(
            get: { UIState.shared.isInspectorVisible },
            set: { UIState.shared.isInspectorVisible = $0 }
        )) {
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
                    Image(systemName: UIState.shared.isInspectorVisible ? "info.circle.fill" : "info.circle")
                }
                .help(UIState.shared.isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}

#Preview {
    ContentView()
}

//
//  ProjectListView.swift
//  Sordello
//

import SwiftUI

struct ProjectListView: View {
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            if ProjectManager.shared.openProjectPaths.isEmpty {
                Text("No projects opened")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(ProjectManager.shared.getOpenProjects(), id: \.path) { project in
                    ProjectRow(project: project)
                        .tag(project.path)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }
}

#Preview {
    ProjectListView(selection: .constant(nil))
}

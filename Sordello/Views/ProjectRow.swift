//
//  ProjectRow.swift
//  Sordello
//

import SwiftUI

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

#Preview {
    ProjectRow(project: Project(path: "/Users/test/My Song Project"))
}

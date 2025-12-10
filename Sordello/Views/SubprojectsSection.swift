//
//  SubprojectsSection.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct SubprojectsSection: View {
    let projectPath: String
    @Query<SubprojectLiveSetsRequest> var subprojects: [LiveSet]

    init(projectPath: String) {
        self.projectPath = projectPath
        _subprojects = Query(constant: SubprojectLiveSetsRequest(projectPath: projectPath))
    }

    var body: some View {
        Group {
            if !subprojects.isEmpty {
                Section("Subprojects") {
                    ForEach(subprojects, id: \.path) { subproject in
                        LiveSetRow(liveSet: subproject)
                            .tag(subproject.path)
                    }
                }
            }
        }
    }
}

#Preview {
    SubprojectsSection(projectPath: "/Users/test/My Song Project")
}

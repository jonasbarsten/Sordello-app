//
//  BackupsSection.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct BackupsSection: View {
    let projectPath: String
    @Query<BackupLiveSetsRequest> var backups: [LiveSet]

    init(projectPath: String) {
        self.projectPath = projectPath
        _backups = Query(constant: BackupLiveSetsRequest(projectPath: projectPath))
    }

    var body: some View {
        Group {
            if !backups.isEmpty {
                Section("Backups (\(backups.count))") {
                    ForEach(backups, id: \.path) { backup in
                        LiveSetRow(liveSet: backup)
                            .tag(backup.path)
                    }
                }
            }
        }
    }
}

#Preview {
    BackupsSection(projectPath: "/Users/test/My Song Project")
}

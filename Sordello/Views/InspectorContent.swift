//
//  InspectorContent.swift
//  Sordello
//

import SwiftUI
import GRDB

struct InspectorContent: View {
    let liveSet: LiveSet
    @State private var selectedTrack: Track?
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let selectedTrack = selectedTrack {
                TrackInspectorView(track: selectedTrack, liveSetPath: liveSet.path)
            } else {
                LiveSetInspectorView(liveSet: liveSet)
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            observationTask?.cancel()
        }
        .onChange(of: UIState.shared.selectedTrackId) { _, _ in
            startObserving()
        }
    }

    private func startObserving() {
        guard let trackId = UIState.shared.selectedTrackId,
              let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath),
              let db = projectDb.dbQueue else {
            selectedTrack = nil
            return
        }

        observationTask?.cancel()
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try Track
                    .filter(Column("liveSetPath") == liveSet.path)
                    .filter(Column("trackId") == trackId)
                    .fetchOne(db)
            }
            do {
                for try await track in observation.values(in: db) {
                    selectedTrack = track
                }
            } catch {
                // Observation cancelled
            }
        }
    }
}

#Preview {
    InspectorContent(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

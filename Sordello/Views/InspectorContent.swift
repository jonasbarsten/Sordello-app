//
//  InspectorContent.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct InspectorContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let path = appState.selectedLiveSetPath {
                // Use child view with @Query - new instance created when path changes
                InspectorContentInner(liveSetPath: path, selectedTrack: appState.selectedTrack)
            } else {
                VStack {
                    Spacer()
                    Text("No Live Set selected")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

/// Inner view that creates its own @Query based on the path
private struct InspectorContentInner: View {
    let selectedTrack: LiveSetTrack?
    @Query<SingleLiveSetRequest> var liveSet: LiveSet?

    init(liveSetPath: String, selectedTrack: LiveSetTrack?) {
        self.selectedTrack = selectedTrack
        _liveSet = Query(constant: SingleLiveSetRequest(path: liveSetPath))
    }

    var body: some View {
        Group {
            if let track = selectedTrack,
               let liveSet = liveSet {
                TrackInspectorView(track: track, liveSetPath: liveSet.path, projectPath: liveSet.projectPath)
            } else if let liveSet = liveSet {
                LiveSetInspectorView(liveSet: liveSet)
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    InspectorContent()
        .environment(AppState())
}

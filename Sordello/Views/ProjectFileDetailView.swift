//
//  LiveSetDetailView.swift
//  Sordello
//

import SwiftUI

struct ProjectFileDetailView: View {
    @Environment(AppState.self) private var appState
    let liveSet: LiveSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ProjectFileHeader(liveSet: liveSet)
            
            Divider()
            
            // Content
            TrackListView(liveSet: liveSet)
        }
        .onChange(of: liveSet.path) { _, _ in
            appState.selectedTrack = nil
            }
    }
}

#Preview {
    ProjectFileDetailView(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
        .environment(AppState())
}

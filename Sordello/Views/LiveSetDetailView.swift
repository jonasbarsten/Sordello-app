//
//  LiveSetDetailView.swift
//  Sordello
//

import SwiftUI

struct LiveSetDetailView: View {
    let liveSet: LiveSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            LiveSetHeader(liveSet: liveSet)

            Divider()

            // Content
            TrackListView(liveSet: liveSet)
        }
        .onChange(of: liveSet.path) { _, _ in
            UIState.shared.selectedTrack = nil
        }
    }
}

#Preview {
    LiveSetDetailView(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

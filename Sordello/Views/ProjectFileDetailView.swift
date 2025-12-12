//
//  LiveSetDetailView.swift
//  Sordello
//

import SwiftUI

struct ProjectFileDetailView: View {
    let liveSet: LiveSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ProjectFileHeader(liveSet: liveSet)

            Divider()

            // Content
            TrackListView(liveSet: liveSet)
        }
    }
}

#Preview {
    ProjectFileDetailView(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

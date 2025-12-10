//
//  TrackListView.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct TrackListView: View {
    let liveSet: LiveSet
    @Query<RootTracksRequest> var rootTracks: [LiveSetTrack]

    init(liveSet: LiveSet) {
        self.liveSet = liveSet
        _rootTracks = Query(constant: RootTracksRequest(liveSetPath: liveSet.path))
    }

    var body: some View {
        Group {
            if rootTracks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text("Loading track structure...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootTracks, id: \.trackId) { track in
                            TrackRow(track: track, liveSetPath: liveSet.path, depth: 0)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    TrackListView(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

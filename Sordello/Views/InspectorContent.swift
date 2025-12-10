//
//  InspectorContent.swift
//  Sordello
//

import SwiftUI
import GRDB

struct InspectorContent: View {
    var body: some View {
        Group {
            if let track = UIState.shared.selectedTrack,
               let liveSet = UIState.shared.selectedLiveSet {
                TrackInspectorView(track: track, liveSetPath: liveSet.path)
            } else if let liveSet = UIState.shared.selectedLiveSet {
                LiveSetInspectorView(liveSet: liveSet)
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

#Preview {
    InspectorContent()
}

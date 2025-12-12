//
//  LiveSetDetailWrapper.swift
//  Sordello
//

import SwiftUI
import GRDB
import GRDBQuery

struct LiveSetDetailWrapper: View {
    let liveSetPath: String
    @Query<SingleLiveSetRequest> var liveSet: LiveSet?

    init(liveSetPath: String) {
        // Handle "original-" prefix from OriginalLiveSetRow tag
        let actualPath = liveSetPath.hasPrefix("original-")
            ? String(liveSetPath.dropFirst("original-".count))
            : liveSetPath

        self.liveSetPath = actualPath
        _liveSet = Query(constant: SingleLiveSetRequest(path: actualPath))
    }

    var body: some View {
        Group {
            if let liveSet = liveSet {
                ProjectFileDetailView(liveSet: liveSet)
            } else {
                ProgressView("Loading...")
            }
        }
    }
}

#Preview {
    LiveSetDetailWrapper(liveSetPath: "/test/My Song.als")
}

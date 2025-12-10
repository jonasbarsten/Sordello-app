//
//  LiveSetDetailView.swift
//  Sordello
//

import SwiftUI

struct LiveSetDetailView: View {
    let liveSet: LiveSet

    private var isInspectorPresented: Binding<Bool> {
        Binding(
            get: { UIState.shared.isInspectorVisible },
            set: { UIState.shared.isInspectorVisible = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            LiveSetHeader(liveSet: liveSet)

            Divider()

            // Content
            TrackListView(liveSet: liveSet)
        }
        .inspector(isPresented: isInspectorPresented) {
            InspectorContent(liveSet: liveSet)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ProjectManager.shared.openProject()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Open Project...")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIState.shared.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: UIState.shared.isInspectorVisible ? "info.circle.fill" : "info.circle")
                }
                .help(UIState.shared.isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .onChange(of: liveSet.path) { _, _ in
            UIState.shared.selectedTrackId = nil
        }
    }
}

#Preview {
    LiveSetDetailView(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

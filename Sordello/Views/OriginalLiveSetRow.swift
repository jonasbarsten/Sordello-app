//
//  OriginalLiveSetRow.swift
//  Sordello
//

import SwiftUI
import AppKit

struct OriginalLiveSetRow: View {
    let liveSet: LiveSet

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24)
            Image(systemName: "doc")
                .foregroundColor(.blue.opacity(0.6))
            Text("Original")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Show spinner while parsing
            if !liveSet.isParsed {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .contextMenu {
            Button("Open in Ableton Live") {
                NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
            }
        }
    }
}

#Preview {
    OriginalLiveSetRow(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

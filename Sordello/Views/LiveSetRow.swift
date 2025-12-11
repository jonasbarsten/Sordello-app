//
//  LiveSetRow.swift
//  Sordello
//

import SwiftUI
import AppKit

struct LiveSetRow: View {
    let liveSet: LiveSet

    var body: some View {
        HStack {
            Image(systemName: iconForCategory(liveSet.category))
                .foregroundColor(colorForCategory(liveSet.category))

            VStack(alignment: .leading, spacing: 2) {
                Text(liveSet.name)
                    .lineLimit(1)

                // Show source info for subprojects with metadata
                if liveSet.category == .liveSetTrackVersion, liveSet.hasMetadata {
                    Text("From: \(liveSet.sourceLiveSetName ?? "") → \(liveSet.sourceGroupName ?? "")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Show spinner while parsing
            if !liveSet.isParsed {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Ableton Live") {
                NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
            }

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(liveSet.path, inFileViewerRootedAtPath: "")
            }
        }
    }

    private func iconForCategory(_ category: FileCategory) -> String {
        switch category {
        case .main: return "doc.fill"
        case .liveSetTrackVersion: return "doc.badge.gearshape.fill"
        case .version: return "clock.arrow.circlepath"
        case .backup: return "clock.fill"
        }
    }

    private func colorForCategory(_ category: FileCategory) -> Color {
        switch category {
        case .main: return .blue
        case .liveSetTrackVersion: return .purple
        case .version: return .orange
        case .backup: return .gray
        }
    }
}

#Preview("Main") {
    LiveSetRow(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

#Preview("Subproject") {
    var subproject = LiveSet(path: "/test/.sordello/My Song/subprojects/Drums-2025-12-09T14-30-00.als", category: .liveSetTrackVersion)
    subproject.sourceLiveSetName = "My Song"
    subproject.sourceGroupName = "Drums"
    subproject.sourceGroupId = 15
    return LiveSetRow(liveSet: subproject)
}

#Preview("Backup") {
    LiveSetRow(liveSet: LiveSet(path: "/test/Backup/My Song [2025-12-09 143000].als", category: .backup))
}

//
//  LiveSetMainRow.swift
//  Sordello
//

import SwiftUI
import AppKit

struct LiveSetMainRow: View {
    let liveSet: LiveSet
    let versionCount: Int
    let isExpanded: Bool
    var onToggleExpand: (() -> Void)?
    var onSelect: (() -> Void)?
    var latestVersionPath: String?

    private var isSelected: Bool {
        UIState.shared.selectedLiveSetPath == liveSet.path
    }

    var body: some View {
        HStack {
            // Expand/collapse chevron (only if has versions)
            if versionCount > 0 {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                    .onTapGesture {
                        onToggleExpand?()
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 12)
            }

            Image(systemName: "doc.fill")
                .foregroundColor(.blue)

            Text(liveSet.name)
                .lineLimit(1)

            if versionCount > 0 {
                Text("(\(versionCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Show spinner while parsing
            if !liveSet.isParsed {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected && versionCount > 0 {
                // Second click on selected liveset with versions toggles expand/collapse
                onToggleExpand?()
            } else {
                onSelect?()
            }
        }
        .contextMenu {
            if versionCount > 0, let latestPath = latestVersionPath {
                Button("Open Latest Version in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: latestPath))
                }
                Button("Open Original in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
                }
            } else {
                Button("Open in Ableton Live") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: liveSet.path))
                }
            }

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(liveSet.path, inFileViewerRootedAtPath: "")
            }

            Divider()

            Button("Create Version") {
                ProjectManager.shared.createVersion(of: liveSet)
            }
        }
    }
}

#Preview("With Versions") {
    LiveSetMainRow(
        liveSet: LiveSet(path: "/test/My Song.als", category: .main),
        versionCount: 3,
        isExpanded: false
    )
}

#Preview("No Versions") {
    LiveSetMainRow(
        liveSet: LiveSet(path: "/test/My Song.als", category: .main),
        versionCount: 0,
        isExpanded: false
    )
}

//
//  VersionRow.swift
//  Sordello
//

import SwiftUI
import AppKit

struct VersionRow: View {
    let version: LiveSet

    var body: some View {
        HStack(alignment: .top) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24)
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatVersionName(version.name))
                    .font(.caption)
                    .lineLimit(1)
                if let comment = version.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Show spinner while parsing
            if !version.isParsed {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .contextMenu {
            Button("Open in Ableton Live") {
                let url = URL(fileURLWithPath: version.path)
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func formatVersionName(_ name: String) -> String {
        if let range = name.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}"#, options: .regularExpression) {
            var timestamp = String(name[range])
            timestamp = timestamp.replacingOccurrences(of: "T", with: " ")
            let parts = timestamp.split(separator: " ")
            if parts.count == 2 {
                let date = parts[0]
                let time = parts[1].replacingOccurrences(of: "-", with: ":")
                let timeParts = time.split(separator: ":")
                if timeParts.count >= 2 {
                    return "\(date) \(timeParts[0]):\(timeParts[1])"
                }
            }
        }
        return name
    }
}

#Preview {
    var version = LiveSet(path: "/test/.sordello/My Song/versions/2025-12-09T14-30-00.als", category: .version)
    version.comment = "Added new drums"
    return VersionRow(version: version)
}

//
//  FileSystemItemDetailView.swift
//  Sordello
//
//  Created by Jonas Barsten on 12/12/2025.
//

import SwiftUI

struct FileSystemItemDetailView: View {
    let fileSystemItem: LazyFileSystemItem

    var body: some View {
        if fileSystemItem.isAlsFile {
            // Show LiveSet detail view for .als files
            LiveSetDetailWrapper(liveSetPath: fileSystemItem.path)
        } else {
            // Show generic file info for other files
            GenericFileDetailView(fileSystemItem: fileSystemItem)
        }
    }
}

/// Generic detail view for non-.als files
private struct GenericFileDetailView: View {
    let fileSystemItem: LazyFileSystemItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: fileSystemItem.isDirectory ? "folder.fill" : iconName)
                    .font(.largeTitle)
                    .foregroundColor(iconColor)

                VStack(alignment: .leading) {
                    Text(fileSystemItem.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(fileSystemItem.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Info
            GroupBox("Details") {
                LabeledContent("Type", value: fileSystemItem.isDirectory ? "Directory" : "File")
                if !fileSystemItem.isDirectory {
                    LabeledContent("Extension", value: fileSystemItem.fileExtension.uppercased())
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle(fileSystemItem.name)
    }

    private var iconName: String {
        switch fileSystemItem.fileExtension {
        case "als":
            return "doc.fill"
        case "wav", "aif", "aiff", "mp3", "flac", "ogg":
            return "waveform"
        case "mid", "midi":
            return "pianokeys"
        default:
            return "doc"
        }
    }

    private var iconColor: Color {
        if fileSystemItem.isDirectory {
            return .blue
        }
        switch fileSystemItem.fileExtension {
        case "als":
            return .orange
        case "wav", "aif", "aiff", "mp3", "flac", "ogg":
            return .green
        case "mid", "midi":
            return .purple
        default:
            return .secondary
        }
    }
}

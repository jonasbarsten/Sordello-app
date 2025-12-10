//
//  LiveSetHeader.swift
//  Sordello
//

import SwiftUI
import AppKit

struct LiveSetHeader: View {
    let liveSet: LiveSet
    @State private var groupCount: Int = 0
    @State private var modifiedCount: Int = 0

    // Save functionality state
    @State private var showSaveConfirmation = false
    @State private var savedPath: String?
    @State private var showOpenPrompt = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var isSaving = false

    private var hasUnsavedChanges: Bool {
        modifiedCount > 0
    }

    /// Parse subproject filename to extract metadata
    private var parsedSubprojectInfo: (projectName: String, groupName: String, timestamp: String)? {
        guard liveSet.category == .subproject else { return nil }

        let name = liveSet.name
        guard name.hasPrefix(".subproject-") else { return nil }

        let withoutPrefix = String(name.dropFirst(".subproject-".count))

        // Find timestamp at the end (format: YYYY-MM-DDTHH-MM-SS)
        let timestampPattern = #"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern),
              let match = regex.firstMatch(in: withoutPrefix, range: NSRange(withoutPrefix.startIndex..., in: withoutPrefix)),
              let timestampRange = Range(match.range, in: withoutPrefix) else {
            return nil
        }

        let timestamp = String(withoutPrefix[timestampRange])
        let beforeTimestamp = withoutPrefix[..<timestampRange.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Split remaining by last hyphen to get projectName-groupName
        if let lastHyphen = beforeTimestamp.lastIndex(of: "-") {
            let projectName = String(beforeTimestamp[..<lastHyphen])
            let groupName = String(beforeTimestamp[beforeTimestamp.index(after: lastHyphen)...])
            return (projectName, groupName, timestamp)
        }

        return (beforeTimestamp, "", timestamp)
    }

    /// Format timestamp from 2025-12-08T14-30-00 to readable format
    private func formatTimestamp(_ timestamp: String) -> String {
        let parts = timestamp.split(separator: "T")
        guard parts.count == 2 else { return timestamp }
        let date = parts[0]
        let time = parts[1].replacingOccurrences(of: "-", with: ":")
        return "\(date) \(time)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if liveSet.category == .subproject {
                    // Subproject header
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .foregroundColor(.purple)
                        Text("SUBPROJECT")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }

                    if let info = parsedSubprojectInfo {
                        Text(info.groupName.isEmpty ? info.projectName : info.groupName)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                Text(info.projectName)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            if !info.groupName.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                    Text(info.groupName)
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(formatTimestamp(info.timestamp))
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    } else if liveSet.hasMetadata {
                        // Fallback to stored metadata
                        Text(liveSet.sourceGroupName ?? liveSet.name)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.caption)
                                Text(liveSet.sourceLiveSetName ?? "Unknown")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            if let extractedAt = liveSet.extractedAt {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text(extractedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(liveSet.name)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                } else {
                    // Normal LiveSet header
                    Text(liveSet.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(liveSet.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving...")
                            .foregroundColor(.secondary)
                    }
                } else if hasUnsavedChanges {
                    Button {
                        showSaveConfirmation = true
                    } label: {
                        Label("Save to new Live Set", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save changes to a new version of this Live Set")
                }
            }
            Spacer()

            VStack(alignment: .trailing) {
                Text("Ableton Live \(liveSet.liveVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(groupCount) groups")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            fetchCounts()
        }
        .onChange(of: liveSet.path) { _, _ in
            fetchCounts()
        }
        .confirmationDialog("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Save to new Live Set") {
                saveChangesToNewLiveSet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will create a new version of the .als file with \(modifiedCount) renamed track\(modifiedCount == 1 ? "" : "s"). The original file will remain unchanged.")
        }
        .alert("Changes Saved", isPresented: $showOpenPrompt) {
            Button("Open in Ableton") {
                if let path = savedPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Would you like to open the new Live Set in Ableton Live?")
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    private func fetchCounts() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else { return }
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            groupCount = tracks.filter { $0.type == .group }.count
            modifiedCount = tracks.filter { $0.isModified }.count
        } catch {
            groupCount = 0
            modifiedCount = 0
        }
    }

    private func saveChangesToNewLiveSet() {
        guard let projectPath = liveSet.projectPath,
              let projectDb = ProjectManager.shared.database(forProjectPath: projectPath) else {
            saveError = "No project found for this Live Set"
            showSaveError = true
            return
        }

        isSaving = true

        // Collect track name changes: [trackId: newName]
        var nameChanges: [Int: String] = [:]
        do {
            let tracks = try projectDb.fetchTracks(forLiveSetPath: liveSet.path)
            for track in tracks where track.isModified {
                nameChanges[track.trackId] = track.name
            }
        } catch {
            isSaving = false
            saveError = "Failed to fetch modified tracks"
            showSaveError = true
            return
        }

        // Generate output path as a version file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)  // Remove timezone
        let baseName = liveSet.name
        let outputFileName = ".version-\(baseName)-\(timestamp).als"
        let outputPath = (projectPath as NSString).appendingPathComponent(outputFileName)

        // Use AlsModifier to save changes
        let modifier = AlsModifier()
        let result = modifier.saveWithModifiedTrackNames(
            inputPath: liveSet.path,
            outputPath: outputPath,
            nameChanges: nameChanges
        )

        isSaving = false

        if result.success {
            savedPath = outputPath

            // Reparse the original LiveSet from disk to reset track state
            ProjectManager.shared.parseLiveSet(liveSet)

            // Navigate to the new version in the sidebar
            UIState.shared.selectedLiveSetPath = outputPath

            showOpenPrompt = true
        } else {
            saveError = result.error ?? "Unknown error"
            showSaveError = true
        }
    }
}

#Preview("Main LiveSet") {
    LiveSetHeader(liveSet: LiveSet(path: "/test/My Song.als", category: .main))
}

#Preview("Subproject") {
    LiveSetHeader(liveSet: LiveSet(path: "/test/.subproject-My Song-Drums-2025-12-09T14-30-00.als", category: .subproject))
}

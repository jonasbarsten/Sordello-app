//
//  WholeTreeTestView.swift
//  Sordello
//
//  Proof of concept: Display the entire file tree hierarchy of a project directory.
//  This view scans the file system directly without using the database.
//
//  Created by Jonas Barsten on 12/12/2025.
//

import SwiftUI

// MARK: - File System Item Model

/// Represents a file or directory in the file system
struct FileSystemItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [FileSystemItem]?

    /// File extension (empty for directories)
    var fileExtension: String {
        guard !isDirectory else { return "" }
        return URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    /// Whether this is an .als file
    var isAlsFile: Bool {
        fileExtension == "als"
    }

    /// Whether this is a hidden file/directory (starts with ".")
    var isHidden: Bool {
        name.hasPrefix(".")
    }
}

// MARK: - File Tree Scanner

/// Scans a directory and builds a tree of FileSystemItems
struct FileTreeScanner {

    /// Scan a directory recursively and return a tree structure
    /// - Parameters:
    ///   - url: The directory URL to scan
    ///   - includeHidden: Whether to include hidden files/directories
    ///   - maxDepth: Maximum recursion depth (nil for unlimited)
    /// - Returns: Array of FileSystemItems at the root level
    static func scan(
        at url: URL,
        includeHidden: Bool = false,
        maxDepth: Int? = nil
    ) -> [FileSystemItem] {
        return scanDirectory(at: url, includeHidden: includeHidden, currentDepth: 0, maxDepth: maxDepth)
    }

    private static func scanDirectory(
        at url: URL,
        includeHidden: Bool,
        currentDepth: Int,
        maxDepth: Int?
    ) -> [FileSystemItem] {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [FileSystemItem] = []

        for itemUrl in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = itemUrl.lastPathComponent

            // Skip hidden if not including them (double check)
            if !includeHidden && name.hasPrefix(".") {
                continue
            }

            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemUrl.path, isDirectory: &isDir)

            let children: [FileSystemItem]?
            if isDir.boolValue {
                // Check depth limit
                if let max = maxDepth, currentDepth >= max {
                    children = nil  // Don't recurse further
                } else {
                    children = scanDirectory(
                        at: itemUrl,
                        includeHidden: includeHidden,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth
                    )
                }
            } else {
                children = nil
            }

            let item = FileSystemItem(
                name: name,
                path: itemUrl.path,
                isDirectory: isDir.boolValue,
                children: children
            )

            items.append(item)
        }

        return items
    }
}

// MARK: - Tree Row View

/// A single row in the file tree
struct FileTreeRow: View {
    let item: FileSystemItem
    let depth: Int

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indentation
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16)
                }

                // Expand/collapse chevron for directories
                if item.isDirectory {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }

                // Icon
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                // Name
                Text(item.name)
                    .font(.system(.body, design: .default))
                    .foregroundColor(item.isHidden ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                // File extension badge for non-directories
                if !item.isDirectory && !item.fileExtension.isEmpty {
                    Text(item.fileExtension.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(item.isAlsFile ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                        .foregroundColor(item.isAlsFile ? .orange : .secondary)
                        .cornerRadius(3)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Children (if expanded)
            if isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeRow(item: child, depth: depth + 1)
                }
            }
        }
    }

    private var iconName: String {
        if item.isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }

        switch item.fileExtension {
        case "als":
            return "doc.fill"
        case "wav", "aif", "aiff", "mp3", "flac", "ogg":
            return "waveform"
        case "mid", "midi":
            return "pianokeys"
        case "txt", "md":
            return "doc.text"
        case "json", "xml":
            return "curlybraces"
        default:
            return "doc"
        }
    }

    private var iconColor: Color {
        if item.isDirectory {
            return .blue
        }

        switch item.fileExtension {
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

// MARK: - Main View

/// Displays the entire file tree of a project directory
struct WholeTreeTestView: View {
    let projectPath: String

    @State private var items: [FileSystemItem] = []
    @State private var includeHidden = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("File Tree")
                    .font(.headline)

                Spacer()

                Toggle("Show Hidden", isOn: $includeHidden)
                    .toggleStyle(.checkbox)
                    .onChange(of: includeHidden) { _, _ in
                        loadTree()
                    }

                Button {
                    loadTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Tree content
            if isLoading {
                ProgressView("Scanning...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Files Found",
                    systemImage: "folder",
                    description: Text("The project folder is empty")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            FileTreeRow(item: item, depth: 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadTree()
        }
    }

    private func loadTree() {
        isLoading = true

        // Load in background to not block UI
        Task {
            let url = URL(fileURLWithPath: projectPath)
            let scannedItems = FileTreeScanner.scan(at: url, includeHidden: includeHidden)

            await MainActor.run {
                items = scannedItems
                isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WholeTreeTestView(projectPath: "/Users/jonasbarsten/Development/Sordello")
        .frame(width: 400, height: 600)
}

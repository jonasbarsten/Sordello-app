//
//  WholeTreeLazyTestView.swift
//  Sordello
//
//  Proof of concept: Lazy-loading file tree.
//  Children are only loaded when a directory is expanded.
//
//  Compare with WholeTreeTestView.swift which loads everything upfront.
//
//  Created by Jonas Barsten on 12/12/2025.
//

import SwiftUI

// MARK: - Lazy File System Item

/// Represents a file or directory with lazy-loaded children
@Observable
class LazyFileSystemItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool

    /// Children - nil means not loaded yet, empty array means loaded but no children
    var children: [LazyFileSystemItem]?

    /// Whether this directory is expanded in the UI (stored here to persist with cache)
    var isExpanded = false

    /// Whether children have been loaded
    var isLoaded: Bool { children != nil }

    /// File extension (empty for directories)
    var fileExtension: String {
        guard !isDirectory else { return "" }
        return URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    /// Whether this is an .als file
    var isAlsFile: Bool {
        fileExtension == "als"
    }

    /// Whether this is a hidden file/directory
    var isHidden: Bool {
        name.hasPrefix(".")
    }

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        // Children start as nil (not loaded) for directories
        self.children = isDirectory ? nil : []
    }

    /// Load children from disk (call when expanding)
    func loadChildren(includeHidden: Bool = false) {
        guard isDirectory, !isLoaded else { return }

        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            children = []
            return
        }

        children = contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { itemUrl -> LazyFileSystemItem? in
                let name = itemUrl.lastPathComponent
                if !includeHidden && name.hasPrefix(".") { return nil }

                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: itemUrl.path, isDirectory: &isDir)

                return LazyFileSystemItem(
                    name: name,
                    path: itemUrl.path,
                    isDirectory: isDir.boolValue
                )
            }
    }

    /// Unload children (to free memory)
    func unloadChildren() {
        guard isDirectory else { return }
        children = nil
        isExpanded = false
    }
}

// MARK: - Lazy Tree Row View

/// A single row in the lazy file tree
struct LazyFileTreeRow: View {
    var item: LazyFileSystemItem  // No wrapper needed - @Observable is automatically tracked
    let depth: Int
    let includeHidden: Bool
    let projectPath: String
    @Binding var selection: LazyFileSystemItem?

    private var isSelected: Bool {
        selection?.id == item.id
    }

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
                        toggleExpanded()
                    } label: {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
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

                // Loading indicator for directories being loaded
                if item.isDirectory && item.isExpanded && !item.isLoaded {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }

                // File extension badge
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
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = item
                if item.isDirectory {
                    toggleExpanded()
                }
            }
            .contextMenu {
                if !item.isDirectory {
                    Button("Create Version") {
                        ProjectManager.shared.createVersionByPath(filePath: item.path, projectPath: projectPath)
                    }
                }
            }

            // Children (if expanded and loaded)
            if item.isExpanded, let children = item.children {
                ForEach(children) { child in
                    LazyFileTreeRow(item: child, depth: depth + 1, includeHidden: includeHidden, projectPath: projectPath, selection: $selection)
                }
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.15)) {
            item.isExpanded.toggle()
        }

        if item.isExpanded && !item.isLoaded {
            // Load children in background
            Task {
                item.loadChildren(includeHidden: includeHidden)
            }
        } else if !item.isExpanded {
            // Free memory when collapsing
            item.unloadChildren()
        }
    }

    private var iconName: String {
        if item.isDirectory {
            return item.isExpanded ? "folder.fill" : "folder"
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

// MARK: - Main Lazy View

/// Displays the file tree with lazy loading - children loaded on expand
struct WholeTreeLazyTestView: View {
    let projectPath: String
    @Binding var selection: LazyFileSystemItem?

    /// Cache of tree state per project path (preserves expanded state when switching)
    @State private var projectTreeCache: [String: [LazyFileSystemItem]] = [:]
    @State private var includeHidden = false
    @State private var isLoading = true
    @State private var loadTime: TimeInterval = 0

    /// Current root items (from cache or freshly loaded)
    private var rootItems: [LazyFileSystemItem] {
        projectTreeCache[projectPath] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Lazy File Tree")
                    .font(.headline)

                Text("(\(String(format: "%.0fms", loadTime * 1000)))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Toggle("Show Hidden", isOn: $includeHidden)
                    .toggleStyle(.checkbox)
                    .onChange(of: includeHidden) { _, _ in
                        // Clear cache since hidden setting affects all projects
                        projectTreeCache.removeAll()
                        loadRootItems()
                    }

                Button {
                    loadRootItems()
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
                ProgressView("Loading root...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rootItems.isEmpty {
                ContentUnavailableView(
                    "No Files Found",
                    systemImage: "folder",
                    description: Text("The project folder is empty")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootItems) { item in
                            LazyFileTreeRow(item: item, depth: 0, includeHidden: includeHidden, projectPath: projectPath, selection: $selection)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadRootItemsIfNeeded()
        }
        .onChange(of: projectPath) { _, _ in
            loadRootItemsIfNeeded()
        }
    }

    /// Load root items only if not already cached for this project
    private func loadRootItemsIfNeeded() {
        if projectTreeCache[projectPath] != nil {
            isLoading = false
            return
        }
        loadRootItems(forceReload: false)
    }

    /// Force reload from disk (used by refresh button and hidden toggle)
    private func loadRootItems(forceReload: Bool = true) {
        isLoading = true

        Task {
            let startTime = Date()

            let fileManager = FileManager.default
            let url = URL(fileURLWithPath: projectPath)

            let contents = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: includeHidden ? [] : [.skipsHiddenFiles]
            )) ?? []

            let items = contents
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { itemUrl -> LazyFileSystemItem? in
                    let name = itemUrl.lastPathComponent
                    if !includeHidden && name.hasPrefix(".") { return nil }

                    var isDir: ObjCBool = false
                    fileManager.fileExists(atPath: itemUrl.path, isDirectory: &isDir)

                    return LazyFileSystemItem(
                        name: name,
                        path: itemUrl.path,
                        isDirectory: isDir.boolValue
                    )
                }

            let elapsed = Date().timeIntervalSince(startTime)

            await MainActor.run {
                projectTreeCache[projectPath] = items
                loadTime = elapsed
                isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selection: LazyFileSystemItem?
    WholeTreeLazyTestView(projectPath: "/Users/jonasbarsten/Development/Sordello", selection: $selection)
        .frame(width: 400, height: 600)
}

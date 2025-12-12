//
//  FileWatcher.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation

/// Type of file system change
enum FileChangeType: Sendable {
    case created
    case modified
    case deleted
    case renamed
}

/// A single file change event
struct FileChange: Sendable, Hashable {
    let path: String
    let type: FileChangeType
    let isDirectory: Bool
}

/// Watches directories for changes using FSEvents (includes all subdirectories)
class FileWatcher {
    static let shared = FileWatcher()

    private var streams: [String: FSEventStreamRef] = [:]
    private var callbacks: [String: ([FileChange]) -> Void] = [:]

    /// Pending changes to be batched (debounced)
    private var pendingChanges: [String: Set<FileChange>] = [:]
    private var debounceWorkItems: [String: DispatchWorkItem] = [:]
    private let debounceDelay: TimeInterval = 0.3  // seconds

    init() {}

    /// Start watching a directory and all its subdirectories for changes
    /// Also watches .sordello/files/ explicitly for version changes
    /// Callback receives batched file changes after debounce period
    func watch(at path: String, onChange: @escaping ([FileChange]) -> Void) {
        // Stop existing watcher for this path
        stopWatching(path: path)

        callbacks[path] = onChange
        pendingChanges[path] = []

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Watch both the project path and .sordello/files/ explicitly
        let sordelloFilesPath = (path as NSString).appendingPathComponent(K.sordello.filesPath)
        let pathsToWatch = [path, sordelloFilesPath] as CFArray

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, eventFlags, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

                for i in 0..<numEvents {
                    let changedPath = paths[i]
                    let flags = eventFlags[i]

                    // Allow .sordello/files/ (our managed version files)
                    let isInSordelloFiles = changedPath.contains("/\(K.sordello.filesPath)/")

                    // Skip all other hidden files/directories (starting with ".")
                    if !isInSordelloFiles && watcher.containsHiddenComponent(changedPath) {
                        continue
                    }

                    // Determine change type from flags
                    let isItemModified = (flags & UInt32(kFSEventStreamEventFlagItemModified)) != 0
                    let isItemCreated = (flags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                    let isItemRemoved = (flags & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
                    let isItemRenamed = (flags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
                    let isDirectory = (flags & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0

                    // Determine change type (prioritize in order: deleted > created > renamed > modified)
                    let changeType: FileChangeType?
                    if isItemRemoved {
                        changeType = .deleted
                    } else if isItemCreated {
                        changeType = .created
                    } else if isItemRenamed {
                        changeType = .renamed
                    } else if isItemModified {
                        changeType = .modified
                    } else {
                        changeType = nil
                    }

                    guard let type = changeType else { continue }

                    let change = FileChange(path: changedPath, type: type, isDirectory: isDirectory)

                    // Find which watched path this belongs to and queue the change
                    for watchedPath in watcher.callbacks.keys {
                        if changedPath.hasPrefix(watchedPath) {
                            watcher.queueChange(change, for: watchedPath)
                            break
                        }
                    }
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,  // Low latency - we do our own debouncing
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            print("FileWatcher: Failed to create stream for: \(path)")
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)

        streams[path] = stream
        print("FileWatcher: Now watching \(path) (+ .sordello/files/)")
    }

    /// Queue a change and reset the debounce timer
    private func queueChange(_ change: FileChange, for watchedPath: String) {
        pendingChanges[watchedPath, default: []].insert(change)

        // Cancel existing debounce timer
        debounceWorkItems[watchedPath]?.cancel()

        // Create new debounce timer
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushChanges(for: watchedPath)
        }
        debounceWorkItems[watchedPath] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    /// Flush pending changes and call the callback
    private func flushChanges(for watchedPath: String) {
        guard let changes = pendingChanges[watchedPath], !changes.isEmpty else { return }
        guard let callback = callbacks[watchedPath] else { return }

        // Clear pending changes
        pendingChanges[watchedPath] = []
        debounceWorkItems[watchedPath] = nil

        // Convert to array and call callback
        let changesArray = Array(changes)
        print("FileWatcher: Flushing \(changesArray.count) change(s) for \(watchedPath)")
        for change in changesArray {
            print("  - \(change.type): \(change.path)")
        }

        callback(changesArray)
    }

    /// Check if a path contains any hidden component (starting with ".")
    private func containsHiddenComponent(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }

    /// Stop watching a specific directory
    func stopWatching(path: String) {
        if let stream = streams[path] {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streams.removeValue(forKey: path)
            callbacks.removeValue(forKey: path)
            pendingChanges.removeValue(forKey: path)
            debounceWorkItems[path]?.cancel()
            debounceWorkItems.removeValue(forKey: path)
            print("FileWatcher: Stopped watching \(path)")
        }
    }

    /// Stop all file watchers
    func stopAll() {
        for (path, stream) in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            debounceWorkItems[path]?.cancel()
            print("FileWatcher: Stopped watching \(path)")
        }
        streams.removeAll()
        callbacks.removeAll()
        pendingChanges.removeAll()
        debounceWorkItems.removeAll()
    }
}
